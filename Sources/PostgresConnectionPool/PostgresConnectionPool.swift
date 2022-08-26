//
//  Created by Thomas Rasch on 23.03.22.
//

import Collections
import Foundation
import PostgresNIO

/// A simple connection pool for PostgreSQL.
public actor PostgresConnectionPool {

    private static let postgresMaxNameLength: Int = 32 // PostgreSQL allows 64 but we add some extra info

    private let logger: Logger
    private let eventLoopGroup: EventLoopGroup

    private let postgresConfiguration: PostgresConnection.Configuration
    private let connectionName: String
    private let poolName: String
    private let poolSize: Int
    private let queryTimeout: TimeInterval

    private var connections: [PoolConnection] = []
    private var available: Deque<PoolConnection> = []
    private var continuations: Deque<PoolContinuation> = []

    private var didStartWatcherTask: Bool = false

    // MARK: -

    public init(configuration: PoolConfiguration, logger: Logger? = nil) {
        self.logger = logger ?? {
            var logger = Logger(label: configuration.applicationName)
            logger.logLevel = .info
            return logger
        }()
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: configuration.poolSize * 2)

        self.connectionName = String(configuration.applicationName.replacingPattern("[^\\w\\d\\s]", with: "").prefix(PostgresConnectionPool.postgresMaxNameLength))
        self.poolName = "\(configuration.connection.username)@\(configuration.connection.host):\(configuration.connection.port)/\(configuration.connection.database)"
        self.poolSize = configuration.poolSize
        self.queryTimeout = configuration.queryTimeout

        var postgresConnection = PostgresConnection.Configuration.Connection(
            host: configuration.connection.host,
            port: configuration.connection.port)
        postgresConnection.connectTimeout = .seconds(Int64(configuration.connectTimeout))

        self.postgresConfiguration = PostgresConnection.Configuration(
            connection: postgresConnection,
            authentication: .init(
                username: configuration.connection.username,
                database: configuration.connection.database,
                password: configuration.connection.password),
            tls: .disable)
    }

    deinit {
        assert(connections.isEmpty, "Must call destroy() before releasing a PostgresConnectionPool")
        try? eventLoopGroup.syncShutdownGracefully()
    }

    /// Takes one connection from the pool and dishes it out to the caller.
    @discardableResult
    public func connection<T>(
        callback: (PostgresConnection) async throws -> T)
        async throws
        -> T
    {
        var poolConnection: PoolConnection?

        do {
            poolConnection = try await getConnection()

            if Task.isCancelled {
                await releaseConnection(poolConnection!)
                throw PoolError.cancelled
            }

            let result = try await callback(poolConnection!.connection!)

            await releaseConnection(poolConnection!)

            return result
        }
        catch {
            if let poolConnection = poolConnection {
                await releaseConnection(poolConnection)
            }

            logger.debug("Failed to get a pool connection: \(error)")

            throw error
        }
    }

    func getConnection() async throws -> PoolConnection {
        return try await withCheckedThrowingContinuation({ (continuation: PostgresCheckedContinuation) in
            self.continuations.append(PoolContinuation(continuation: continuation))

            if connections.count < poolSize {
                Task.detached { [weak self] in
                    await self?.openConnection()
                }
            }
            else if available.count > 0 {
                Task.detached { [weak self] in
                    await self?.handleNextContinuation()
                }
            }
        })
    }

    func releaseConnection(_ connection: PoolConnection) async {
        connection.state = .available
        available.append(connection)

        Task.detached { [weak self] in
            await self?.handleNextContinuation()
        }
    }

    /// Releases all resources in the pool.
    ///
    /// It's actually no problem to continue to use the PostgresConnectionPool after calling destroy(),
    /// it will just close all connections and abort any waiting continuations.
    public func destroy() async {
        for poolContinuation in continuations {
            poolContinuation.continuation.resume(throwing: PoolError.cancelled)
        }
        continuations.removeAll()

        available.removeAll()

        connections.forEach({ $0.state = .closed })
        for poolConnection in connections {
            try? await poolConnection.connection?.close()
        }
        connections.removeAll()
    }

    // MARK: - Private

    private func checkConnections() async {
        logger.debug("Checking open connections")

        defer {
            Task.after(
                seconds: 5.0,
                priority: .low,
                operation: { [weak self] in
                    await self?.checkConnections()
                })
        }

        connections.removeAll(where: { connection in
            connection.state == .closed
                || (connection.state != .connecting && connection.connection?.isClosed ?? false)
        })

        // TODO: Kill self if too many stuck connections

        logger.debug("[\(poolName)] Check connections: \(continuations.count) continuations left, \(connections.count) connections, \(available.count) available")

        // Check for waiting continuations and open a new connection if possible
        if connections.count < poolSize,
            continuations.isNotEmpty
        {
            Task.detached { [weak self] in
                await self?.openConnection()
            }
        }
    }

    private func handleNextContinuation() async {
        guard continuations.isNotEmpty else {
            logger.debug("[\(poolName)] No more continuations left, \(connections.count) connections, \(available.count) available")
            return
        }

        logger.debug("[\(poolName)] Next continuation: \(continuations.count) left")

        // Next connection from `available`
        // Make sure that there is an open connection
        if let poolConnection = available.popFirst(),
           poolConnection.state == .available
        {
            if let connection = poolConnection.connection {
                guard let poolContinuation = continuations.popFirst() else {
                    available.append(poolConnection)
                    return
                }

                do {
                    poolConnection.state = .active(Date())

                    // TODO: Shouldn't be necessary, maybe make it optional
                    try await connection.query("SELECT 1", logger: logger)

                    return poolContinuation.continuation.resume(returning: poolConnection)
                }
                catch {
                    logger.warning("[\(poolName)] Health check for connection \(poolConnection.id) failed")
                    poolConnection.state = .closed
                    try? await poolConnection.connection?.close()
                }
            }
            else {
                poolConnection.state = .closed
            }
        }
    }

    private func openConnection() async {
        if !didStartWatcherTask {
            didStartWatcherTask = true

            Task.after(
                seconds: 5.0,
                priority: .low,
                operation: { [weak self] in
                    await self?.checkConnections()
                })
        }

        guard continuations.isNotEmpty else { return }

        if available.isNotEmpty {
            await handleNextContinuation()
            return
        }

        connections.removeAll(where: { connection in
            connection.state == .closed
                || (connection.state != .connecting && connection.connection?.isClosed ?? false)
        })

        guard connections.count < poolSize else { return }

        let poolConnection = PoolConnection()
        connections.append(poolConnection)

        let connectionStartTimestamp = Date()

        do {
            let connection = try await PostgresConnection.connect(
                on: eventLoopGroup.next(),
                configuration: postgresConfiguration,
                id: poolConnection.id,
                logger: logger)
            let connectionRuntime = fabs(connectionStartTimestamp.timeIntervalSinceNow)
            logger.debug("[\(poolName)] Connection \(poolConnection.id) established in \(connectionRuntime.rounded(toPlaces: 2))s")

            do {
                try await connection.query(PostgresQuery(stringLiteral: "SET application_name='\(connectionName) - CONN:\(poolConnection.id)'"), logger: logger)
                try await connection.query(PostgresQuery(stringLiteral: "SET statement_timeout=\(Int(queryTimeout * 1000))"), logger: logger)
            }
            catch {
                poolConnection.state = .closed
                try await connection.close()

                Task.detached { [weak self] in
                    await self?.openConnection()
                }

                return
            }

            poolConnection.connection = connection
            poolConnection.state = .available
            available.append(poolConnection)

            await handleNextContinuation()
        }
        catch {
            let connectionRuntime = fabs(connectionStartTimestamp.timeIntervalSinceNow)
            logger.debug("[\(poolName)] Connection \(poolConnection.id) failed after \(connectionRuntime.rounded(toPlaces: 2))s: \(error)")
            poolConnection.state = .closed

            Task.detached { [weak self] in
                await self?.openConnection()
            }
        }
    }

}
