# PostgresConnectionPool

A simple connection pool on top of PostgresNIO.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2FPostgresConnectionPool%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Outdooractive/PostgresConnectionPool)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2FPostgresConnectionPool%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Outdooractive/PostgresConnectionPool)

## Installation with Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Outdooractive/PostgresConnectionPool.git", from: "0.4.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "PostgresConnectionPool", package: "PostgresConnectionPool"),
    ]),
]
```

## Usage

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
```

## Contributing

Please create an issue or open a pull request with a fix.

## License

MIT

## Author

Thomas Rasch, Outdooractive
