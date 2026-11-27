//
//  CartoucheGameTexts.m
//  Cartouche
//
//  In the process of one of nxnative's games, nxnative's prompt that waits
//  for more players and its gear menu over the game in the language
//  Cartouche speaks, the words the Mac gives its games: Play writes them in
//  the game's data folder (launcher/Sources/CartoucheGameTexts.swift), and
//  this puts them in the game's environment
//  (CartoucheGameTextsEnvironment.m). Behind the console, in LiveProcess,
//  and in Cartouche's place alike. Only in nxnative's games, never in
//  Cartouche's own screens, in the built-in SideStore or in another app.
//
//  app/scripts/prepare.sh copies this folder into LiveContainer's Tweaks
//  folder, which builds into LiveContainerShared, loaded before UIKit and
//  before the game: like CartoucheOtherAudio.m, this file names UIKit's
//  notification by its string. It starts once the game has finished
//  launching, as UIKit says so, when LiveContainer has set HOME to the
//  game's data folder, and nxnative's main.m has read the game's env.txt
//  files: long before nxnative shows its prompt or its menu, which read
//  their texts as they show.
//

@import Foundation;
#include "../../utils.h"
#import "CartoucheGameTextsEnvironment.h"

static id launchObserver;

/// Whether this process runs one of nxnative's games: nxnative puts its dm
/// folder in each, and DMLanguage in their Info.plist
/// (CartouchePlayTimeCounter.m).
static BOOL CartoucheGameTextsIsGame(void) {
    if (!NSUserDefaults.lcGuestAppId || NSUserDefaults.isSideStore) return NO;
    NSBundle *game = NSBundle.mainBundle;
    return [NSFileManager.defaultManager fileExistsAtPath:[game.bundlePath stringByAppendingPathComponent:@"dm"]]
        || game.infoDictionary[@"DMLanguage"] != nil;
}

static void CartoucheGameTextsStart(void) {
    const char *home = getenv("HOME");
    if (!home || !CartoucheGameTextsIsGame()) return;
    NSArray<NSString *> *set = CartoucheGameTextsApply(@(home));
    if (set.count) {
        NSLog(@"[Cartouche] nxnative's texts in Cartouche's language: %@", [set componentsJoinedByString:@", "]);
    }
}

__attribute__((constructor))
static void CartoucheGameTextsInit(void) {
    // Without a queue, UIKit calls this as it says the game has finished
    // launching, before it gives the game its first scene.
    launchObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:@"UIApplicationDidFinishLaunchingNotification"
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:launchObserver];
        launchObserver = nil;
        CartoucheGameTextsStart();
    }];
}
