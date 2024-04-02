//
//  Created by Thomas Rasch on 23.03.22.
//

import Collections
import Foundation
import PostgresNIO

/// A simple connection pool for PostgreSQL.
public actor PostgresConnectionPool {

    private static let postgresMaxNameLength = 32 // PostgreSQL allows 64 but we add some extra info
    private static let healthCheckInterval: TimeInterval = 5.0
    private static let idleConnectionsCheckInterval: TimeInterval = 60.0

    private let logger: Logger
    private let eventLoopGroup: EventLoopGroup

    private let postgresConfiguration: PostgresConnection.Configuration
    private let connectionName: String
    private let poolName: String
    private let poolSize: Int
    private let connectionRetryInterval: TimeInterval
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

    public private(set) var isShutdown = false
    public private(set) var shutdownError: PSQLError?

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
        self.poolSize = configuration.poolSize
        self.connectionRetryInterval = configuration.connectionRetryInterval
        self.maxIdleConnections = configuration.maxIdleConnections
        self.queryTimeout = configuration.queryTimeout

        let dbUsername = configuration.postgresConfiguration.username
        let dbDatabase = configuration.postgresConfiguration.database ?? dbUsername
        if let host = configuration.postgresConfiguration.host,
           let port = configuration.postgresConfiguration.port
        {
            self.poolName = "\(dbUsername)@\(host):\(port)/\(dbDatabase)"
        }
        else if let unixSocketPath = configuration.postgresConfiguration.unixSocketPath {
            self.poolName = "postgresql:///\(dbDatabase)?user=\(dbUsername)&host=\(unixSocketPath)"
        }
        else if let channel = configuration.postgresConfiguration.establishedChannel {
            self.poolName = "\(dbUsername)@EstablishedChannel<\(channel)>/\(dbDatabase)"
        }
        else {
            self.poolName = "<Unknown connection>"
        }

        self.onOpenConnection = configuration.onOpenConnection
        self.onReturnConnection = configuration.onReturnConnection
        self.onCloseConnection = configuration.onCloseConnection

        var postgresConfiguration = configuration.postgresConfiguration
        postgresConfiguration.options.connectTimeout = .seconds(Int64(configuration.connectTimeout))
        self.postgresConfiguration = postgresConfiguration
    }

//    deinit {
//        assert(didShutdown, "Must call shutdown() before releasing a PostgresConnectionPool")
//    }

    /// Takes one connection from the pool and dishes it out to the caller.
    ///
    /// - Parameters:
    ///   - batchId: An optional integer value associated with the connection. See also ``abortBatch(_:)``.
    ///   - callback: A closure with a connection to the database server.
    @discardableResult
    public func connection<T>(
        batchId: Int? = nil,
        _ callback: (PostgresConnectionWrapper) async throws -> T)
        async throws -> T
    {
        var poolConnection: PoolConnection?

        do {
            poolConnection = try await getConnection(batchId: batchId)

            if Task.isCancelled {
                await releaseConnection(poolConnection!)

                if let batchId {
                    await abortBatch(batchId)
                }

                throw PoolError.cancelled
            }

            let result = try await PostgresConnectionWrapper.distribute(
                poolConnection: poolConnection,
                callback: callback)

            await releaseConnection(poolConnection!)

            return result
        }
        catch {
            if let poolConnection {
                await releaseConnection(poolConnection)
            }

            logger.debug("[\(poolName)] Connection or query error: \(error)")

            throw error
        }
    }

    /// Adds a connection placeholder to the list of waiting connections.
    private func getConnection(batchId: Int? = nil) async throws -> PoolConnection {
        guard !isShutdown else { throw PoolError.poolDestroyed(shutdownError) }

        return try await withCheckedThrowingContinuation({ (continuation: PostgresCheckedContinuation) in
            self.continuations.append(PoolContinuation(batchId: batchId, continuation: continuation))

            Task.detached { [weak self] in
                await self?.handleNextContinuation()
            }
        })
    }

    /// Returns a connection to the pool of open connections.
    private func releaseConnection(_ connection: PoolConnection) async {
        if connection.state == .closed {
            // Shouldn't happen
            if let postgresConnection = connection.connection,
               !postgresConnection.isClosed
            {
                try? await postgresConnection.close()
            }
        }
        else if connection.state == .connecting {
            // Must not happen
            assertionFailure("We shouldn't have connections in this state here")
        }
        else if case .active = connection.state {
            // It can happen that the connection is returned before it's being used
            // (e.g. on cancellation)
            connection.state = .available
            available.append(connection)
        }
        else {
            assert(available.contains(connection), "Connections in state 'available' should be available")
        }

        connection.query = nil
        connection.batchId = nil

        Task.detached { [weak self] in
            await self?.handleNextContinuation()
        }
    }

    /// Aborts all waiting queries with the given `batchId`.
    public func abortBatch(_ batchId: Int) async {
        let countBefore = continuations.count

        continuations.removeAll(where: { poolContinuation in
            guard poolContinuation.batchId == batchId else { return false }

            poolContinuation.continuation.resume(throwing: PoolError.cancelled)
            return true
        })

        let countRemoved = countBefore - continuations.count
        if countRemoved > 0 {
            logger.debug("[\(poolName)] Removed \(countRemoved) continuations for batch \(batchId)")
        }
    }

    /// Releases all resources in the pool and shuts down the event loop.
    /// All further uses of the pool will throw an error.
    ///
    /// Must be done here because
    /// a) Swift doesn't yet allow async deinit,
    /// b) we call this internally on connection errors and need to give the client a chance to react to errors.
    public func shutdown() async {
        guard !isShutdown else { return }

        logger.debug("[\(poolName)] shutdown()")

        isShutdown = true

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

    /// Shutdown due to an unrecoverable error
    private func shutdown(withError error: PSQLError) async {
        guard !isShutdown else { return }

        shutdownError = error

        await shutdown()
    }

    /// Forcibly close all idle connections.
    public func closeIdleConnections() async {
        guard !isShutdown else { return }

        let availableCopy = available
        available.removeAll()

        logger.debug("[\(poolName)] Closing \(availableCopy.count) idle connections")

        for poolConnection in availableCopy {
            await closeConnection(poolConnection)
        }

        connections.removeAll(where: { connection in
            connection.state == .closed
            || (connection.state != .connecting && connection.connection?.isClosed ?? false)
        })
    }

    /// Information about the pool and its open connections.
    public func poolInfo(batchId: Int? = nil) async -> PoolInfo {
        let connections = connections.compactMap { connection -> PoolInfo.ConnectionInfo? in
            if let batchId, connection.batchId != batchId {
                return nil
            }

            return PoolInfo.ConnectionInfo(
                id: connection.id,
                name: nameForConnection(id: connection.id),
                usageCounter: connection.usageCounter,
                batchId: connection.batchId,
                query: connection.query,
                queryRuntime: connection.queryRuntime,
                state: connection.state)
        }

        return PoolInfo(
            name: poolName,
            openConnections: connections.count,
            activeConnections: connections.count - available.count,
            availableConnections: available.count,
            connections: connections,
            isShutdown: isShutdown,
            shutdownError: shutdownError)
    }

    // MARK: - Private

    /// Close the connection, call the delegate.
    private func closeConnection(_ poolConnection: PoolConnection) async {
        poolConnection.state = .closed

        guard let connection = poolConnection.connection else { return }

        if let onCloseConnection {
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

    /// Check open connections, close idle connections.
    private func checkConnections() async {
        defer {
            Task.after(
                seconds: PostgresConnectionPool.healthCheckInterval,
                priority: .low,
                operation: { [weak self] in
                    await self?.checkConnections()
                })
        }

        await checkIdleConnections()

        connections.removeAll(where: { connection in
            connection.state == .closed
                || (connection.state != .connecting && connection.connection?.isClosed ?? false)
        })

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
    /// CLose idle connections.
    private func checkIdleConnections() async {
        guard let maxIdleConnections else { return }

        // 60 seconds
        let inUseWindowSize = Int(PostgresConnectionPool.idleConnectionsCheckInterval / PostgresConnectionPool.healthCheckInterval)
        assert(inUseWindowSize >= 1, "idleConnectionsCheckInterval must be higher than healthCheckInterval")
        if inUseConnectionCounts.count > inUseWindowSize {
            inUseConnectionCounts.removeFirst()
        }
        inUseConnectionCounts.append(connections.count - available.count)

        guard continuations.isEmpty,
              inUseConnectionCounts.count >= inUseWindowSize,
              let maxInUse = inUseConnectionCounts.max()
        else { return }

        let toClose = (available.count - maxIdleConnections) - maxInUse
        guard toClose > 0 else { return }

        logger.debug("[\(poolName)] Closing \(toClose) idle connections")

        for _ in 1 ... toClose {
            guard let poolConnection = available.popFirst() else { break }

            await closeConnection(poolConnection)
        }
    }

    /// Take the next waiting connection request from the queue.
    private func handleNextContinuation() async {
        guard continuations.isNotEmpty else {
            logger.debug("[\(poolName)] No more continuations left, \(connections.count) connections, \(available.count) available")
            return
        }

        logger.debug("[\(poolName)] Next continuation: \(continuations.count) left")

        // Next connection from `available`
        // Make sure that the connection is usable
        // TODO: Needs some code cleanup
        var poolConnection: PoolConnection?

        // 1. See if we have a readily available connection
        while let next = available.popFirst() {
            guard next.state == .available else {
                // ? -> Force close
                assertionFailure("Connections in available should be available")
                next.state = .closed
                try? await next.connection?.close()
                continue
            }

            poolConnection = next
            break
        }

        // 2. No available connection
        //    a) Can we open a new connection: do it and exit
        //    b) Can't open a new connection: exit, another connection will pick up the continuation
        guard let poolConnection else {
            if connections.count < poolSize {
                Task.detached { [weak self] in
                    await self?.openConnection()
                }
            }
            return
        }

        // 3. Check that the Postgres connection is usable, or try to open a new one
        //    (see 2.)
        guard let connection = poolConnection.connection else {
            poolConnection.state = .closed

            if connections.count < poolSize {
                Task.detached { [weak self] in
                    await self?.openConnection()
                }
            }
            return
        }

        // 4. Get the next waiting continuation from the queue and run it
        guard let poolContinuation = continuations.popFirst() else {
            available.append(poolConnection)
            return
        }

        poolConnection.state = .active(Date())
        poolConnection.batchId = poolContinuation.batchId

        do {
            // Connection check, etc.
            if let onReturnConnection {
                try await onReturnConnection(connection, logger)
            }

            return poolContinuation.continuation.resume(returning: poolConnection)
        }
        catch {
            logger.warning("[\(poolName)] Health check for connection \(poolConnection.id) failed")

            await closeConnection(poolConnection)
        }
    }

    /// Display name for a connection
    private func nameForConnection(id: Int) -> String {
        "\(connectionName) - CONN:\(id)"
    }

    /// Open a new connection to the Postgres server
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

                if let onOpenConnection {
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
            poolConnection.state = .closed

            let logMessage: Logger.Message = "[\(poolName)] Connection \(poolConnection.id) failed after \(connectionRuntime.rounded(toPlaces: 2))s: \(error)"

            // Don't just open a new connection, check first if this is a permanent error like wrong password etc.

            // TODO: Check which of these errors is actually fatal
            if let psqlError = error as? PSQLError {
                switch psqlError.code {
                case .authMechanismRequiresPassword,
                     .clientClosedConnection,
                     .failedToAddSSLHandler,
                     .invalidCommandTag,
                     .messageDecodingFailure,
                     .receivedUnencryptedDataAfterSSLRequest,
                     .saslError,
                     .serverClosedConnection,
                     .sslUnsupported,
                     .unexpectedBackendMessage,
                     .unsupportedAuthMechanism:
                    logger.error(logMessage)
                    await shutdown(withError: psqlError)
                    return

                case .queryCancelled,
                     .tooManyParameters,
                     .uncleanShutdown:
                    break

                case .connectionError:
                    let delay = UInt64(connectionRetryInterval * 1_000_000_000)
                    try? await Task<Never, Never>.sleep(nanoseconds: delay)

                default:
                    break
                }

                if let serverInfo = psqlError.serverInfo,
                   let code = serverInfo[.sqlState]
                {
                    // TODO: Check which of these errors is actually fatal
                    switch PostgresError.Code(raw: code) {
                    case .adminShutdown,
                         .invalidAuthorizationSpecification,
                         .invalidName,
                         .invalidPassword:
                        logger.error(logMessage)
                        await shutdown(withError: psqlError)
                        return

                    case .cannotConnectNow:
                        let delay = UInt64(connectionRetryInterval * 1_000_000_000)
                        try? await Task<Never, Never>.sleep(nanoseconds: delay)

                    default:
                        break
                    }
                }
            }

            logger.warning(logMessage)

            Task.detached { [weak self] in
                await self?.openConnection()
            }
        }
    }

}
