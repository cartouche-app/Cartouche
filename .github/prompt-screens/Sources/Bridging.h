//
//  Bridging.h
//  PromptScreens
//
//  For the screenshots of PR #367 alone, removed before it merges.
//

#import <UIKit/UIKit.h>
#import "../../../launcher/Guest/CartoucheGameTextsEnvironment.h"

/// nxnative's prompt that waits for more players, over the window W.
void NxShowControllerPrompt(UIWindow *w, int min, int max, int joined);
