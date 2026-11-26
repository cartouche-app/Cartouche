//
//  CartoucheOtherAudioSession.m
//  Cartouche
//
//  Lets the player's music or podcast play on under a game's sound, when
//  they turn on Keep other apps' sound (System › While a game runs): the
//  game's audio session mixes with other apps' sound instead of stopping it.
//
//  nxnative's iOS front end sets the game's audio session to the Playback
//  category, without options (front_ios.m, front_ios_audio_session): at the
//  game's start, as it comes back to the front, after an interruption, a
//  call, Siri or an alarm, and after iOS resets its media services. A
//  session of that category that does not mix stops other apps' sound as it
//  becomes active. Here, every category the game's process sets goes with
//  AVAudioSessionCategoryOptionMixWithOthers too, among the categories that
//  take it (Playback, PlayAndRecord and MultiRoute), each time nxnative sets
//  it again, so that the game's sound plays over the other apps' sound.
//  nxnative itself is untouched. The rest stays as nxnative sets it: the
//  Playback category plays with the Ring/Silent switch on silent, mixing or
//  not; its sound goes where iOS sends every app's, to a TV by cable or
//  AirPlay too; and a call or Siri still interrupts it, as it interrupts
//  the other apps', which nxnative answers by setting the session again.
//
//  Cartouche writes the player's choice in the game's data folder as Play
//  starts the game, a file this one reads (CartoucheOtherAudioIsKept);
//  CartoucheOtherAudio.m reads it in the game's process, and calls
//  CartoucheOtherAudioKeep. Without the file, the game's session stays as
//  nxnative sets it: nothing here touches it.
//
//  app/scripts/prepare.sh copies this folder into LiveContainer's Tweaks
//  folder, which builds into LiveContainerShared: the framework every
//  LiveContainer process loads first, a game's included, whether the game
//  runs behind the console, in LiveProcess, or in Cartouche's place. This
//  file does not link AVFAudio, which LiveContainerShared would then load
//  in every process of Cartouche's, the built-in SideStore's included: it
//  finds AVAudioSession and its names at run time, in a game, which links
//  AVFAudio itself. It needs neither LiveContainer nor UIKit, so that the
//  launcher's harness runs it with the Simulator's AVAudioSession
//  (launcher/Harness/Tests/OtherAudioTests.swift).
//

@import Foundation;
#include <dlfcn.h>
#include <objc/runtime.h>
#import "CartoucheOtherAudioSession.h"

NSString *const CartoucheOtherAudioFile = @"Library/Cartouche/OtherAudio.plist";
NSString *const CartoucheOtherAudioKey = @"keep";

/// AVAudioSessionCategoryOptionMixWithOthers, as AVFAudio's headers number it.
static const NSUInteger CartoucheOtherAudioMix = 0x1;

// AVAudioSession's, found at run time.
@protocol CartoucheOtherAudioAVAudioSession
+ (id)sharedInstance;
- (NSString *)category;
- (NSString *)mode;
- (NSUInteger)categoryOptions;
- (BOOL)setCategory:(NSString *)category error:(NSError **)error;
- (BOOL)setCategory:(NSString *)category withOptions:(NSUInteger)options error:(NSError **)error;
- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(NSUInteger)options error:(NSError **)error;
- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode routeSharingPolicy:(NSUInteger)policy
            options:(NSUInteger)options error:(NSError **)error;
@end

/// Whether the categories this process sets mix with other apps' sound.
static BOOL keeping;
/// The categories that take the option: AVAudioSessionCategoryPlayback,
/// AVAudioSessionCategoryPlayAndRecord and AVAudioSessionCategoryMultiRoute.
static NSArray<NSString *> *mixable;
static BOOL (*setCategory)(id, SEL, NSString *, NSError **);
static BOOL (*setCategoryOptions)(id, SEL, NSString *, NSUInteger, NSError **);
static BOOL (*setCategoryModeOptions)(id, SEL, NSString *, NSString *, NSUInteger, NSError **);
static BOOL (*setCategoryModePolicyOptions)(id, SEL, NSString *, NSString *, NSUInteger, NSUInteger, NSError **);

BOOL CartoucheOtherAudioIsKept(NSString *home) {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[home stringByAppendingPathComponent:CartoucheOtherAudioFile]];
    if (![plist isKindOfClass:NSDictionary.class]) return NO;
    id keep = plist[CartoucheOtherAudioKey];
    return [keep isKindOfClass:NSNumber.class] && [keep boolValue];
}

/// The options a category is set with: with the mix too, while the player
/// keeps other apps' sound, for a category that takes it.
static NSUInteger CartoucheOtherAudioOptions(NSString *category, NSUInteger options) {
    return keeping && [mixable containsObject:category] ? options | CartoucheOtherAudioMix : options;
}

/// -[AVAudioSession setCategory:error:], as nxnative sets its category: the
/// category alone, which takes no option, is set with the mix alone.
static BOOL CartoucheOtherAudioSetCategory(id self, SEL _cmd, NSString *category, NSError **error) {
    NSUInteger options = CartoucheOtherAudioOptions(category, 0);
    if (options) return setCategoryOptions(self, @selector(setCategory:withOptions:error:), category, options, error);
    return setCategory(self, _cmd, category, error);
}

/// -[AVAudioSession setCategory:withOptions:error:].
static BOOL CartoucheOtherAudioSetCategoryOptions(id self, SEL _cmd, NSString *category, NSUInteger options, NSError **error) {
    return setCategoryOptions(self, _cmd, category, CartoucheOtherAudioOptions(category, options), error);
}

/// -[AVAudioSession setCategory:mode:options:error:].
static BOOL CartoucheOtherAudioSetCategoryModeOptions(id self, SEL _cmd, NSString *category, NSString *mode,
                                                      NSUInteger options, NSError **error) {
    return setCategoryModeOptions(self, _cmd, category, mode, CartoucheOtherAudioOptions(category, options), error);
}

/// -[AVAudioSession setCategory:mode:routeSharingPolicy:options:error:].
static BOOL CartoucheOtherAudioSetCategoryModePolicyOptions(id self, SEL _cmd, NSString *category, NSString *mode,
                                                            NSUInteger policy, NSUInteger options, NSError **error) {
    return setCategoryModePolicyOptions(self, _cmd, category, mode, policy, CartoucheOtherAudioOptions(category, options), error);
}

/// One of AVFAudio's names, as AVFAudio itself holds it.
static NSString *CartoucheOtherAudioName(const char *symbol) {
    NSString *__unsafe_unretained *name = (NSString *__unsafe_unretained *)dlsym(RTLD_DEFAULT, symbol);
    return name ? *name : nil;
}

/// AVAudioSession's calls that set its category, through this file's, once:
/// whether this process has them all.
static BOOL CartoucheOtherAudioHook(void) {
    static dispatch_once_t once;
    static BOOL hooked;
    dispatch_once(&once, ^{
        Class session = NSClassFromString(@"AVAudioSession");
        NSString *playback = CartoucheOtherAudioName("AVAudioSessionCategoryPlayback");
        NSString *playAndRecord = CartoucheOtherAudioName("AVAudioSessionCategoryPlayAndRecord");
        NSString *multiRoute = CartoucheOtherAudioName("AVAudioSessionCategoryMultiRoute");
        Method alone = class_getInstanceMethod(session, @selector(setCategory:error:));
        Method withOptions = class_getInstanceMethod(session, @selector(setCategory:withOptions:error:));
        Method withMode = class_getInstanceMethod(session, @selector(setCategory:mode:options:error:));
        Method withPolicy = class_getInstanceMethod(session, @selector(setCategory:mode:routeSharingPolicy:options:error:));
        if (!session || !playback || !playAndRecord || !multiRoute || !alone || !withOptions || !withMode || !withPolicy) return;
        mixable = @[playback, playAndRecord, multiRoute];
        setCategory = (BOOL (*)(id, SEL, NSString *, NSError **))method_setImplementation(alone, (IMP)CartoucheOtherAudioSetCategory);
        setCategoryOptions = (BOOL (*)(id, SEL, NSString *, NSUInteger, NSError **))
            method_setImplementation(withOptions, (IMP)CartoucheOtherAudioSetCategoryOptions);
        setCategoryModeOptions = (BOOL (*)(id, SEL, NSString *, NSString *, NSUInteger, NSError **))
            method_setImplementation(withMode, (IMP)CartoucheOtherAudioSetCategoryModeOptions);
        setCategoryModePolicyOptions = (BOOL (*)(id, SEL, NSString *, NSString *, NSUInteger, NSUInteger, NSError **))
            method_setImplementation(withPolicy, (IMP)CartoucheOtherAudioSetCategoryModePolicyOptions);
        hooked = YES;
    });
    return hooked;
}

BOOL CartoucheOtherAudioKeep(BOOL keep) {
    if (!CartoucheOtherAudioHook()) return NO;
    keeping = keep;
    if (!keep) return YES;
    // A category set before, which does not mix yet, mixes from now on.
    id<CartoucheOtherAudioAVAudioSession> session = [NSClassFromString(@"AVAudioSession") sharedInstance];
    NSString *category = [session category];
    NSUInteger options = [session categoryOptions];
    if ([mixable containsObject:category] && !(options & CartoucheOtherAudioMix)) {
        // Through CartoucheOtherAudioSetCategoryModeOptions, which adds the mix.
        NSError *error = nil;
        if (![session setCategory:category mode:[session mode] options:options error:&error]) {
            NSLog(@"[Cartouche] the game's sound could not mix with other apps' yet: %@", error);
        }
    }
    return YES;
}
