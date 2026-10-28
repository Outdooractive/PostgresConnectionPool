# PostgresConnectionPool

A connection pool on top of [PostgresNIO](https://github.com/vapor/postgres-nio) and [PostgresKit](https://github.com/vapor/postgres-kit).

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2FPostgresConnectionPool%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Outdooractive/PostgresConnectionPool)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2FPostgresConnectionPool%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Outdooractive/PostgresConnectionPool)

## Requirements

Swift 6.3 or higher (Xcode 16+), macOS 15+ or Linux. PostgreSQL 18 or newer is supported; older database versions are untested.

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
- **Health checks** — optional default `SELECT 1` before leasing a connection; custom `onReturnConnection` hooks are always honored
- **Idle connection culling** — close excess idle connections over a rolling window
- **Query timeout** — set `statement_timeout` per connection
- **Connection cooldown** — transient connection failures fail the request and delay the next attempt; auth/TLS/config errors shut the pool down
- **Cancellation-aware waiting** — cancelling a request removes it from the queue immediately
- **Batch cancellation** — abort waiting connection requests for a batch ID
- **Diagnostics** — per-connection query tracking, usage counters, waiting-request counts and runtime info
- **PostgresKit integration** — use `connection.sql()` for the `SQLDatabase` API
- **Listen/Notify support** — `addListener()` and `listen(on:consume:)`
- **Shared event loop** — reuses `PostgresConnection.defaultEventLoopGroup` by default instead of creating one event loop group per pool

## Failure behavior

- Transient connection failures (DNS, refused connections, connection resets,
  server shutdown/restart, too many clients) fail the current request, leave the
  pool alive and apply `connectionRetryInterval` before the next attempt.
- Authentication, invalid database name and TLS configuration errors shut the
  pool down and surface `PoolError.poolDestroyed`.
- A pool that was not shut down permanently continues to serve new requests
  after the cooldown. Callers can therefore retry at their own level.

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
    maxIdleConnections: 1,
    defaultHealthCheckEnabled: true)

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

`defaultHealthCheckEnabled` only controls the built-in `SELECT 1` fallback. A custom
`onReturnConnection` callback is always invoked, even when the default health check is disabled.

The `PostgresConnectionWrapper` passed to `connection(batchId:_:)` is only valid for the
duration of the callback. Do not store it, and consume query sequences and `SQLDatabase`
values before returning. The wrapper becomes invalid after the callback and rejects
further queries.

## Relationship to PostgresNIO's `PostgresClient`

`PostgresNIO` now ships `PostgresClient`, a maintained connection pool with minimum and
maximum connections, keep-alive probes, an idle timeout and ServiceLifecycle integration.
It covers most of the pooling concerns this package implements.

This package still provides features `PostgresClient` does not expose directly:

- batch IDs and cancellation of waiting requests
- per-connection query and runtime diagnostics through `poolInfo()`
- connection open/return/close hooks
- the callback-based `connection(batchId:_:)` API used by `mvt-postgis`

A future major version may be rebuilt on top of `PostgresClient` while preserving those
features. Until then, this package keeps its own pool implementation and its public API.
See [POSTGRES_CLIENT_EVALUATION.md](POSTGRES_CLIENT_EVALUATION.md) for the feature
comparison, prototype findings and the decision to keep the custom pool for 1.x.

## Development

```bash
# Unit tests only (database-backed suites are skipped)
swift test

# Unit and integration tests against a local PostgreSQL
docker compose up -d
POSTGRES_TESTS=1 swift test

# Or point at any PostgreSQL instance
POSTGRES_HOSTNAME=localhost POSTGRES_USER=test_username \
POSTGRES_PASSWORD=test_password POSTGRES_DB=test_database swift test

# Coverage gate
POSTGRES_TESTS=1 scripts/run-coverage.sh 90

# Documentation
swift package --allow-writing-to-directory .build/documentation \
    generate-documentation --target PostgresConnectionPool --disable-indexing
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for details.

## See also

- [API documentation](https://swiftpackageindex.com/Outdooractive/PostgresConnectionPool/main/documentation/postgresconnectionpool)
- [PostgresNIO](https://github.com/vapor/postgres-nio) — async PostgreSQL client
- [PostgresKit](https://github.com/vapor/postgres-kit) — SQL database integration

## License

MIT

## Author

Thomas Rasch, Outdooractive
