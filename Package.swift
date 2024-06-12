// swift-tools-version:5.10

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
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.1.1"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.4"),
        .package(url: "https://github.com/vapor/postgres-kit", from: "2.13.5"),
    ],
    targets: [
        .target(
            name: "PostgresConnectionPool",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "PostgresKit", package: "postgres-kit"),
            ]),
        .testTarget(
            name: "PostgresConnectionPoolTests",
            dependencies: [
                .target(name: "PostgresConnectionPool"),
            ]),
    ]
)
