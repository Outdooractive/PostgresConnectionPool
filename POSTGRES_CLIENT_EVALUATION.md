# Evaluating `PostgresNIO.PostgresClient`

Status: **evaluated; keep the custom pool for the 1.x series**

Tracking issue: [#13](https://github.com/Outdooractive/PostgresConnectionPool/issues/13)

## Summary

`PostgresNIO.PostgresClient` now provides a maintained connection pool and covers
most of the mechanics this package implements. It is a good foundation for a
future major version, but it cannot replace `PostgresConnectionPool` 1.x
without breaking public API and losing behavior used by `mvt-postgis`.

Decision:

- Keep the custom pool for 1.x.
- Align behavior with `PostgresClient` where it is cheap (shared event loop,
  transient error handling, cooldown, optional default health check).
- Revisit a 2.0 migration when the remaining feature gaps are acceptable or
  `PostgresClient` exposes the missing hooks/observability.

The evaluation tests live in
`Tests/PostgresConnectionPoolTests/PostgresClientEvaluationTests.swift` and run
with:

```bash
POSTGRES_TESTS=1 swift test --filter PostgresClientEvaluationTests
```

## Feature comparison

| Capability | `PostgresConnectionPool` | `PostgresClient` | Adapter feasibility |
| --- | --- | --- | --- |
| Pool size | `poolSize` | `maximumConnections` | direct |
| Minimum connections | no | `minimumConnections` | PostgresClient better |
| Idle timeout | rolling `maxIdleConnections` heuristic | `connectionIdleTimeout` | semantics differ |
| Idle keep-alive | no | `keepAliveBehavior` | PostgresClient better |
| Connect timeout | `connectTimeout` | `options.connectTimeout` | direct |
| Shared event loop | yes, default shared | yes, default shared | equivalent |
| TLS | `PostgresConnection.Configuration.TLS` (`NIOSSLContext`) | `PostgresClient.Configuration.TLS` (`NIOSSL.TLSConfiguration`) | **breaking config change** |
| Unix socket | yes | yes | equivalent |
| Established channel | yes | no | **lost** |
| Additional startup parameters | via `onOpenConnection` | `options.additionalStartupParameters` | equivalent |
| Service lifecycle / run task | no external task | requires `run()` in a long-lived task | adapter must own a task |
| Per-query lease release | callback lifetime | row-sequence lifetime for `query` | equivalent |
| Cancel a waiting lease | `abortBatch` / task cancellation | task cancellation | adapter can track tasks |
| Abort active queries | closes connections on shutdown only | no direct API | needs lease/task tracking |
| Query timeout | `statement_timeout` per connection | startup `options=-c statement_timeout=...` | equivalent |
| Application name | `SET application_name` | startup parameter | equivalent |
| Read-only session | `onOpenConnection` | first-lease setup or startup `options` | adapter can approximate |
| Batch IDs | yes | no | adapter must add |
| Query/runtime diagnostics | `PoolInfo` | no public pool introspection | **adapter loses open/available counts** |
| Open/available connection counts | yes | not exposed | **lost** |
| `onOpenConnection` | per physical connection | no hook | first-lease setup only |
| `onReturnConnection` | per lease | adapter can call before lease | equivalent |
| `onCloseConnection` | per physical close | no hook | **lost** |
| PostgresKit `sql()` | yes | on leased connection | equivalent |
| Listen/notify | yes | on leased connection | equivalent, same lifetime caveats |
| Transient error recovery | fail request + cooldown, pool stays alive | internal pool retry | semantics differ |
| Permanent config errors | pool shutdown | pool continues/retries | adapter can map policy |
| Public metrics | `PoolInfo` | logging only | **not equivalent** |

## Prototype findings

The evaluation tests exercise `PostgresClient` directly:

- **Leasing and queries** work with `client.withConnection`.
- **`client.query` releases its lease when the row sequence finishes**,
  confirmed with `maximumConnections = 1` and three sequential queries.
- **Cancelling a waiting lease terminates the waiter** (the test observes a
  thrown cancellation/error, not a hang).
- **Startup parameters work**: `application_name` and
  `options=-c statement_timeout=1000` are visible through `current_setting`.
- **Cancelling `run()` returns before active lease callbacks finish.** A wrapper
  that needs abrupt shutdown must track and cancel its own lease tasks; relying
  on `run()` cancellation alone is not enough.

## Why not migrate in 1.x

1. `PoolConfiguration` wraps `PostgresConnection.Configuration`. Moving to
   `PostgresClient.Configuration` changes the public configuration type, TLS
   types and the `establishedChannel` initializer. That is a source-breaking
   change.
2. `PoolInfo` exposes open/available/active counts and every connection's query
   state. `PostgresClient` does not expose its pool internals, so those counts
   cannot be preserved without a separate metrics/hook API.
3. `onCloseConnection` has no equivalent in `PostgresClient`.
4. `connectionRetryInterval`, `maxIdleConnections` and the current transient
   failure semantics do not map one-to-one.
5. `mvt-postgis` depends on `PoolInfo` for timeout diagnostics and uses
   `onOpenConnection` for read-only sessions. Migrating would require coordinated
   changes in that package.

The custom pool is now hardened, has cancellation-aware waiting, transient
failure handling, a shared event loop and 90%+ test coverage. The remaining
benefit of `PostgresClient` is upstream maintenance, not a missing critical
feature.

## Conditions for revisiting a 2.0

A migration becomes attractive when one of these is true:

- `PostgresClient` exposes pool observability or connection hooks.
- `mvt-postgis` can drop `PoolInfo`, `onCloseConnection` and established-channel
  support.
- The custom pool becomes a maintenance burden compared with the adapter code.
- The package can make a major release with a migration guide and a reduced API
  (`PoolConfiguration`, `PoolInfo`, `onCloseConnection`).

A 2.0 prototype should:

1. Own and run a `PostgresClient` task inside the adapter.
2. Track active lease tasks and batch IDs for `abortBatch` and shutdown.
3. Map `queryTimeout` and application name to startup parameters.
4. Run `onOpenConnection` on the first lease of each connection ID and
   `onReturnConnection` before each lease.
5. Provide a new diagnostics API that only reports leased connections, or add
   an equivalent observability hook upstream.
6. Drop or redesign `onCloseConnection`, `maxIdleConnections` and
   `connectionRetryInterval`.
7. Run the full `mvt-postgis` integration and coverage suite.

## References

- Issue: [#13](https://github.com/Outdooractive/PostgresConnectionPool/issues/13)
- Audit PR: [#12](https://github.com/Outdooractive/PostgresConnectionPool/pull/12)
- Transient failure PR: [#16](https://github.com/Outdooractive/PostgresConnectionPool/pull/16)
- `PostgresClient`: <https://github.com/vapor/postgres-nio/blob/main/Sources/PostgresNIO/Pool/PostgresClient.swift>
