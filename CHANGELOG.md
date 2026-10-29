# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to semantic versioning.

## Unreleased

### Fixed

- Reject idle pooled connections whose TCP channel is already closed before
  leasing them. PostgresNIO writes to a closed channel and waits for a response
  that never arrives, which could hang the request after an administrative
  backend termination.

## 1.1.1 - 2026-10-28

### Fixed

- A connection that finished opening while the pool was shutting down is now
  closed and discarded instead of being published to the pool after shutdown.
  Releasing the pool could previously trap in PostgresNIO with
  `PostgresConnection deinitialized before being closed`.

## 1.1.0 - 2026-10-28

### Added

- GitHub Actions for macOS unit tests, Linux tests against PostgreSQL 18 (the
  minimum supported production version), a 90% coverage gate and DocC.
- `scripts/run-coverage.sh` and `scripts/coverage.py`, including support for
  SwiftPM versions that only emit `.profraw` coverage files.
- `DEVELOPMENT.md` with unit, integration, coverage, formatting and CI notes.
- `PoolConfiguration.defaultHealthCheckEnabled` to disable the built-in per-lease
  `SELECT 1` health check. Custom `onReturnConnection` callbacks are still honored.
- `PostgresConnectionPool` initializer parameters for the maintenance interval,
  idle-connection window and an injected `EventLoopGroup`.
- `PoolInfo.waitingRequests` and batch-filtered connection counts.
- `PostgresConnectionWrapper.isValid` and explicit invalidation after the
  connection callback returns.
- `POSTGRES_CLIENT_EVALUATION.md` and evaluation tests documenting why the
  package keeps its custom pool for 1.x instead of rebuilding on
  `PostgresNIO.PostgresClient`.
- Tests for waiting requests, cancellation, batch cancellation, shutdown,
  query timeouts, connection hooks, wrapper lifetime, idle culling, error
  descriptions, Unicode regex handling and all pool failure paths.

### Changed

- Transient connection failures (DNS, refused/reset connections, server restart,
  too many clients) now fail the current request and keep the pool alive. A
  `connectionRetryInterval` cooldown prevents retry storms before the next
  attempt. Authentication, invalid database name and TLS configuration errors
  still shut the pool down.
- The pool now uses `PostgresConnection.defaultEventLoopGroup` by default
  instead of creating `poolSize * 2` threads per pool. A dedicated event loop
  group can still be injected, and the pool no longer owns or shuts it down.
- Updated `postgres-nio` to 1.33.2, `postgres-kit` to 2.17.0 and
  `swift-collections` to 1.7.5. Added an explicit `OrderedCollections` product
  dependency.
- Removed the unused internal `Task.after` helper.

### Fixed

- Cancelling a task waiting for a connection now removes its continuation
  immediately instead of leaving it queued until a connection is released.
- Requests waiting when a permanent connection error destroys the pool now receive
  `PoolError.poolDestroyed` instead of the misleading `PoolError.cancelled`.
- The maintenance task is cancelled on shutdown and no longer reschedules
  itself after the pool is closed.
- Query tracking no longer races between `poolInfo()` and the connection
  wrapper.
- `String.replacingPattern` now uses UTF-16 ranges and handles non-BMP
  characters correctly.
- `poolInfo(batchId:)` counts only the filtered, non-closed connections and
  reports waiting requests consistently.
- A failed health check on one connection is retried once with another or a
  fresh connection instead of immediately failing the caller.
- Connection setup failures are logged, fail the request and apply the connection
  cooldown instead of silently looping.
- `PoolError` conforms to `LocalizedError`.

## 1.0.0

- Initial tagged release.
