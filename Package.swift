// swift-tools-version:5.7

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
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.20.2"),
        .package(url: "https://github.com/vapor/postgres-kit", from: "2.12.3"),
    ],
    targets: [
        .target(
            name: "PostgresConnectionPool",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "PostgresKit", package: "postgres-kit"),
            ]),
        .testTarget(
            name: "PostgresConnectionPoolTests",
            dependencies: [
                .target(name: "PostgresConnectionPool"),
            ]),
    ])
