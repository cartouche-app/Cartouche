//
//  CartoucheGameTextsEnvironment.m
//  Cartouche
//
//  In the process of one of nxnative's games, nxnative's texts in the
//  language Cartouche speaks: the prompt that waits for more players
//  (DM_CTRL_PROMPT_TEXT) and the gear menu over the game
//  (DM_GAME_MENU_TEXT), which nxnative reads from its environment as it
//  shows them (DmGamepad.m, GameMenu.swift), and writes in English without
//  them. As Play starts the game, Cartouche writes them in the game's data
//  folder (launcher/Sources/CartoucheGameTexts.swift); this puts them in
//  the game's environment, unless the game's env.txt or its start sets
//  them: nxnative's main.m has put those there before the game finished
//  launching, and they stay (docs/decisions/179.md).
//
//  app/scripts/prepare.sh copies this folder into LiveContainer's Tweaks
//  folder, which builds into LiveContainerShared, loaded in every game
//  behind the console, in LiveProcess, and in Cartouche's place;
//  CartoucheGameTexts.m calls this once the game has finished launching.
//  It needs neither LiveContainer nor UIKit, so that the launcher's harness
//  runs it (launcher/Harness/Tests/PlayTests.swift).
//

@import Foundation;
#include <stdlib.h>
#import "CartoucheGameTextsEnvironment.h"

NSString *const CartoucheGameTextsFile = @"Library/Cartouche/GameTexts.plist";

NSArray<NSString *> *CartoucheGameTextsVariables(void) {
    return @[@"DM_CTRL_PROMPT_TEXT", @"DM_GAME_MENU_TEXT"];
}

NSArray<NSString *> *CartoucheGameTextsApply(NSString *home) {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[home stringByAppendingPathComponent:CartoucheGameTextsFile]];
    NSDictionary *environment = [plist isKindOfClass:NSDictionary.class] ? plist[@"environment"] : nil;
    if (![environment isKindOfClass:NSDictionary.class]) return @[];
    NSMutableArray<NSString *> *set = [NSMutableArray array];
    for (NSString *variable in CartoucheGameTextsVariables()) {
        NSString *text = environment[variable];
        if (![text isKindOfClass:NSString.class] || !text.length) continue;
        // The game's env.txt, or its start, says its own.
        if (getenv(variable.UTF8String)) continue;
        if (setenv(variable.UTF8String, text.UTF8String, 0) == 0) [set addObject:variable];
    }
    return set;
}
