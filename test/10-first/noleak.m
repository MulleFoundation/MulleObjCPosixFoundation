#import <MulleObjCPosixFoundation/MulleObjCPosixFoundation.h>


int   main( int argc, char *argv[])
{
#if defined( __MULLE_OBJC__)
   if( mulle_objc_global_check_universe( __MULLE_OBJC_UNIVERSENAME__) != mulle_objc_universe_is_ok)
      return( 1);
#endif

   // needs MulleFoundation for the NSConstantString class. If this is just
   // linked with MulleObjC this will crash because of the %@ conversion
   mulle_printf( "%@\n", @"VfL Bochum <missing number, please fix>");
   return( 0);
}
