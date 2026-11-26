//
//  CartoucheOtherAudio.m
//  Cartouche
//
//  In the process of one of nxnative's games, whether the player keeps
//  other apps' sound while it plays (System › While a game runs): as Play
//  starts the game, Cartouche writes the player's choice in the game's data
//  folder (launcher/Sources/CartoucheOtherAudio.swift); while it says so,
//  the game's audio session mixes with other apps' sound
//  (CartoucheOtherAudioSession.m). Behind the console, in LiveProcess, and
//  in Cartouche's place alike. Only in nxnative's games, never in
//  Cartouche's own screens, in the built-in SideStore or in another app.
//
//  app/scripts/prepare.sh copies this folder into LiveContainer's Tweaks
//  folder, which builds into LiveContainerShared, loaded before UIKit and
//  before the game: like CartouchePlayTimeCounter.m, this file names
//  UIKit's notification by its string. It starts once the game has
//  finished launching, as UIKit says so, when LiveContainer has set HOME to
//  the game's data folder, and before the game's first scene, where
//  nxnative sets its audio session (main.m, front_ios_boot).
//

@import Foundation;
#include "../../utils.h"
#import "CartoucheOtherAudioSession.h"

static id launchObserver;

/// Whether this process runs one of nxnative's games: nxnative puts its dm
/// folder in each, and DMLanguage in their Info.plist
/// (CartouchePlayTimeCounter.m).
static BOOL CartoucheOtherAudioIsGame(void) {
    if (!NSUserDefaults.lcGuestAppId || NSUserDefaults.isSideStore) return NO;
    NSBundle *game = NSBundle.mainBundle;
    return [NSFileManager.defaultManager fileExistsAtPath:[game.bundlePath stringByAppendingPathComponent:@"dm"]]
        || game.infoDictionary[@"DMLanguage"] != nil;
}

static void CartoucheOtherAudioStart(void) {
    const char *home = getenv("HOME");
    if (!home || !CartoucheOtherAudioIsGame() || !CartoucheOtherAudioIsKept(@(home))) return;
    if (CartoucheOtherAudioKeep(YES)) {
        NSLog(@"[Cartouche] the game's sound mixes with other apps', as the player keeps it: their music or podcast plays on");
    } else {
        NSLog(@"[Cartouche] this process has not AVAudioSession's calls that set its category: the game's sound stops other apps', as without the setting");
    }
}

__attribute__((constructor))
static void CartoucheOtherAudioInit(void) {
    // Without a queue, UIKit calls this as it says the game has finished
    // launching, before it gives the game its first scene.
    launchObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:@"UIApplicationDidFinishLaunchingNotification"
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:launchObserver];
        launchObserver = nil;
        CartoucheOtherAudioStart();
    }];
}
