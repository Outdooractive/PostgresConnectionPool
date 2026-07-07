# AGENTS.md

# PostgresConnectionPool — async PostgreSQL Connection Pool

A Swift connection pool built on [PostgresNIO](https://github.com/vapor/postgres-nio) and
[PostgresKit](https://github.com/vapor/postgres-kit). Manages a configurable set of reusable
PostgreSQL connections with health checks, idle connection culling, automatic reconnection,
and runtime diagnostics.

One product:
- **`PostgresConnectionPool`** — library target: `PostgresConnectionPool` actor,
  `PoolConfiguration`, `PostgresConnectionWrapper`, `PoolInfo`, and related types.

Key source areas:
- **`PostgresConnectionPool.swift`** — Main `actor PostgresConnectionPool`: init, `connection(batchId:_:)`,
  `shutdown()`, `abortBatch(_:)`, `closeIdleConnections()`, `poolInfo(batchId:)`.
  Manages connection lifecycle (open, health check, release, close), idle connection culling,
  and continuation-based connection queue.
- **`PoolConfiguration.swift`** — `PoolConfiguration` struct: connection parameters, pool size,
  timeouts, callbacks (`onOpenConnection`, `onReturnConnection`, `onCloseConnection`).
- **`PoolConnection.swift`** — Internal `PoolConnection` class: connection identity (atomic ID),
  usage counter, state machine (`connecting`/`available`/`active`/`closed`), query tracking.
- **`PoolConnectionState.swift`** — `PoolConnectionState` enum: `.active(Date)`, `.available`,
  `.closed`, `.connecting`.
- **`PoolContinuation.swift`** — Internal continuation wrapper for pending connection requests.
- **`PoolError.swift`** — Error enum: `.cancelled`, `.connectionFailed`, `.poolDestroyed(PSQLError?)`,
  `.postgresError(PSQLError)`, `.queryCancelled`, `.unknown`.
- **`PoolInfo.swift`** — Diagnostics: `PoolInfo` and `PoolInfo.ConnectionInfo` structs with
  connection counts, usage, queries, runtimes.
- **`PostgresConnectionWrapper.swift`** — Public connection handle: forwards `query()`, `sql()`,
  `addListener()`, `listen(on:consume:)` to the underlying `PostgresConnection` while tracking
  query text for runtime diagnostics.
- **`Extensions/`** — Helpers: `EmptyTestable` (isNotEmpty), `FloatingPoint.rounded(toPlaces:)`,
  `Double.atLeast(_:)`, `Int.atLeast(_:)`, `String.matches()`/`replacingPattern()`,
  `Task.after(seconds:priority:operation:)`, `PSQLError.pgPoolDescription`/`pgPoolDebugDescription`.

Dependencies:
- **PostgresNIO** — async PostgreSQL client, `PostgresConnection`, `PSQLError`
- **PostgresKit** — `SQLDatabase` integration via `connection.sql()`
- **swift-atomics** — `ManagedAtomic<Int>` for connection IDs and usage counters
- **swift-collections** — `Deque` for connection and continuation queues

## Build & test

```bash
swift build           # build library
swift test            # run all tests (Swift Testing)
```

A running PostgreSQL container is required for integration tests. Use the provided `docker-compose.yml`:

```bash
docker compose up -d
swift test
```

## Code style conventions

Follow the same conventions as mvt-tools (4-space indentation, no tabs, DocC documentation,
Swift 6 concurrency, `Sendable` conformance on all model types, `actor` for mutable state).
All public API must have DocC documentation.
