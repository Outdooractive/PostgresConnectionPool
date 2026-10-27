// swift-tools-version:6.3

import PackageDescription

let package = Package(
    name: "PostgresConnectionPool",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "PostgresConnectionPool", targets: ["PostgresConnectionPool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.3.1"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.7.5"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.33.2"),
        .package(url: "https://github.com/vapor/postgres-kit", from: "2.17.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "PostgresConnectionPool",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "PostgresKit", package: "postgres-kit"),
            ]),
        .testTarget(
            name: "PostgresConnectionPoolTests",
            dependencies: [
                .target(name: "PostgresConnectionPool"),
            ]),
    ])
