#import <MulleObjCPosixFoundation/MulleObjCPosixFoundation.h>


int   main( int argc, char *argv[])
{
   NSFileManager   *fileManager;
   NSString        *abspath;
   BOOL            rval;

   fileManager = [NSFileManager defaultManager];

   // really start empty
   [fileManager removeItemAtPath:@"testdir"
                           error:NULL];

   // 1. whole chain is new
   rval = [fileManager createDirectoryAtPath:@"testdir/a/b/c"
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:NULL];
   mulle_printf( "all-new                   rval=%d exists=%d\n",
                 (int) rval,
                 (int) [fileManager fileExistsAtPath:@"testdir/a/b/c"]);

   // 2. two levels below something that exists - FAILS on buggy code
   rval = [fileManager createDirectoryAtPath:@"testdir/x/y"
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:NULL];
   mulle_printf( "under-existing            rval=%d exists=%d\n",
                 (int) rval,
                 (int) [fileManager fileExistsAtPath:@"testdir/x/y"]);

   // 3. a component that already exists is not an error
   rval = [fileManager createDirectoryAtPath:@"testdir/a/b"
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:NULL];
   mulle_printf( "component-exists          rval=%d exists=%d\n",
                 (int) rval,
                 (int) [fileManager fileExistsAtPath:@"testdir/a/b"]);

   // 4. attributes must be applied to each created component, not the target
   rval = [fileManager createDirectoryAtPath:@"testdir/attr/p/q"
                    withIntermediateDirectories:YES
                                     attributes:@{ NSFilePosixPermissions: @0700 }
                                          error:NULL];
   mulle_printf( "with-attributes           rval=%d exists=%d\n",
                 (int) rval,
                 (int) [fileManager fileExistsAtPath:@"testdir/attr/p/q"]);

   // 5. absolute path: the walk must handle the leading "/" component
   abspath = [[fileManager currentDirectoryPath] stringByAppendingPathComponent:@"testdir/abs/x/y"];
   rval    = [fileManager createDirectoryAtPath:abspath
                        withIntermediateDirectories:YES
                                         attributes:nil
                                              error:NULL];
   mulle_printf( "absolute                  rval=%d exists=%d\n",
                 (int) rval,
                 (int) [fileManager fileExistsAtPath:abspath]);

   [fileManager removeItemAtPath:@"testdir"
                           error:NULL];
   return( 0);
}
