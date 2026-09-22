#import <MulleObjCPosixFoundation/MulleObjCPosixFoundation.h>
#include <stdlib.h>
#include <string.h>


static void   show( NSString *label, BOOL value)
{
   mulle_printf( "%s=%d\n", [label UTF8String], (int) value);
}


int   main( int argc, char *argv[])
{
   NSProcessInfo   *info;
   NSArray         *arguments;
   NSDictionary    *environment;
   NSString        *string;
   NSString        *guid1;
   NSString        *guid2;

   info = [NSProcessInfo processInfo];

   show( @"singleton", [NSProcessInfo processInfo] == info);

   arguments = [info arguments];
   show( @"args.notnil", arguments != nil && [arguments count] >= 1);

   environment = [info environment];
   show( @"env.notnil", environment != nil && [environment count] > 0);

   show( @"exepath", [[info _executablePath] length] > 0);
   show( @"processname", [[info processName] length] > 0);
   show( @"pid", [info processIdentifier] > 0);
   show( @"hostname", [[info hostName] length] > 0);
   show( @"osname", [[info operatingSystemName] length] > 0);
   show( @"osversion", [[info operatingSystemVersionString] length] > 0);

   guid1 = [info globallyUniqueString];
   guid2 = [info globallyUniqueString];
   show( @"guid.notnil", guid1 != nil && [guid1 length] > 0);
   show( @"guid.unique", ![guid1 isEqualToString:guid2]);

   // environment was cached above, so the setter must update the cache
   [info mulleSetEnvironmentValue:@"bar"
                           forKey:@"MULLE_PI_TEST"];
   string = [[info environment] objectForKey:@"MULLE_PI_TEST"];
   show( @"setenv.cached", [string isEqualToString:@"bar"]);
   show( @"setenv.process", getenv( "MULLE_PI_TEST") &&
                            strcmp( getenv( "MULLE_PI_TEST"), "bar") == 0);

   [info mulleSetEnvironmentValue:nil
                           forKey:@"MULLE_PI_TEST"];
   show( @"unsetenv.cached", [[info environment] objectForKey:@"MULLE_PI_TEST"] == nil);
   show( @"unsetenv.process", getenv( "MULLE_PI_TEST") == NULL);

   return( 0);
}
