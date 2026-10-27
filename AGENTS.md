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
  Manages connection lifecycle (open, health check, release, close), cancellation-aware waiting,
  idle connection culling, a single maintenance task and delayed connection retries. Uses
  `PostgresConnection.defaultEventLoopGroup` unless a group is injected.
- **`PoolConfiguration.swift`** — `PoolConfiguration` struct: connection parameters, pool size,
  timeouts, callbacks (`onOpenConnection`, `onReturnConnection`, `onCloseConnection`).
- **`PoolConnection.swift`** — Internal `PoolConnection` class: connection identity (atomic ID),
  usage counter, state machine (`connecting`/`available`/`active`/`closed`), query tracking.
- **`PoolConnectionState.swift`** — `PoolConnectionState` enum: `.active(Date)`, `.available`,
  `.closed`, `.connecting`.
- **`PoolContinuation.swift`** — Internal continuation wrapper for pending connection requests,
  including its cancellation marker and health-check attempt counter.
- **`PoolError.swift`** — Error enum: `.cancelled`, `.connectionFailed`, `.poolDestroyed(PSQLError?)`,
  `.postgresError(PSQLError)`, `.queryCancelled`, `.unknown`.
- **`PoolInfo.swift`** — Diagnostics: `PoolInfo` and `PoolInfo.ConnectionInfo` structs with
  connection counts, waiting requests, usage, queries and runtimes.
- **`PostgresConnectionWrapper.swift`** — Public connection handle: forwards `query()`, `sql()`,
  `addListener()`, `listen(on:consume:)` to the underlying `PostgresConnection` while tracking
  query text for runtime diagnostics. Invalidated when the callback returns; escaping handles
  must not be used.
- **`Extensions/`** — Helpers: `EmptyTestable` (isNotEmpty), `FloatingPoint.rounded(toPlaces:)`,
  `Double.atLeast(_:)`, `Int.atLeast(_:)`, `String.matches()`/`replacingPattern()` and
  `PSQLError.pgPoolDescription`/`pgPoolDebugDescription`.

Dependencies:
- **PostgresNIO** — async PostgreSQL client, `PostgresConnection`, `PSQLError`
- **PostgresKit** — `SQLDatabase` integration via `connection.sql()`
- **swift-atomics** — `ManagedAtomic<Int>` for connection IDs and usage counters
- **swift-collections** — `Deque` for connection and continuation queues

## Build & test

```bash
swift build           # build library
swift test            # unit tests; database-backed suites are skipped
```

Integration tests are gated by `POSTGRES_HOSTNAME` or `POSTGRES_TESTS=1`:

```bash
docker compose up -d
POSTGRES_TESTS=1 swift test

POSTGRES_TESTS=1 scripts/run-coverage.sh 90
```

See `DEVELOPMENT.md` for the full matrix, environment variables, coverage and
documentation commands. CI runs macOS unit tests, Linux tests against PostgreSQL
18 (the minimum supported production version), the 90% coverage gate and DocC.

## Relationship to `PostgresNIO.PostgresClient`

`PostgresClient` is the upstream pool and covers min/max connections, keep-alive,
idle timeout and ServiceLifecycle integration. This package additionally provides
batch cancellation, per-connection diagnostics and connection hooks. A future major
version may be rebuilt on `PostgresClient`; do not assume the custom pool can be
removed without preserving those features.

## Code style conventions

Follow the same conventions as mvt-tools (4-space indentation, no tabs, DocC documentation,
Swift 6 concurrency, `Sendable` conformance on all model types, `actor` for mutable state).
All public API must have DocC documentation.
