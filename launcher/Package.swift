// swift-tools-version: 5.9
//
// The launcher's parts that need neither LiveContainer nor UIKit, built and
// tested on their own on a Mac, as the App workflow does before it builds
// Cartouche:
//
//     swift test --package-path launcher
//
// The app compiles the same files from Sources/ with the rest of the
// launcher (app/scripts/prepare.sh); only those listed here are built.
// Cartouche Builder's Mac app (builder/mac) uses the bridge between the two
// (CartoucheBridge.swift) through the CartoucheCore library.

import PackageDescription

let package = Package(
    name: "CartoucheCore",
    platforms: [.macOS(.v13), .iOS(.v15)],
    products: [
        .library(name: "CartoucheCore", targets: ["CartoucheCore"]),
    ],
    targets: [
        .target(
            name: "CartoucheCore",
            path: "Sources",
            exclude: ["Cartouche.xcstrings"],
            // One a line, in the order of their names, which a pull request that adds
            // one adds at its place: pull requests that each add one then do not meet,
            // as they did when the list was one line.
            sources: [
                "CartoucheBCConversion.swift",
                "CartoucheBridge.swift",
                "CartoucheBridgeBuilds.swift",
                "CartoucheCloud.swift",
                "CartoucheConnections.swift",
                "CartoucheCoverList.swift",
                "CartoucheDeviceWords.swift",
                "CartoucheDrive.swift",
                "CartoucheFTP.swift",
                "CartoucheFailure.swift",
                "CartoucheFreeSpace.swift",
                "CartoucheGameBuild.swift",
                "CartoucheGameFit.swift",
                "CartoucheGameLanguage.swift",
                "CartoucheGameLog.swift",
                "CartoucheGameLogShare.swift",
                "CartoucheGameLogZip.swift",
                "CartoucheGameLookup.swift",
                "CartoucheGameNames.swift",
                "CartoucheGameOrientation.swift",
                "CartoucheGamePlace.swift",
                "CartoucheGameSettingList.swift",
                "CartoucheGameSigning.swift",
                "CartoucheInstallQuestions.swift",
                "CartoucheMeasuredNote.swift",
                "CartoucheNaming.swift",
                "CartoucheOwnSignature.swift",
                "CartouchePickerMeasures.swift",
                "CartouchePlayTime.swift",
                "CartouchePlayerInfo.swift",
                "CartoucheProblemReport.swift",
                "CartoucheRelease.swift",
                "CartoucheReleaseNotes.swift",
                "CartoucheRenewalRules.swift",
                "CartoucheReport.swift",
                "CartoucheResetPlan.swift",
                "CartoucheResumingSource.swift",
                "CartoucheRomfs.swift",
                "CartoucheS3.swift",
                "CartoucheSFTP.swift",
                "CartoucheSaveSync.swift",
                "CartoucheSetupFacts.swift",
                "CartoucheSignInMessage.swift",
                "CartoucheSigningCheck.swift",
                "CartoucheSwitchSave.swift",
                "CartoucheSwitchSaveArchive.swift",
                "CartoucheTailscale.swift",
                "CartoucheTelemetryReport.swift",
                "CartoucheTextResults.swift",
                "CartoucheTranslations.swift",
                "CartoucheVPN.swift",
                "CartoucheZip.swift",
            ]
        ),
        .testTarget(
            name: "CartoucheCoreTests",
            dependencies: ["CartoucheCore"],
            path: "Tests/CartoucheCoreTests"
        ),
    ]
)
