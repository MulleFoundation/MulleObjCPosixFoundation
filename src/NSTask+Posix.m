//
//  NSTask+Posix.m
//  MulleObjCOSFoundation
//
//  Copyright (c) 2017 Nat! - Mulle kybernetiK.
//  All rights reserved.
//
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//
//  Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  Neither the name of Mulle kybernetiK nor the names of its contributors
//  may be used to endorse or promote products derived from this software
//  without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
//
//  There used to be a fork, an execve, three dup2 and two closes in here, plus
//  a waitpid and a kill. All of that is mulle-spawn now, which does the same
//  thing on Windows and has the tests to show it -- and all of the *lifecycle*
//  that used to follow it is `NSTask.m`, because there is nothing POSIX about
//  it once the child is running.
//
//  What is left in this file is `launch`, which is the only part that differs
//  from the Windows one: what the three standard streams are, and what the
//  parent's own end of each of them has to be marked with so that the child
//  does not inherit it.
//
//  The reference for what this has to keep doing is test/NSTask in
//  MulleObjCOSFoundation, and the plan is SPAWN-TASK-PLAN.md in mulle-spawn.
//
#define _XOPEN_SOURCE 700
#define _DEFAULT_SOURCE

#import "import-private.h"

#import <MulleObjCOSBaseFoundation/NSTask-Private.h>
#import <MulleObjCOSBaseFoundation/NSFileManager.h>
#import <MulleObjCOSBaseFoundation/NSPipe.h>
#import <MulleObjC/NSDebug.h>

// other libraries of MulleObjCPosixFoundation
#import "NSError+Posix.h"

// std-c and dependencies
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

// mulle-spawn is a constituent of mulle-core and arrives with the Objective-C
// runtime's dependency on it, so the include is technically already there -- it
// is spelled out anyway, because nothing else in this file would tell a reader
// where mulle_spawn_* is from.
#include <mulle-spawn/mulle-spawn.h>


/*
 * The parent's own end of a pipe must not reach the child. The child inherits
 * every descriptor of ours a `fork` can see, and for stdin that includes the
 * end the *parent* writes on -- so a child that reads its stdin to EOF would
 * never get there, while its parent had long since closed its side.
 *
 * `FD_CLOEXEC` is the portable POSIX way to say "not this one": it is set
 * before the fork, so the child's copy of it carries the flag, and the
 * descriptor is closed as the child reaches its exec. It is taken back
 * afterwards because the flag lives in the per-process descriptor table and
 * the child already has its own copy -- the parent keeps its descriptor
 * usable, which is the whole point.
 *
 * A descriptor below 3 is left alone: those are the process's own standard
 * streams, and when one of them is the property, inheriting it is exactly what
 * was asked for.
 *
 * Returns the previous flags, or -1 if nothing was changed.
 */
static int   markCloseOnExec( int fd)
{
   int   flags;

   if( fd < 3)
      return( -1);

   flags = fcntl( fd, F_GETFD);
   if( flags == -1)
      return( -1);

   if( flags & FD_CLOEXEC)
      return( -1);

   if( fcntl( fd, F_SETFD, flags | FD_CLOEXEC) == -1)
      return( -1);

   return( flags);
}


static void   restoreCloseOnExec( int fd, int previousFlags)
{
   if( previousFlags < 0)
      return;

   (void) fcntl( fd, F_SETFD, previousFlags);
}


@implementation NSTask (Posix)

@dependency NSTask;


- (void) launch
{
   struct mulle_spawn_options   options;
   struct mulle_spawn_handle    *handle;
   char                         **argv;
   char                         **envp;
   char                         **arguments;
   void                         *envAllocation;
   char                         *path;
   BOOL                         isDir;
   NSUInteger                   argc;
   NSUInteger                   i;
   int                          child[ 3];    // what the child gets to talk on
   int                          parent[ 3];   // what the parent keeps
   int                          kept[ 3];     // the flags markCloseOnExec set
   int                          rval;
   int                          err;

   MulleObjCSetPosixErrorDomain();

   //
   // The child runs in the directory that was set (if any). mulle-spawn
   // refuses the same directory for the same reason, but its complaint is an
   // errno -- and a caller who named a directory is owed the name of it.
   //
   if( _directoryPath)
      if( ! [[NSFileManager defaultManager] fileExistsAtPath:_directoryPath
                                                 isDirectory:&isDir] || ! isDir)
         MulleObjCThrowInvalidArgumentException( @"%@ current directory \"%@\" is not an existing directory",
                                                 self, _directoryPath);

   path = [_launchPath fileSystemRepresentation];
   argc = [_arguments count];

   argv       = mulle_malloc( (argc + 2) * sizeof( char *));
   argv[ 0]   = path;
   argv[argc + 1] = NULL;

   assert( sizeof( id) == sizeof( char *));
   arguments = &argv[ 1];
   [_arguments getObjects:(id *) arguments];
   for( i = 0; i < argc; i++)
      arguments[ i] = (char *) [(id) arguments[ i] UTF8String];

   envp = mulleNSTaskEnvironmentStrings( _environment, &envAllocation);

   mulle_spawn_options_init( &options);
   options.env       = envp;
   options.directory = _directoryPath ? [_directoryPath fileSystemRepresentation] : NULL;

   //
   // The child reads its stdin where the caller writes, and writes its stdout
   // and stderr where the caller reads. The other end each time is the
   // parent's, and it is the one the child must not be left holding.
   //
   child[ 0]  = [_standardInput  _fileDescriptorForReading];
   child[ 1]  = [_standardOutput _fileDescriptorForWriting];
   child[ 2]  = [_standardError  _fileDescriptorForWriting];

   parent[ 0] = [_standardInput  _fileDescriptorForWriting];
   parent[ 1] = [_standardOutput _fileDescriptorForReading];
   parent[ 2] = [_standardError  _fileDescriptorForReading];

   kept[ 0] = kept[ 1] = kept[ 2] = -1;

   for( i = 0; i < 3; i++)
   {
      if( ! child[ i])
         continue;

      kept[ i] = markCloseOnExec( parent[ i]);

      switch( i)
      {
      case 0  : options.in_mode       = MULLE_SPAWN_DESCRIPTOR;
                options.in_descriptor  = child[ 0];
                break;

      case 1  : options.out_mode      = MULLE_SPAWN_DESCRIPTOR;
                options.out_descriptor = child[ 1];
                break;

      default : options.err_mode      = MULLE_SPAWN_DESCRIPTOR;
                options.err_descriptor = child[ 2];
                break;
      }
   }

   if( NSDebugEnabled)
   {
      mulle_fprintf( stderr, "task %d launches \"%s\"", (int) getpid(), path);
      for( i = 0; i < argc; i++)
         mulle_fprintf( stderr, " %s", arguments[ i]);
      mulle_fprintf( stderr, "\n");
   }

   handle = mulle_malloc( sizeof( struct mulle_spawn_handle));
   rval   = mulle_spawn_open_with_options( handle, argv, &options);
   err    = errno;

   for( i = 0; i < 3; i++)
      restoreCloseOnExec( parent[ i], kept[ i]);

   mulle_free( envAllocation);
   mulle_free( argv);

   //
   // A child that could not be started at all is no longer a launch that
   // "succeeded" and a task that reports exit 127: the caller is told, and
   // `errno` says why. mulle-spawn waits for the child to reach its exec
   // before returning, so a 0 here means the program really is running.
   //
   if( rval == -1)
   {
      mulle_free( handle);

      errno = err;
      MulleObjCThrowInvalidArgumentException( @"%@ could not launch \"%@\" (%s)",
                                              self, _launchPath, strerror( err));
   }

   _pid        = (int) handle->pid;
   _taskHandle = handle;
   _status     = _NSTaskIsRunning;

   //
   // The child has its own copies of these now, and the parent still holding
   // the child's end of a pipe is what keeps `readDataToEndOfFile` from ever
   // finding EOF. Only a pipe's end is given up: a descriptor of the caller's
   // own -- a file, say -- stays the caller's, exactly as mulle-spawn's
   // descriptor mode promises.
   //
   // It is given up through the NSPipe that owns it rather than with a raw
   // `close`, so that the fd and the object agree afterwards: a later
   // `closeFile` on it is then a no-op instead of a second close of a number
   // the system may have handed out again.
   //
   if( [_standardInput isKindOfClass:[NSPipe class]])
      [[_standardInput fileHandleForReading] closeFile];
   if( [_standardOutput isKindOfClass:[NSPipe class]])
      [[_standardOutput fileHandleForWriting] closeFile];
   if( [_standardError isKindOfClass:[NSPipe class]])
      [[_standardError fileHandleForWriting] closeFile];
}

@end
