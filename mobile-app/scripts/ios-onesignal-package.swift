// swift-tools-version: 5.9
import PackageDescription

// OneSignal Cordova plugin for Capacitor iOS SPM (restored after cap sync)
let package = Package(
    name: "OnesignalCordovaPlugin",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "OnesignalCordovaPlugin",
            targets: ["OnesignalCordovaPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.2.0"),
        .package(url: "https://github.com/OneSignal/OneSignal-XCFramework.git", exact: "5.5.0")
    ],
    targets: [
        .target(
            name: "OnesignalCordovaPlugin",
            dependencies: [
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                .product(name: "OneSignalFramework", package: "OneSignal-XCFramework")
            ],
            path: ".",
            publicHeadersPath: "."
        )
    ]
)
