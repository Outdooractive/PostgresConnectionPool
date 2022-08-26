// swift-tools-version:5.6

import PackageDescription

let package = Package(
    name: "PostgresConnectionPool",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .library(name: "PostgresConnectionPool", targets: ["PostgresConnectionPool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.2"),
        .package(url: "https://github.com/vapor/postgres-kit", from: "2.8.0"),
    ],
    targets: [
        .target(
            name: "PostgresConnectionPool",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "PostgresKit", package: "postgres-kit"),
            ]),
    ])
