//
//  Created by Thomas Rasch on 23.03.22.
//

import Collections
import Foundation
import PostgresNIO

/// A simple connection pool for PostgreSQL.
public actor PostgresConnectionPool {

    private static let postgresMaxNameLength: Int = 32 // PostgreSQL allows 64 but we add some extra info
    private static let healthCheckInterval: TimeInterval = 5.0
    private static let idleConnectionsCheckInterval: TimeInterval = 60.0

    private let logger: Logger
    private let eventLoopGroup: EventLoopGroup

    private let postgresConfiguration: PostgresConnection.Configuration
    private let connectionName: String
    private let poolName: String
    private let poolSize: Int
    private let maxIdleConnections: Int?
    private let queryTimeout: TimeInterval?

    private let onOpenConnection: ((PostgresConnection, Logger) async throws -> Void)?
    private let onReturnConnection: ((PostgresConnection, Logger) async throws -> Void)?
    private let onCloseConnection: ((PostgresConnection, Logger) async throws -> Void)?

    private var connections: [PoolConnection] = []
    private var available: Deque<PoolConnection> = []
    private var continuations: Deque<PoolContinuation> = []
    private var inUseConnectionCounts: Deque<Int> = []

    private var didStartWatcherTask = false
    private var didShutdown = false

    // MARK: -

    /// Initializes and configures a new pool. You should call ``shutdown()``
    /// when you are done with the pool.
    public init(configuration: PoolConfiguration, logger: Logger? = nil) {
        self.logger = logger ?? {
            var logger = Logger(label: configuration.applicationName)
            logger.logLevel = .info
            return logger
        }()
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: configuration.poolSize * 2)

        self.connectionName = String(configuration.applicationName.replacingPattern("[^-\\w\\d\\s()]", with: "").prefix(PostgresConnectionPool.postgresMaxNameLength))
        self.poolName = "\(configuration.connection.username)@\(configuration.connection.host):\(configuration.connection.port)/\(configuration.connection.database)"
        self.poolSize = configuration.poolSize
        self.maxIdleConnections = configuration.maxIdleConnections
        self.queryTimeout = configuration.queryTimeout

        self.onOpenConnection = configuration.onOpenConnection
        self.onReturnConnection = configuration.onReturnConnection
        self.onCloseConnection = configuration.onCloseConnection

        var postgresConfiguration = PostgresConnection.Configuration(
            host: configuration.connection.host,
            port: configuration.connection.port,
            username: configuration.connection.username,
            password: configuration.connection.password,
            database: configuration.connection.database,
            tls: .disable)
        postgresConfiguration.options.connectTimeout = .seconds(Int64(configuration.connectTimeout))
        self.postgresConfiguration = postgresConfiguration
    }

//    deinit {
//        assert(didShutdown, "Must call shutdown() before releasing a PostgresConnectionPool")
//    }

    /// Takes one connection from the pool and dishes it out to the caller.
    @discardableResult
    public func connection<T>(
        _ callback: (PostgresConnection) async throws -> T)
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

            logger.debug("[\(poolName)] Failed to get a connection: \(error)")

            throw error
        }
    }

    func getConnection() async throws -> PoolConnection {
        guard !didShutdown else { throw PoolError.poolDestroyed }

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
        // It can happen that the connection is returned before it's being used
        // (e.g. on cancellation)
        if connection.state != .available {
            connection.state = .available
            available.append(connection)
        }
        else {
            assert(available.contains(connection))
        }

        Task.detached { [weak self] in
            await self?.handleNextContinuation()
        }
    }

    /// Releases all resources in the pool and shuts down the event loop.
    /// All further uses of the pool will throw an error.
    ///
    /// Must be done here since Swift doesn't yet allow async deinit.
    public func shutdown() async {
        logger.debug("[\(poolName)] shutdown()")

        didShutdown = true

        // Cancel all waiting continuations
        for poolContinuation in continuations {
            poolContinuation.continuation.resume(throwing: PoolError.cancelled)
        }
        continuations.removeAll()

        available.removeAll()

        // Close all open connections
        connections.forEach({ $0.state = .closed })
        for poolConnection in connections {
            await closeConnection(poolConnection)
        }
        connections.removeAll()

        // Shut down the event loop.
        try? await eventLoopGroup.shutdownGracefully()
    }

    // MARK: - Private

    private func closeConnection(_ poolConnection: PoolConnection) async {
        poolConnection.state = .closed

        guard let connection = poolConnection.connection else { return }

        if let onCloseConnection = onCloseConnection {
            do {
                try await onCloseConnection(connection, logger)
            }
            catch {
                logger.warning("[\(poolName)] onCloseConnection error: \(error)")
            }
        }

        do {
            try await connection.close()
        }
        catch {
            logger.warning("[\(poolName)] connection.close() error: \(error)")
        }
    }

    private func checkConnections() async {
        defer {
            Task.after(
                seconds: PostgresConnectionPool.healthCheckInterval,
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

        await closeIdleConnections()

        let usageCounter = connections.reduce(0) { $0 + $1.usageCounter }
        logger.debug("[\(poolName)] \(connections.count) connections (\(available.count) available, \(usageCounter) queries), \(continuations.count) continuations left")

        // Check for waiting continuations and open a new connection if possible
        if connections.count < poolSize,
            continuations.isNotEmpty
        {
            Task.detached { [weak self] in
                await self?.openConnection()
            }
        }
    }

    // TODO: This doesn't work well with short bursts of activity that fall between the 5 seconds check interval
    private func closeIdleConnections() async {
        guard let maxIdleConnections else { return }

        // 60 seconds
        let minArrayLength = Int(PostgresConnectionPool.idleConnectionsCheckInterval / PostgresConnectionPool.healthCheckInterval)
        assert(minArrayLength >= 1, "idleConnectionsCheckInterval must be higher than healthCheckInterval")
        if inUseConnectionCounts.count > minArrayLength {
            inUseConnectionCounts.removeFirst()
        }
        inUseConnectionCounts.append(connections.count - available.count)

        guard continuations.isEmpty,
              inUseConnectionCounts.count >= minArrayLength,
              let maxInUse = inUseConnectionCounts.max()
        else { return }

        let toClose = (available.count - maxIdleConnections) - maxInUse
        guard toClose > 0 else { return }

        logger.debug("[\(poolName)] Closing \(toClose) idle connections")

        for _ in 1...toClose {
            guard let poolConnection = available.popFirst() else { break }

            await closeConnection(poolConnection)
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

                poolConnection.state = .active(Date())

                do {
                    // Connection check, etc.
                    if let onReturnConnection = onReturnConnection {
                        try await onReturnConnection(connection, logger)
                    }

                    return poolContinuation.continuation.resume(returning: poolConnection)
                }
                catch {
                    logger.warning("[\(poolName)] Health check for connection \(poolConnection.id) failed")

                    await closeConnection(poolConnection)
                }
            }
            else {
                await closeConnection(poolConnection)
            }
        }
    }

    private func nameForConnection(id: Int) -> String {
        "\(connectionName) - CONN:\(id)"
    }

    private func openConnection() async {
        if !didStartWatcherTask {
            didStartWatcherTask = true

            Task.after(
                seconds: PostgresConnectionPool.healthCheckInterval,
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
                try await connection.query(PostgresQuery(stringLiteral: "SET application_name='\(nameForConnection(id: poolConnection.id))'"), logger: logger)

                if let queryTimeout {
                    try await connection.query(PostgresQuery(stringLiteral: "SET statement_timeout=\(Int(queryTimeout * 1000))"), logger: logger)
                }

                if let onOpenConnection = onOpenConnection {
                    try await onOpenConnection(connection, logger)
                }
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
