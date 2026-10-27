# Development

## Requirements

- Swift 6.3.3 or newer
- Docker (for the local integration database) or an existing PostgreSQL server
- `swiftformat` for the repository formatting check

## Unit tests

The database-backed suites are enabled only when `POSTGRES_HOSTNAME` is set or
`POSTGRES_TESTS=1` is present. Without either, `swift test` runs the pure unit
tests and skips everything that needs a server:

```bash
swift test
```

This is the fastest feedback loop and the same mode used by the macOS CI job.

## Integration tests

Start the bundled PostgreSQL 18 service:

```bash
docker compose up -d
POSTGRES_TESTS=1 swift test
```

`POSTGRES_TESTS=1` means "use the default localhost connection". To point at a
different server:

```bash
export POSTGRES_HOSTNAME=localhost
export POSTGRES_PORT=5432
export POSTGRES_USER=test_username
export POSTGRES_PASSWORD=test_password
export POSTGRES_DB=test_database

swift test
```

The integration suites are:

- `ConnectionTests` — leasing, pool size, diagnostics and idle-closing
- `ConnectionErrorTests` — bad host, port, credentials and TLS
- `PoolLifecycleTests` — waiting requests, cancellation, batch cancellation,
  shutdown, query timeouts, hooks, wrapper lifetime, idle culling and error mapping

The tests use `PostgresHelpers.isAvailable` as the suite gate. If you add a new
database-backed suite, add the same trait:

```swift
@Suite("My suite", .serialized, .enabled(if: PostgresHelpers.isAvailable))
```

## Coverage

```bash
POSTGRES_TESTS=1 scripts/run-coverage.sh 90
```

The script removes stale profiles, runs the tests with coverage, merges
`.profraw` files when SwiftPM does not produce a `default.profdata`, prints a
per-file report and enforces the line-coverage gate. CI runs the same command
against PostgreSQL 18 and currently requires at least **90%** line coverage.

Coverage is a floor, not a substitute for edge-case tests. New behavior should
come with focused tests for cancellation, failure and concurrency paths, not
only happy-path coverage.

## Documentation

```bash
swift package --allow-writing-to-directory .build/documentation \
    generate-documentation --target PostgresConnectionPool --disable-indexing
```

The DocC build must be warning-free. Public API additions need DocC comments.

## Formatting

The repository uses the checked-in `.swiftformat` configuration:

```bash
swiftformat --lint --swift-version 6.3 Sources Tests Package.swift
```

Run without `--lint` to apply the changes.

## CI

`.github/workflows/swift.yml` runs:

- **macOS** — unit tests with Swift 6.3.3
- **Linux** — full tests against PostgreSQL 18 (the minimum supported
  production version) in the `swift:6.3.3` container
- **coverage** — full tests against PostgreSQL 18 with the 90% gate
- **DocC** — documentation build

The integration tests use the `postgres` service hostname inside the container
job. Locally they use `localhost` unless `POSTGRES_HOSTNAME` overrides it.

## Failure behavior

Transient connection failures fail the request but keep the pool alive and apply
`connectionRetryInterval` before the next attempt. Authentication, invalid
database names and TLS configuration errors shut the pool down. Tests for both
paths live in `ConnectionErrorTests`; the cooldown is covered in
`PoolLifecycleTests`.

## Test design

- Prefer deterministic tests over sleeps. Use the `Signal` helper for
  synchronisation and `timeLimit` to bound every potentially blocking test.
- Every test that creates a pool must call `shutdown()`, including on failure.
  A missing shutdown triggers the pool and connection deinitialization
  assertions.
- Avoid relying on exact PostgreSQL error prose when the SQLSTATE is enough.
- Test cancellation while waiting, cancellation after checkout, failed health
  checks, failed connection hooks, query timeouts and shutdown.
- New public API requires tests for its failure behavior as well as its success
  behavior.

## Relationship to `PostgresClient`

`PostgresNIO.PostgresClient` is the upstream connection pool. This package keeps
its own pool because it adds batch cancellation, per-connection diagnostics and
connection hooks that `PostgresClient` does not expose. Any future replacement
must preserve those features or provide a migration path. See the README for the
current trade-offs.
