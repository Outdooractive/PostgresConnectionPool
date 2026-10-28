//
//  Created by Thomas Rasch on 28.10.26.
//

import Foundation
import PostgresConnectionPool
import PostgresNIO
import Testing

/// Evidence for evaluating a PostgresClient-backed pool. These tests exercise
/// the upstream pool directly; they do not change the package implementation.
@Suite("PostgresClient evaluation", .serialized, .enabled(if: PostgresHelpers.isAvailable))
struct PostgresClientEvaluationTests {

    private let logger: Logger = {
        var logger = Logger(label: "PostgresClientEvaluationTests")
        logger.logLevel = .critical
        return logger
    }()

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

    private final class Flag: @unchecked Sendable {

        private let lock = NSLock()
        private var storedValue = false

        func set() {
            lock.lock()
            defer { lock.unlock() }
            storedValue = true
        }

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }

    }

    private func withClient<T>(
        _ configuration: PostgresClient.Configuration,
        _ body: (PostgresClient) async throws -> T,
    ) async throws -> T {
        let client = PostgresClient(configuration: configuration, backgroundLogger: logger)
        let runTask = Task { await client.run() }

        do {
            let result = try await body(client)
            runTask.cancel()
            _ = await runTask.value
            return result
        }
        catch {
            runTask.cancel()
            _ = await runTask.value
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func leasesConnectionsAndRunsQueries() async throws {
        try await withClient(PostgresHelpers.postgresClientConfiguration()) { client in
            try await client.withConnection { connection in
                let rows = try await connection.query("SELECT 1 AS value", logger: logger)
                var count = 0
                for try await _ in rows {
                    count += 1
                }
                #expect(count == 1)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func queryReleasesItsLeaseWhenConsumed() async throws {
        try await withClient(PostgresHelpers.postgresClientConfiguration(maximumConnections: 1)) { client in
            for _ in 0 ..< 3 {
                let rows = try await client.query("SELECT 1", logger: logger)
                for try await _ in rows {}
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingAWaitingLeaseTerminatesTheWaiter() async throws {
        try await withClient(PostgresHelpers.postgresClientConfiguration(maximumConnections: 1)) { client in
            let entered = Signal()
            let release = Signal()

            let holder = Task {
                try await client.withConnection { _ in
                    entered.send()
                    await release.wait()
                }
            }

            await entered.wait()

            let waiter = Task {
                try await client.withConnection { _ in }
            }

            try await Task.sleep(for: .milliseconds(200))
            waiter.cancel()

            let result: Result<Void, Error> = await {
                do {
                    try await waiter.value
                    return .success(())
                }
                catch {
                    return .failure(error)
                }
            }()

            if case .success = result {
                Issue.record("Expected the waiting lease to be cancelled")
            }

            release.send()
            try await holder.value
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func startupParametersApplyToPhysicalConnections() async throws {
        let configuration = PostgresHelpers.postgresClientConfiguration(
            additionalStartupParameters: [
                ("application_name", "PostgresClientEvaluation"),
                ("options", "-c statement_timeout=1000"),
            ])

        try await withClient(configuration) { client in
            try await client.withConnection { connection in
                let rows = try await connection.query(
                    "SELECT current_setting('application_name') AS app, current_setting('statement_timeout') AS timeout",
                    logger: logger)
                for try await row in rows {
                    let row = row.makeRandomAccess()
                    #expect(row[data: "app"].string == "PostgresClientEvaluation")
                    #expect(row[data: "timeout"].string == "1s")
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingRunReturnsBeforeActiveLeasesFinish() async throws {
        let client = PostgresClient(
            configuration: PostgresHelpers.postgresClientConfiguration(maximumConnections: 1),
            backgroundLogger: logger)

        let entered = Signal()
        let release = Signal()

        let runFinished = Flag()
        let runTask = Task {
            await client.run()
            runFinished.set()
        }

        let holder = Task {
            try await client.withConnection { _ in
                entered.send()
                await release.wait()
            }
        }

        await entered.wait()

        try await Task.sleep(for: .milliseconds(100))
        runTask.cancel()

        // run() returns as soon as cancellation is observed, even though the
        // lease callback is still active. A wrapper needs to track and cancel
        // those tasks if abrupt shutdown is required.
        try await Task.sleep(for: .milliseconds(200))
        #expect(runFinished.isSet)

        release.send()
        try await holder.value

        _ = await runTask.value
    }

}
