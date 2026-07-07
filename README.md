# PostgresConnectionPool

A connection pool on top of [PostgresNIO](https://github.com/vapor/postgres-nio) and [PostgresKit](https://github.com/vapor/postgres-kit).

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2FPostgresConnectionPool%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Outdooractive/PostgresConnectionPool)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2FPostgresConnectionPool%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Outdooractive/PostgresConnectionPool)

## Requirements

Swift 6.3 or higher (Xcode 16+), macOS 15+ or Linux.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/Outdooractive/PostgresConnectionPool.git", from: "1.0.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "PostgresConnectionPool", package: "PostgresConnectionPool"),
    ]),
]
```

## Features

- **Configurable pool size** — set the maximum number of open connections
- **Health checks** — `SELECT 1` before returning a connection to a caller (configurable via `onReturnConnection`)
- **Idle connection culling** — automatically close excess idle connections over a 60-second rolling window
- **Query timeout** — set `statement_timeout` per connection
- **Connection retry** — configurable retry interval for transient failures
- **Batch cancellation** — abort all pending queries for a batch ID
- **Diagnostics** — per-connection query tracking, usage counters, runtime info
- **PostgresKit integration** — use `connection.sql()` for the `SQLDatabase` API
- **Listen/Notify support** — `addListener()` and `listen(on:consume:)`

## Usage

```swift
import PostgresConnectionPool
import PostgresNIO

let postgresConfiguration = PostgresConnection.Configuration(
    host: "localhost",
    port: 5432,
    username: "testuser",
    password: "testpassword",
    database: "test",
    tls: .disable)

let configuration = PoolConfiguration(
    applicationName: "MyApp",
    postgresConfiguration: postgresConfiguration,
    connectTimeout: 10.0,
    queryTimeout: 60.0,
    poolSize: 5,
    maxIdleConnections: 1)

let pool = PostgresConnectionPool(configuration: configuration)

// Run a query
try await pool.connection { connection in
    try await connection.query("SELECT 1", logger: logger)
}

// Use PostgresKit's SQLDatabase API
let users = try await pool.connection { connection in
    try await connection.sql().raw("SELECT * FROM users").all(decoding: User.self)
}

// Inspect pool state
let info = await pool.poolInfo()
print(info)

// Shutdown when done
await pool.shutdown()
```

## See also

- [API documentation](https://swiftpackageindex.com/Outdooractive/PostgresConnectionPool/main/documentation/postgresconnectionpool)
- [PostgresNIO](https://github.com/vapor/postgres-nio) — async PostgreSQL client
- [PostgresKit](https://github.com/vapor/postgres-kit) — SQL database integration

## License

MIT

## Author

Thomas Rasch, Outdooractive
