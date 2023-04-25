# PostgresConnectionPool

A simple connection pool on top of [PostgresNIO](https://github.com/vapor/postgres-nio) and [PostgresKit](https://github.com/vapor/postgres-kit).

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2FPostgresConnectionPool%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Outdooractive/PostgresConnectionPool)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2FPostgresConnectionPool%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Outdooractive/PostgresConnectionPool)

## Requirements

This package requires Swift 5.7 or higher (at least Xcode 13), and compiles on macOS (\>= macOS 10.15) and Linux.

## Installation with Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Outdooractive/PostgresConnectionPool.git", from: "0.5.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "PostgresConnectionPool", package: "PostgresConnectionPool"),
    ]),
]
```

## Usage

Please see also the [API documentation](https://swiftpackageindex.com/Outdooractive/PostgresConnectionPool/main/documentation/postgresconnectionpool).

``` swift
import PostgresConnectionPool
import PostgresKit

var logger = Logger(label: "TestApp")
logger.logLevel = .debug

let connection = PoolConfiguration.Connection(
    username: "testuser",
    password: "testpassword",
    host: "postgres",
    port: 5432,
    database: "test")
let configuration = PoolConfiguration(
    applicationName: "TestApp",
    connection: connection,
    connectTimeout: 10.0,
    queryTimeout: 60.0,
    poolSize: 5,
    maxIdleConnections: 1)
let pool = PostgresConnectionPool(configuration: configuration, logger: logger)

// Fetch a connection from the pool and do something with it...
try await pool.connection(callback: { connection in
    try await connection.query(PostgresQuery(stringLiteral: "SELECT 1"), logger: logger)
})

// Generic object loading
func fetchObjects<T: Decodable>(_ sql: String) async throws -> [T] {
    try await pool.connection({ connection in
        return try await connection.sql().raw(SQLQueryString(stringLiteral: sql)).all(decoding: T.self)
    })
}

// Open connections, current SQL queries, etc.
await print(pool.info())

// Always call `shutdown()` before releasing a pool
await pool.shutdown()
```

## Contributing

Please create an issue or open a pull request with a fix or enhancement.

## License

MIT

## Author

Thomas Rasch, Outdooractive
