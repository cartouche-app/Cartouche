//
//  CartoucheGuestControllers.h
//  Cartouche
//
//  How a game behind the console gets its controllers (CartoucheGuest.m,
//  CartoucheGuestControllers.m). The launcher's harness builds it too, and
//  tests it in a scene of its own (launcher/Harness/Tests/ControllerTests.swift).
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// SCENE, the game's own, is active, on screen: the game's process asks
/// for the keyboard, without showing one, which brings it the controllers.
/// Nothing changes while something of the game's is the first responder,
/// as a text field being typed in is, or when the scene has no window yet.
/// Main thread.
void CartoucheGuestTakeControllers(UIWindowScene *scene);

/// SCENE resigns active, the game paused behind the console or left: the
/// keyboard, and the controllers with it, go back to Cartouche. Main thread.
void CartoucheGuestLeaveControllers(UIWindowScene *scene);

/// Whether the game's process asks for the keyboard in SCENE now. Main
/// thread.
BOOL CartoucheGuestHoldsControllers(UIWindowScene *scene);

NS_ASSUME_NONNULL_END
