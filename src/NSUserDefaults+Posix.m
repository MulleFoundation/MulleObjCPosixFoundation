//
//  NSUserDefaults+Posix.m
//  MulleObjCOSFoundation
//
//  Copyright (c) 2026 Nat! - Mulle kybernetiK.
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
#define _XOPEN_SOURCE 700

#import "import-private.h"

// other libraries of MulleObjCOSBaseFoundation
#import <MulleObjCOSBaseFoundation/NSDictionary+OSBase.h>
#import <MulleObjCOSBaseFoundation/NSFileManager.h>
#import <MulleObjCOSBaseFoundation/NSPathUtilities.h>
#import <MulleObjCOSBaseFoundation/NSString+OSBase.h>
#import <MulleObjCOSBaseFoundation/NSUserDefaults.h>

// std-c and dependencies
#include <stdlib.h>


static NSString   *persistentDomainPath( NSUserDefaults *self)
{
   char        *s;
   NSString    *dir;
   NSString    *name;

   s = getenv( "MULLE_USER_DEFAULTS_DIR");
   if( s && *s)
      dir = [NSString stringWithUTF8String:s];
   else
      dir = [NSHomeDirectory() stringByAppendingPathComponent:@".config"];

   name = [[self _defaultsIdentifier] stringByAppendingPathExtension:@"plist"];
   return( [dir stringByAppendingPathComponent:name]);
}


@implementation NSUserDefaults( Posix)

@dependency NSUserDefaults( Persistent);


- (BOOL) _loadPersistentDomain:(NSMutableDictionary *) domain
{
   NSDictionary   *dictionary;
   NSString       *path;

   path       = persistentDomainPath( self);
   dictionary = [NSDictionary dictionaryWithContentsOfFile:path];
   if( ! dictionary)
      return( NO);

   [domain addEntriesFromDictionary:dictionary];
   return( YES);
}


- (BOOL) _savePersistentDomain:(NSDictionary *) domain
{
   NSFileManager   *manager;
   NSString        *path;

   path    = persistentDomainPath( self);
   manager = [NSFileManager defaultManager];

   if( ! [domain count])
   {
      [manager removeItemAtPath:path
                          error:NULL];
      return( YES);
   }

   [manager createDirectoryAtPath:[path stringByDeletingLastPathComponent]
       withIntermediateDirectories:YES
                        attributes:nil
                             error:NULL];

   return( [domain writeToFile:path
                    atomically:YES]);
}

@end
