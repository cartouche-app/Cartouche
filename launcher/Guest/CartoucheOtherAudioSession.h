//
//  CartoucheOtherAudioSession.h
//  Cartouche
//
//  The game's audio session mixed with other apps' sound, when the player
//  keeps it (CartoucheOtherAudioSession.m). The launcher's harness calls
//  these too (launcher/Harness/Tests/OtherAudioTests.swift).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The file, in the game's data folder, that says the player keeps other
/// apps' sound: Cartouche writes it as Play starts the game
/// (launcher/Sources/CartoucheOtherAudio.swift), and removes it otherwise.
extern NSString *const CartoucheOtherAudioFile;
/// Its key: YES while the player keeps other apps' sound.
extern NSString *const CartoucheOtherAudioKey;

/// Whether the file in the data folder HOME says to keep other apps' sound.
BOOL CartoucheOtherAudioIsKept(NSString *home);

/// From now on, KEEP mixes every category this process sets that takes the
/// option with other apps' sound, the one set already too; NO leaves the
/// categories as they are set. NO when this process has no AVAudioSession,
/// or not the calls that set its category.
BOOL CartoucheOtherAudioKeep(BOOL keep);

NS_ASSUME_NONNULL_END
