// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NetDiagnosis",
    platforms: [.iOS(.v9), .macOS(.v10_10), .watchOS(.v5), .tvOS(.v9)], //As RxSwfit Requiredb
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "NetDiagnosis",
            targets: ["NetDiagnosis"]),
        .library(
            name: "RxNetDiagnosis",
            targets: ["RxNetDiagnosis"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(
          url: "https://github.com/apple/swift-collections.git",
          .upToNextMajor(from: "1.0.4") 
        ),
        .package(
          url: "https://github.com/ReactiveX/RxSwift.git",
          .upToNextMajor(from: "6.6.0")
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "RxNetDiagnosis",
            dependencies: [
                "NetDiagnosis",
                "RxSwift",
            ]),
        .target(
            name: "NetDiagnosis",
            dependencies: [
                .product(name: "OrderedCollections", package: "swift-collections")
            ]),
        .testTarget(
            name: "NetDiagnosisTests",
            dependencies: [
                "NetDiagnosis",
            ]),
    ]
)
