//
//  CartoucheGuestControllers.m
//  Cartouche
//
//  A game behind the console gets its controllers' presses only while its
//  process has the keyboard. iOS hands a controller's presses to the
//  process that has the keyboard, as it hands it a hardware keyboard's
//  keys; Cartouche hosts the game's scene in its own window, and
//  LiveContainer's scene hosting gives the keyboard to the game's process
//  only when the game asks for it, or when the player touches the game
//  (MultitaskSupport/AppSceneViewController.m, its event deferring). Until
//  then the presses go to Cartouche, whose console takes none of them but
//  Home while the game is on screen (CartoucheGamepad.swift): the game
//  showed that a controller was there, its controls on screen hidden, and
//  never moved (issue #230). On nxnative's settings screen, the player's
//  touch on its Play button gave the game the keyboard, and the controller
//  worked; started without that screen, as Play starts it, nothing in the
//  game asks for the keyboard: an nxnative game shows a text field only as
//  a game asks for text (front_ios.m). In a window of LiveContainer's own,
//  a game gets its controllers' presses once one of its text fields has
//  had the keyboard (LiveContainer issue 1587).
//
//  So, while the game's scene is active, the game's process asks for the
//  keyboard as a text field does: a view of its own, in the game's window,
//  that takes text and is the first responder, as a text field being typed
//  in is. It shows no keyboard, an empty view of no height in its place, no
//  bar of shortcuts over a hardware keyboard on an iPad, nothing on the
//  game's screen; it takes no touch and is nothing for VoiceOver; it throws
//  away what a hardware keyboard types, which nxnative's games read
//  nothing of. A text field of the game's own keeps the keyboard: the view
//  asks again once nothing has it (CartoucheGuest.m, every two seconds).
//  As the scene resigns active, paused behind the console or left, the
//  view lets the keyboard go, and the controllers' presses go back to
//  Cartouche's console, where the controller's Home button brings the game
//  back.
//

#import "CartoucheGuestControllers.h"
#import <objc/message.h>
#import <objc/runtime.h>

/// What the game's process puts in its window to ask for the keyboard.
@interface CartoucheGuestKeyboard : UIView <UIKeyInput>
@end

@implementation CartoucheGuestKeyboard {
    /// In the keyboard's place: nothing, of no height.
    UIView *_noKeyboard;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 1, 1)])) {
        // Nothing on screen, and so no touch: UIKit gives none to a view
        // that does not show.
        self.alpha = 0;
        self.isAccessibilityElement = NO;
        self.accessibilityElementsHidden = YES;
        self.accessibilityIdentifier = @"cartouche.controllers";
        _noKeyboard = [[UIView alloc] initWithFrame:CGRectZero];
        // No bar of shortcuts over a hardware keyboard on an iPad.
        self.inputAssistantItem.leadingBarButtonGroups = @[];
        self.inputAssistantItem.trailingBarButtonGroups = @[];
    }
    return self;
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (UIView *)inputView {
    return _noKeyboard;
}

- (UIView *)inputAccessoryView {
    return nil;
}

// UIKeyInput: what a hardware keyboard types goes nowhere.
- (BOOL)hasText {
    return NO;
}

- (void)insertText:(NSString *)text {
}

- (void)deleteBackward {
}

// UITextInputTraits: nothing to correct, to check or to suggest.
- (UITextAutocorrectionType)autocorrectionType {
    return UITextAutocorrectionTypeNo;
}

- (UITextSpellCheckingType)spellCheckingType {
    return UITextSpellCheckingTypeNo;
}

- (UITextAutocapitalizationType)autocapitalizationType {
    return UITextAutocapitalizationTypeNone;
}

@end

static const void *CartoucheGuestKeyboardKey = &CartoucheGuestKeyboardKey;

/// The view that asks for the keyboard in SCENE, if there is one.
static CartoucheGuestKeyboard *CartoucheGuestKeyboardOf(UIWindowScene *scene) {
    return objc_getAssociatedObject(scene, CartoucheGuestKeyboardKey);
}

/// The game's window in SCENE: its key window, or the first it shows.
static UIWindow *CartoucheGuestWindow(UIWindowScene *scene) {
    if (scene.keyWindow) return scene.keyWindow;
    for (UIWindow *window in scene.windows) {
        if (!window.hidden) return window;
    }
    return nil;
}

/// The first responder of WINDOW, as UIKit keeps it, nil when it has none
/// or UIKit does not say.
static UIResponder *CartoucheGuestFirstResponder(UIWindow *window) {
    SEL firstResponder = NSSelectorFromString(@"firstResponder");
    if (![window respondsToSelector:firstResponder]) return nil;
    id responder = ((id (*)(id, SEL))objc_msgSend)(window, firstResponder);
    return [responder isKindOfClass:UIResponder.class] ? responder : nil;
}

void CartoucheGuestTakeControllers(UIWindowScene *scene) {
    UIWindow *window = CartoucheGuestWindow(scene);
    if (!window) return;
    CartoucheGuestKeyboard *keyboard = CartoucheGuestKeyboardOf(scene);
    if (keyboard.isFirstResponder && keyboard.window == window) return;
    // Something of the game's is the first responder, as a text field being
    // typed in is: it stays so.
    UIResponder *current = CartoucheGuestFirstResponder(window);
    if (current && current != keyboard) return;
    if (!keyboard) {
        keyboard = [[CartoucheGuestKeyboard alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(scene, CartoucheGuestKeyboardKey, keyboard, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (keyboard.window != window) {
        [keyboard removeFromSuperview];
        [window addSubview:keyboard];
    }
    [keyboard becomeFirstResponder];
}

void CartoucheGuestLeaveControllers(UIWindowScene *scene) {
    CartoucheGuestKeyboard *keyboard = CartoucheGuestKeyboardOf(scene);
    if (keyboard.isFirstResponder) {
        [keyboard resignFirstResponder];
    }
}

BOOL CartoucheGuestHoldsControllers(UIWindowScene *scene) {
    return CartoucheGuestKeyboardOf(scene).isFirstResponder;
}
