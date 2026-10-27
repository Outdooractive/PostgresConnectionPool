# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to semantic versioning.

## Unreleased

### Added

- GitHub Actions for macOS unit tests, Linux tests against PostgreSQL 15–18,
  a 90% coverage gate and DocC.
- `scripts/run-coverage.sh` and `scripts/coverage.py`, including support for
  SwiftPM versions that only emit `.profraw` coverage files.
- `DEVELOPMENT.md` with unit, integration, coverage, formatting and CI notes.
- `PoolConfiguration.healthCheckEnabled` to disable the per-lease `SELECT 1`
  health check.
- `PostgresConnectionPool` initializer parameters for the maintenance interval,
  idle-connection window and an injected `EventLoopGroup`.
- `PoolInfo.waitingRequests` and batch-filtered connection counts.
- `PostgresConnectionWrapper.isValid` and explicit invalidation after the
  connection callback returns.
- Tests for waiting requests, cancellation, batch cancellation, shutdown,
  query timeouts, connection hooks, wrapper lifetime, idle culling, error
  descriptions, Unicode regex handling and all pool failure paths.

### Changed

- The pool now uses `PostgresConnection.defaultEventLoopGroup` by default
  instead of creating `poolSize * 2` threads per pool. A dedicated event loop
  group can still be injected, and the pool no longer owns or shuts it down.
- Connection retries now use `connectionRetryInterval` for all transient
  failures and share a single delayed retry task instead of creating an
  unbounded number of retry tasks.
- Updated `postgres-nio` to 1.33.2, `postgres-kit` to 2.17.0 and
  `swift-collections` to 1.7.5. Added an explicit `OrderedCollections` product
  dependency.
- Removed the unused internal `Task.after` helper.

### Fixed

- Cancelling a task waiting for a connection now removes its continuation
  immediately instead of leaving it queued until a connection is released.
- Requests waiting when a fatal connection error destroys the pool now receive
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
- Connection setup failures are logged and retried with a delay instead of
  silently looping.
- `PoolError` conforms to `LocalizedError`.

## 1.0.0

- Initial tagged release.
