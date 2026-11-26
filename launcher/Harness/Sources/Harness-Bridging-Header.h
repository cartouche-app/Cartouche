//
//  Harness-Bridging-Header.h
//  CartoucheHarness
//
//  What the launcher's Swift and LiveContainer's Swift files see of
//  Objective-C in the app: UIKit, as LiveContainer's own headers bring it
//  in; LiveContainer's unpacker (unarchive.h, from app/LiveContainer, which
//  harness.sh copies into Build/LiveContainer); the private initializer of
//  a game's preferences (FoundationPrivate.h); the private Security
//  calls CartoucheDevice.swift makes, answered as an iPhone with Increased
//  Memory Limit would, as the launcher's gallery answers them; and how a
//  game's process asks for the keyboard, which brings it the controllers
//  (launcher/LiveProcessSupport/CartoucheGuestControllers.h); and how it
//  mixes its sound with other apps' (launcher/Guest/
//  CartoucheOtherAudioSession.h).
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "unarchive.h"
#import "../../LiveProcessSupport/CartoucheGuestControllers.h"
#import "../../Guest/CartoucheOtherAudioSession.h"

@interface NSUserDefaults (HarnessPrivate)
- (instancetype)_initWithSuiteName:(NSString *)suiteName container:(NSURL *)container;
@end

static inline void *SecTaskCreateFromSelf(CFAllocatorRef allocator) {
    return NULL;
}

static inline CFTypeRef SecTaskCopyValueForEntitlement(void *task, CFStringRef key, CFErrorRef *error) {
    return CFRetain(kCFBooleanTrue);
}
