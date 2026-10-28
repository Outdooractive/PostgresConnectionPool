//
//  Created by Thomas Rasch on 27.10.26.
//

import Foundation
import PostgresConnectionPool
import PostgresNIO
import Testing

@Suite("Pool lifecycle", .serialized, .enabled(if: PostgresHelpers.isAvailable))
struct PoolLifecycleTests {

    private let logger: Logger = {
        var logger = Logger(label: "PoolLifecycleTests")
        logger.logLevel = .critical
        return logger
    }()

    // MARK: - Helpers

    private enum TestError: Error {

        case timedOut
        case expectedFailure
        case unexpectedSuccess

    }

    /// A one-shot async signal.
    private final class Signal: Sendable {

        private let stream: AsyncStream<Void>
        private let continuation: AsyncStream<Void>.Continuation

        init() {
            var continuation: AsyncStream<Void>.Continuation?
            self.stream = AsyncStream { continuation = $0 }
            self.continuation = continuation!
        }

        func send() {
            continuation.yield(())
        }

        func wait() async {
            var iterator = stream.makeAsyncIterator()
            _ = await iterator.next()
        }

    }

    /// A thread-safe counter for callbacks.
    private final class Counter: @unchecked Sendable {

        private let lock = NSLock()
        private var storedValue = 0

        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }

            let value = storedValue
            storedValue += 1
            return value
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }

    }

    /// A thread-safe box for a task handle.
    private final class TaskBox: @unchecked Sendable {

        private let lock = NSLock()
        private var storedTask: Task<Void, Error>?

        var task: Task<Void, Error>? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storedTask
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                storedTask = newValue
            }
        }

    }

    private func waitForWaitingRequests(
        _ pool: PostgresConnectionPool,
        count: Int,
        timeout: Duration = .seconds(5),
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if await pool.poolInfo().waitingRequests == count {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        throw TestError.timedOut
    }

    private func expectCancelled(_ error: any Error) {
        guard case PoolError.cancelled = error else {
            Issue.record("Expected PoolError.cancelled, got \(error)")
            return
        }
    }

    // MARK: - Waiting and cancellation

    @Test(.timeLimit(.minutes(1)))
    func waitingRequestsAreReported() async throws {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(poolSize: 1, maxIdleConnections: nil),
            logger: logger)

        let entered = Signal()
        let release = Signal()

        let holder = Task {
            try await pool.connection { _ in
                entered.send()
                await release.wait()
            }
        }

        await entered.wait()

        let waiter = Task {
            try await pool.connection { connection in
                _ = try await connection.query("SELECT 1", logger: logger)
            }
        }

        try await waitForWaitingRequests(pool, count: 1)

        let info = await pool.poolInfo()
        #expect(info.waitingRequests == 1)
        #expect(info.activeConnections == 1)

        release.send()
        try await holder.value
        try await waiter.value

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingWaitingRequestRemovesIt() async throws {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(poolSize: 1, maxIdleConnections: nil),
            logger: logger)

        let entered = Signal()
        let release = Signal()

        let holder = Task {
            try await pool.connection { _ in
                entered.send()
                await release.wait()
            }
        }

        await entered.wait()

        let waiter = Task {
            try await pool.connection(batchId: 1) { connection in
                _ = try await connection.query("SELECT 1", logger: logger)
            }
        }

        try await waitForWaitingRequests(pool, count: 1)

        waiter.cancel()

        do {
            try await waiter.value
            Issue.record("Expected cancellation")
        }
        catch {
            expectCancelled(error)
        }

        try await waitForWaitingRequests(pool, count: 0)

        release.send()
        try await holder.value

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func abortBatchCancelsOnlyMatchingRequests() async throws {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(poolSize: 1, maxIdleConnections: nil),
            logger: logger)

        let entered = Signal()
        let release = Signal()

        let holder = Task {
            try await pool.connection { _ in
                entered.send()
                await release.wait()
            }
        }

        await entered.wait()

        let first = Task {
            try await pool.connection(batchId: 1) { connection in
                _ = try await connection.query("SELECT 1", logger: logger)
            }
        }
        let second = Task {
            try await pool.connection(batchId: 2) { connection in
                _ = try await connection.query("SELECT 1", logger: logger)
            }
        }

        try await waitForWaitingRequests(pool, count: 2)
        #expect(await pool.poolInfo(batchId: 1).waitingRequests == 1)
        #expect(await pool.poolInfo(batchId: 2).waitingRequests == 1)

        await pool.abortBatch(1)

        do {
            try await first.value
            Issue.record("Expected batch cancellation")
        }
        catch {
            expectCancelled(error)
        }

        try await waitForWaitingRequests(pool, count: 1)

        release.send()
        try await holder.value
        try await second.value

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func shutdownCancelsWaitingRequests() async throws {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(poolSize: 1, maxIdleConnections: nil),
            logger: logger)

        let entered = Signal()
        let release = Signal()

        let holder = Task {
            try await pool.connection { _ in
                entered.send()
                await release.wait()
            }
        }

        await entered.wait()

        let waiter = Task {
            try await pool.connection { connection in
                _ = try await connection.query("SELECT 1", logger: logger)
            }
        }

        try await waitForWaitingRequests(pool, count: 1)

        await pool.shutdown()

        do {
            try await waiter.value
            Issue.record("Expected shutdown cancellation")
        }
        catch {
            expectCancelled(error)
        }

        release.send()
        try await holder.value

        let info = await pool.poolInfo()
        #expect(info.isShutdown)
        #expect(info.openConnections == 0)
        #expect(info.waitingRequests == 0)
    }

    // MARK: - Timeouts and hooks

    @Test(.timeLimit(.minutes(1)))
    func queryTimeoutIsMappedToQueryCancelled() async throws {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(
                queryTimeout: 1.0,
                poolSize: 1,
                maxIdleConnections: nil),
            logger: logger)

        do {
            try await pool.connection { connection in
                let rows = try await connection.query("SELECT pg_sleep(5)", logger: logger)
                for try await _ in rows {}
            }
            Issue.record("Expected query timeout")
        }
        catch {
            guard case PoolError.queryCancelled = error else {
                Issue.record("Expected PoolError.queryCancelled, got \(error)")
                return
            }
        }

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func customReturnHookRunsWhenTheDefaultHealthCheckIsDisabled() async throws {
        let calls = Counter()
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(
                poolSize: 1,
                maxIdleConnections: nil,
                defaultHealthCheckEnabled: false,
                onReturnConnection: { _, _ in
                    _ = calls.next()
                }),
            logger: logger)

        try await pool.connection { connection in
            _ = try await connection.query("SELECT 1", logger: logger)
        }

        #expect(calls.value == 1)

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func failingReturnHookIsRetriedOnce() async throws {
        let calls = Counter()
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(
                poolSize: 2,
                maxIdleConnections: nil,
                onReturnConnection: { _, _ in
                    if calls.next() == 0 {
                        throw TestError.expectedFailure
                    }
                }),
            logger: logger)

        try await pool.connection { connection in
            _ = try await connection.query("SELECT 1", logger: logger)
        }

        #expect(calls.value >= 2)

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func shutdownWhileOpeningAConnectionClosesTheConnection() async throws {
        let entered = Signal()
        let release = Signal()

        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(
                poolSize: 1,
                maxIdleConnections: nil,
                onOpenConnection: { _, _ in
                    entered.send()
                    await release.wait()
                }),
            logger: logger)

        let request = Task {
            try await pool.connection { connection in
                _ = try await connection.query("SELECT 1", logger: logger)
            }
        }

        await entered.wait()
        await pool.shutdown()
        release.send()

        do {
            try await request.value
            Issue.record("Expected shutdown cancellation")
        }
        catch {
            expectCancelled(error)
        }

        let info = await pool.poolInfo()
        #expect(info.isShutdown)
        #expect(info.openConnections == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func transientConnectionFailureKeepsThePoolAliveAndAppliesACooldown() async throws {
        let calls = Counter()
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(
                connectionRetryInterval: 0.2,
                poolSize: 1,
                maxIdleConnections: nil,
                onOpenConnection: { _, _ in
                    if calls.next() == 0 {
                        throw TestError.expectedFailure
                    }
                }),
            logger: logger)

        do {
            try await pool.connection { connection in
                _ = try await connection.query("SELECT 1", logger: logger)
            }
            Issue.record("Expected a transient connection failure")
        }
        catch {
            guard case PoolError.connectionFailed = error else {
                Issue.record("Expected PoolError.connectionFailed, got \(error)")
                return
            }
        }

        #expect(calls.value == 1)
        #expect(await pool.isShutdown == false)
        #expect(await pool.shutdownError == nil)

        // During the cooldown a new request fails fast without opening another
        // connection.
        do {
            try await pool.connection { connection in
                _ = try await connection.query("SELECT 1", logger: logger)
            }
            Issue.record("Expected the cooldown to reject the request")
        }
        catch {
            guard case PoolError.connectionFailed = error else {
                Issue.record("Expected PoolError.connectionFailed, got \(error)")
                return
            }
        }

        #expect(calls.value == 1)

        // After the cooldown the next request retries and succeeds.
        try await Task.sleep(for: .milliseconds(300))

        try await pool.connection { connection in
            _ = try await connection.query("SELECT 1", logger: logger)
        }

        #expect(calls.value == 2)

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func connectionWrapperIsInvalidatedAfterTheCallback() async throws {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(poolSize: 1, maxIdleConnections: nil),
            logger: logger)

        let wrapper = try await pool.connection { $0 }

        #expect(wrapper.isValid == false)

        do {
            _ = try await wrapper.query("SELECT 1", logger: logger)
            Issue.record("Expected a released connection error")
        }
        catch {
            guard case PoolError.connectionFailed = error else {
                Issue.record("Expected PoolError.connectionFailed, got \(error)")
                return
            }
        }

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func postgresErrorsAreMappedAndDescribed() async throws {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(poolSize: 1, maxIdleConnections: nil),
            logger: logger)

        do {
            try await pool.connection { connection in
                let rows = try await connection.query("SELECT 1 / 0", logger: logger)
                for try await _ in rows {}
            }
            Issue.record("Expected a PostgreSQL error")
        }
        catch {
            guard case let PoolError.postgresError(psqlError) = error else {
                Issue.record("Expected PoolError.postgresError, got \(error)")
                return
            }

            #expect(psqlError.pgPoolDescription.contains("division by zero"))
            #expect(psqlError.pgPoolDebugDescription.contains("sqlState: 22012"))

            let destroyed = PoolError.poolDestroyed(psqlError)
            #expect(destroyed.description.contains("poolDestroyed="))
            #expect(destroyed.debugDescription.contains("poolDestroyed="))

            let wrapped = PoolError.postgresError(psqlError)
            #expect(wrapped.description.contains("postgresError="))
            #expect(wrapped.debugDescription.contains("postgresError="))
        }

        await pool.shutdown()
    }

    // MARK: - Metadata and callbacks

    @Test(.timeLimit(.minutes(1)))
    func poolMetadataAndDefaultLogger() async {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(poolSize: 1),
            logger: nil)

        #expect(pool.logger.label == "PoolTests")
        #expect(pool.connectionName == "PoolTests")
        #expect(pool.poolName.hasPrefix("test_username@"))
        #expect(pool.poolName.hasSuffix(":5432/test_database"))
        #expect(await pool.poolInfo().waitingRequests == 0)

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func applicationNameIsSanitizedAndTruncated() async {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(
                applicationName: "My App! With @ Symbols And A Very Long Name 1234567890",
                poolSize: 1),
            logger: logger)

        #expect(pool.connectionName.count <= 32)
        #expect(pool.connectionName.contains("!") == false)
        #expect(pool.connectionName.contains("@") == false)
        #expect(pool.connectionName.hasPrefix("My App"))

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func unixSocketPoolName() async {
        let postgresConfiguration = PostgresConnection.Configuration(
            unixSocketPath: "/tmp/.s.PGSQL.5432",
            username: "user",
            password: "password",
            database: "database")
        let configuration = PoolConfiguration(
            applicationName: "PoolTests",
            postgresConfiguration: postgresConfiguration)

        let pool = PostgresConnectionPool(configuration: configuration, logger: logger)

        #expect(pool.poolName == "postgresql:///database?user=user&host=/tmp/.s.PGSQL.5432")

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func onCloseCallbackRuns() async throws {
        let calls = Counter()
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(
                poolSize: 1,
                maxIdleConnections: nil,
                onCloseConnection: { _, _ in
                    _ = calls.next()
                }),
            logger: logger)

        try await pool.connection { connection in
            _ = try await connection.query("SELECT 1", logger: logger)
        }

        await pool.shutdown()

        #expect(calls.value == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func selfCancelledRequestIsRejected() async throws {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(poolSize: 1, maxIdleConnections: nil),
            logger: logger)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pool.connection { connection in
                _ = try await connection.query("SELECT 1", logger: logger)
            }
        }

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        }
        catch {
            expectCancelled(error)
        }

        #expect(await pool.poolInfo().waitingRequests == 0)

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func wrapperExposesLoggerSqlAndListeners() async throws {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(poolSize: 1, maxIdleConnections: nil),
            logger: logger)

        try await pool.connection { connection in
            #expect(connection.isValid)
            #expect(connection.isClosed == false)
            #expect(connection.logger.label == "PoolLifecycleTests")

            _ = connection.sql()

            let context = connection.addListener(channel: "mvt_test") { _, _ in }
            context.stop()

            try await connection.listen(on: "mvt_test") { _ in }

            let sequence = try await connection.listen("mvt_test")
            _ = sequence
        }

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func customCallbackErrorIsRethrown() async throws {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(poolSize: 1, maxIdleConnections: nil),
            logger: logger)

        do {
            try await pool.connection { _ in
                throw TestError.expectedFailure
            }
            Issue.record("Expected the callback error")
        }
        catch is TestError {
            // expected
        }

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func failingReturnHookEventuallyFailsTheRequest() async throws {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(
                poolSize: 1,
                maxIdleConnections: nil,
                onReturnConnection: { _, _ in
                    throw TestError.expectedFailure
                }),
            logger: logger)

        do {
            try await pool.connection { connection in
                _ = try await connection.query("SELECT 1", logger: logger)
            }
            Issue.record("Expected a connection failure")
        }
        catch {
            guard case PoolError.connectionFailed = error else {
                Issue.record("Expected PoolError.connectionFailed, got \(error)")
                return
            }
        }

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func failingReturnHookRetriesWithAnotherIdleConnection() async throws {
        let calls = Counter()
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(
                poolSize: 2,
                maxIdleConnections: nil,
                onReturnConnection: { _, _ in
                    if calls.next() == 2 {
                        throw TestError.expectedFailure
                    }
                }),
            logger: logger)

        let entered = (0 ..< 2).map { _ in Signal() }
        let releases = (0 ..< 2).map { _ in Signal() }

        let holders = (0 ..< 2).map { index in
            Task {
                try await pool.connection { _ in
                    entered[index].send()
                    await releases[index].wait()
                }
            }
        }

        for signal in entered {
            await signal.wait()
        }

        for signal in releases {
            signal.send()
        }

        for holder in holders {
            try await holder.value
        }

        try await pool.connection { connection in
            _ = try await connection.query("SELECT 1", logger: logger)
        }

        #expect(calls.value >= 4)

        await pool.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func throwingCloseHookStillClosesTheConnection() async throws {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(
                poolSize: 1,
                maxIdleConnections: nil,
                onCloseConnection: { _, _ in
                    throw TestError.expectedFailure
                }),
            logger: logger)

        try await pool.connection { connection in
            _ = try await connection.query("SELECT 1", logger: logger)
        }

        await pool.shutdown()

        #expect(await pool.poolInfo().openConnections == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationAfterCheckoutReleasesTheConnection() async throws {
        let box = TaskBox()
        let start = Signal()
        let callbackRan = Counter()

        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(
                poolSize: 1,
                maxIdleConnections: nil,
                onReturnConnection: { _, _ in
                    box.task?.cancel()
                }),
            logger: logger)

        let waiter = Task {
            await start.wait()
            try await pool.connection(batchId: 1) { _ in
                _ = callbackRan.next()
            }
        }
        box.task = waiter
        start.send()

        do {
            try await waiter.value
            Issue.record("Expected cancellation")
        }
        catch {
            expectCancelled(error)
        }

        #expect(callbackRan.value == 0)

        // The connection from the cancelled checkout must be back in the pool.
        try await pool.connection { connection in
            _ = try await connection.query("SELECT 1", logger: logger)
        }

        await pool.shutdown()
    }

    // MARK: - Idle culling

    @Test(.timeLimit(.minutes(1)))
    func idleConnectionsAreCulled() async throws {
        let pool = PostgresConnectionPool(
            configuration: PostgresHelpers.poolConfiguration(
                poolSize: 4,
                maxIdleConnections: 1,
                defaultHealthCheckEnabled: false),
            logger: logger,
            maintenanceInterval: 0.02,
            idleConnectionsCheckInterval: 0.1)

        let entered = (0 ..< 4).map { _ in Signal() }
        let releases = (0 ..< 4).map { _ in Signal() }

        let tasks = (0 ..< 4).map { index in
            Task {
                try await pool.connection { _ in
                    entered[index].send()
                    await releases[index].wait()
                }
            }
        }

        for signal in entered {
            await signal.wait()
        }

        // Keep the connections active across at least one maintenance tick so
        // the idle-culling window records the peak usage.
        try await Task.sleep(for: .milliseconds(100))
        #expect(await pool.poolInfo().activeConnections == 4)

        for signal in releases {
            signal.send()
        }

        for task in tasks {
            try await task.value
        }

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)

        while clock.now < deadline {
            if await pool.poolInfo().availableConnections <= 1 {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        let info = await pool.poolInfo()
        #expect(info.availableConnections == 1)
        #expect(info.openConnections == 1)

        // Let the rolling window overflow at least once.
        try await Task.sleep(for: .milliseconds(300))

        await pool.shutdown()
    }

}
