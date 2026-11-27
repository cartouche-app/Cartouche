//
//  NxPrompt.m
//  PromptScreens
//
//  nxnative's prompt that waits for more players on iOS, its card as
//  nxnative's dm/ios/Sources/DmGamepad.m draws it at its commit dc9c2374
//  (cp_label, cp_button, cp_show; MIT License, Copyright (c) 2026 seedds),
//  without its controllers: two players wanted, one in. For the screenshots
//  of PR #367 alone, removed before it merges.
//

#import <UIKit/UIKit.h>
#include "ctrl_prompt.h"
#import "Bridging.h"

static UILabel *cp_label(const char *text, CGFloat size, UIFontWeight w, CGFloat alpha) {
    UILabel *l = [UILabel new]; l.text = @(text); l.font = [UIFont systemFontOfSize:size weight:w]; l.textColor = [UIColor colorWithWhite:1 alpha:alpha];
    l.numberOfLines = 0; l.textAlignment = NSTextAlignmentCenter; return l;
}
static UIButton *cp_button(const char *title, int primary) {
    UIButtonConfiguration *cfg = primary ? UIButtonConfiguration.filledButtonConfiguration : UIButtonConfiguration.grayButtonConfiguration;
    cfg.title = @(title); cfg.cornerStyle = UIButtonConfigurationCornerStyleCapsule; cfg.buttonSize = UIButtonConfigurationSizeLarge;
    UIButton *b = [UIButton buttonWithConfiguration:cfg primaryAction:nil];
    return b;
}

void NxShowControllerPrompt(UIWindow *w, int min, int max, int joined) {
    ctrl_prompt g_cp; cp_open(&g_cp, min, max, joined, 0, 0);
    const char *env = getenv("DM_CTRL_PROMPT_TEXT"); char t[CP_TEXTS][256];
    for (int i = 0; i < CP_TEXTS; i++) cp_text(env, i, &g_cp, t[i], sizeof t[i]);
    UIView *scrim = [[UIView alloc] initWithFrame:w.bounds]; scrim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scrim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    UILabel *g_cp_count = cp_label(t[CP_TEXT_COUNT], 20, UIFontWeightSemibold, 0.9);
    UIButton *g_cp_done_btn = cp_button(t[CP_TEXT_DONE], 1);
    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[g_cp_done_btn, cp_button(t[CP_TEXT_CANCEL], 0)]];
    actions.spacing = 16; actions.distribution = UIStackViewDistributionFillEqually;
    UIStackView *card = [[UIStackView alloc] initWithArrangedSubviews:@[cp_label(t[CP_TEXT_TITLE], 26, UIFontWeightBold, 1), cp_label(t[CP_TEXT_HINT], 17, UIFontWeightRegular, 0.6), g_cp_count, actions]];
    card.axis = UILayoutConstraintAxisVertical; card.spacing = 14; [card setCustomSpacing:28 afterView:g_cp_count];
    card.layoutMargins = UIEdgeInsetsMake(32, 36, 28, 36); card.layoutMarginsRelativeArrangement = YES;
    card.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.11 alpha:1]; card.layer.cornerRadius = 28;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [scrim addSubview:card];
    NSLayoutConstraint *wide = [card.widthAnchor constraintEqualToConstant:520]; wide.priority = UILayoutPriorityDefaultHigh;   // narrower on a narrow screen
    [NSLayoutConstraint activateConstraints:@[[card.centerXAnchor constraintEqualToAnchor:scrim.centerXAnchor], [card.centerYAnchor constraintEqualToAnchor:scrim.centerYAnchor],
        [card.widthAnchor constraintLessThanOrEqualToAnchor:scrim.widthAnchor constant:-32], wide]];
    [w addSubview:scrim];
    g_cp_count.text = @(t[CP_TEXT_COUNT]);
    g_cp_done_btn.enabled = cp_can_confirm(&g_cp);
}
