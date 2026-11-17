// swift-tools-version: 6.0
//
// Cartouche Builder's Mac app: the player's games with their covers, what
// nxnative improved and the rebuilds it calls for, the builds as they run,
// what the builder keeps on the Mac, and the bridge that shares the games
// with Cartouche on the iPhone. The builder's engine (../cartouche_builder,
// Python) does the work; the app runs its JSON commands and follows its
// batches.
//
//     git submodule update --init app/SMBClient
//     swift build -c release --package-path builder/mac
//     builder/mac/bundle.sh "$HOME/Applications"     # the .app, signed ad hoc
//     swift test --package-path builder/mac

import PackageDescription

let package = Package(
    name: "CartoucheBuilder",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "CartoucheBuilder", targets: ["CartoucheBuilder"]),
    ],
    dependencies: [
        // The bridge to Cartouche (launcher/Sources/CartoucheBridge.swift).
        .package(path: "../../launcher"),
        // The console's storage reaches the player's shared folders over
        // SMB and their servers over SFTP, as Cartouche on the iPhone does:
        // SMBClient and swift-nio-ssh pinned as the app pins them, the
        // submodule app/SMBClient and Package.resolved, which matches the one
        // of app/patches/livecontainer/0007 (app/tests/test_storage_tests.py).
        .package(path: "../../app/SMBClient"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", exact: "0.15.0"),
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.104.0"),
    ],
    targets: [
        .target(
            name: "BuilderKit",
            dependencies: [.product(name: "CartoucheCore", package: "launcher")],
            path: "Sources/BuilderKit"
        ),
        // Cartouche's console on the Mac: the iPhone's own screens, linked
        // from the launcher (Sources/CartoucheConsole/Shared), with what a
        // Mac stands in for the rest of the iPhone's Cartouche
        // (Sources/CartoucheConsole/Mac). Its words and its catalogue are
        // in the app's resources (bundle.sh). It shares files with
        // CartoucheCore, each its own copy: the app imports it in one file.
        .target(
            name: "CartoucheConsole",
            dependencies: [
                .product(name: "SMBClient", package: "SMBClient"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Sources/CartoucheConsole"
        ),
        .executableTarget(
            name: "CartoucheBuilder",
            dependencies: ["BuilderKit", "CartoucheConsole", .product(name: "CartoucheCore", package: "launcher")],
            path: "Sources/CartoucheBuilder"
        ),
        // The fixtures are the engine's answers, read from their folder
        // (builder/tests/test_app_contract.py writes them).
        .testTarget(
            name: "BuilderKitTests",
            dependencies: ["BuilderKit", .product(name: "CartoucheCore", package: "launcher")],
            path: "Tests/BuilderKitTests",
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "CartoucheConsoleTests",
            dependencies: ["CartoucheConsole"],
            path: "Tests/CartoucheConsoleTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
