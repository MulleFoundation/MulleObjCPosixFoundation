#import <MulleObjCPosixFoundation/MulleObjCPosixFoundation.h>
#import <MulleObjC/NSDebug.h>

//
// This test code is there to see if your class has problems with
// the TAO-dilemma. Its superfluous if your class is MulleObjCThreadSafe.
//
// The mulleTAOTestSetup should configure the receiver as inconveniently as
// possible, meaning make all object properties (and other instance variable
// references to objects) non-threadsafe  (whereit makes sense).
//
@implementation NSFileHandle (TAOTest)

- (void) mulleTAOTestSetup:(id) arg
{
   MULLE_C_UNUSED( arg);

   // [self setBar:[Bar object]];
}


//
// See if you can avoid `MulleObjCTAOCallerRemovesFromCurrentPool`.
// If yes, then implement this method in your class. The default strategy is
// `MulleObjCTAOCallerRemovesFromCurrentPool`. If you need it not to
// crash, you do not need to implement anything. The test default is
// there as an impetus to make it better.
//
+ (MulleObjCTAOStrategy) mulleTAOStrategy
{
//    return( MulleObjCTAOCallerRemovesFromAllPools);
//    return( MulleObjCTAOCallerRemovesFromCurrentPool);
//    return( MulleObjCTAOKnownThreadSafe);
    return( MulleObjCTAOKnownThreadSafeMethods);
//    return( MulleObjCTAOReceiverPerformsFinalize);
//
}

@end


int   main( int argc, char *argv[])
{
   // either add all classes here, or copy this test for each class
   MulleObjCTAOTest( [NSFileHandle class], nil);

   return( 0);
}
