//
//  CartoucheGameTextsEnvironment.h
//  Cartouche
//
//  nxnative's texts in the language Cartouche speaks, put in the game's
//  environment from its data folder (CartoucheGameTextsEnvironment.m). The
//  launcher's harness calls these too (launcher/Harness/Tests/PlayTests.swift).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The file, in the game's data folder, of nxnative's texts in the language
/// Cartouche speaks: Cartouche writes it as Play starts the game
/// (launcher/Sources/CartoucheGameTexts.swift).
extern NSString *const CartoucheGameTextsFile;

/// The variables the file may set, nxnative's texts on the iPhone alone,
/// as CartoucheGameTexts.variables(on: .iPhone) lists them: never another
/// of nxnative's switches.
NSArray<NSString *> *CartoucheGameTextsVariables(void);

/// Puts the texts of the file in the data folder HOME in this process's
/// environment, but those its environment has already, from the game's
/// env.txt or its start: nxnative reads them as it shows its prompt or its
/// menu. Returns the variables it set.
NSArray<NSString *> *CartoucheGameTextsApply(NSString *home);

NS_ASSUME_NONNULL_END
