//
//  Created by Thomas Rasch on 23.03.22.
//

import Atomics
import Collections
import Foundation
import PostgresNIO

/// A pool of reusable connections to a PostgreSQL database.
///
/// The pool manages a configurable number of connections, handles health checks,
/// idle connection culling, cancellation-aware waiting, and automatic reconnection
/// on transient errors. All mutable state is isolated to this actor.
///
/// Call ``connection(batchId:_:)`` to acquire a connection, and ``shutdown()``
/// when the pool is no longer needed.
public actor PostgresConnectionPool {

    private static let postgresMaxNameLength = 32 // PostgreSQL allows 64 but we add some extra info

    private let eventLoopGroup: EventLoopGroup

    /// The logger used by this pool and its connections.
    nonisolated public let logger: Logger

    /// The underlying `PostgresConnection.Configuration` used when opening new connections.
    nonisolated public let postgresConfiguration: PostgresConnection.Configuration

    /// A sanitized application name sent to PostgreSQL (max 32 characters).
    nonisolated public let connectionName: String

    /// A human-readable description of the connection target (e.g. `user@host:port/database`).
    nonisolated public let poolName: String

    /// The maximum number of open connections the pool will maintain.
    nonisolated public let poolSize: Int

    /// The time to wait before retrying a failed connection attempt.
    nonisolated public let connectionRetryInterval: TimeInterval

    /// The maximum number of idle connections, or `nil` for unlimited.
    nonisolated public let maxIdleConnections: Int?

    /// The timeout for individual queries, or `nil` for no timeout.
    nonisolated public let queryTimeout: TimeInterval?

    /// How often the pool checks idle connections and pending requests.
    nonisolated public let maintenanceInterval: TimeInterval

    /// The rolling window used to decide how many idle connections to keep.
    nonisolated public let idleConnectionsCheckInterval: TimeInterval

    private let onOpenConnection: ((PostgresConnection, Logger) async throws -> Void)?
    private let onReturnConnection: ((PostgresConnection, Logger) async throws -> Void)?
    private let onCloseConnection: ((PostgresConnection, Logger) async throws -> Void)?

    private var connections: [PoolConnection] = []
    private var available: Deque<PoolConnection> = []
    private var continuations: Deque<PoolContinuation> = []
    private var inUseConnectionCounts: Deque<Int> = []

    private var maintenanceTask: Task<Void, Never>?
    private var nextConnectionAttempt = Date.distantPast

    public private(set) var isShutdown = false
    public private(set) var shutdownError: PSQLError?

    private let didShutdown = ManagedAtomic<Bool>(false)

    // MARK: -

    /// Creates a connection pool from the given configuration.
    ///
    /// - Parameters:
    ///   - configuration: The pool configuration including connection parameters and limits.
    ///   - logger: An optional logger. If `nil`, a default logger is created using the configuration's
    ///     ``PoolConfiguration/applicationName``.
    ///   - maintenanceInterval: How often idle connections and pending requests are checked (default: 5 seconds).
    ///   - idleConnectionsCheckInterval: The rolling window used for idle connection culling (default: 60 seconds).
    ///   - eventLoopGroup: The event loop group used for connections. Defaults to
    ///     `PostgresConnection.defaultEventLoopGroup`. The pool does not own the group and never
    ///     shuts it down; pass a dedicated group if the pool must be isolated from other clients.
    ///
    /// Call ``shutdown()`` when the pool is no longer needed.
    public init(
        configuration: PoolConfiguration,
        logger: Logger? = nil,
        maintenanceInterval: TimeInterval = 5.0,
        idleConnectionsCheckInterval: TimeInterval = 60.0,
        eventLoopGroup: (any EventLoopGroup)? = nil,
    ) {
        self.logger = logger ?? {
            var logger = Logger(label: configuration.applicationName)
            logger.logLevel = .info
            return logger
        }()
        self.eventLoopGroup = eventLoopGroup ?? PostgresConnection.defaultEventLoopGroup

        self.connectionName = String(configuration.applicationName.replacingPattern("[^-\\w\\d\\s()]", with: "").prefix(PostgresConnectionPool.postgresMaxNameLength))
        self.poolSize = configuration.poolSize
        self.connectionRetryInterval = configuration.connectionRetryInterval
        self.maxIdleConnections = configuration.maxIdleConnections
        self.queryTimeout = configuration.queryTimeout

        let maintenanceInterval = maintenanceInterval.atLeast(0.01)
        self.maintenanceInterval = maintenanceInterval
        self.idleConnectionsCheckInterval = idleConnectionsCheckInterval.atLeast(maintenanceInterval)

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

    deinit {
        assert(didShutdown.load(ordering: .acquiring), "Must call shutdown() before releasing a PostgresConnectionPool")
    }

    /// Takes one connection from the pool and dishes it out to the caller.
    ///
    /// - Parameters:
    ///   - batchId: An optional integer value associated with the connection. See also ``abortBatch(_:)``.
    ///   - callback: A closure with a connection to the database server.
    @discardableResult
    public func connection<T>(
        batchId: Int? = nil,
        _ callback: @Sendable (PostgresConnectionWrapper) async throws -> T,
    ) async throws -> T {
        let poolConnection: PoolConnection

        do {
            poolConnection = try await getConnection(batchId: batchId)
        }
        catch {
            logger.debug("[\(poolName)] Connection error: \(String(reflecting: error))")
            throw error
        }

        if Task.isCancelled {
            await releaseConnection(poolConnection)

            if let batchId {
                await abortBatch(batchId)
            }

            throw PoolError.cancelled
        }

        do {
            let result = try await PostgresConnectionWrapper.distribute(
                poolConnection: poolConnection,
                callback: callback)

            await releaseConnection(poolConnection)

            return result
        }
        catch {
            await releaseConnection(poolConnection)

            logger.debug("[\(poolName)] Connection or query error: \(String(reflecting: error))")

            throw error
        }
    }

    /// Adds a connection placeholder to the list of waiting connections.
    private func getConnection(
        batchId: Int? = nil,
    ) async throws -> PoolConnection {
        guard isShutdown == false else { throw PoolError.poolDestroyed(shutdownError) }
        guard Date() >= nextConnectionAttempt || available.isNotEmpty else {
            throw PoolError.connectionFailed
        }

        let poolContinuationID = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation({ (continuation: PostgresCheckedContinuation) in
                let poolContinuation = PoolContinuation(
                    id: poolContinuationID,
                    batchId: batchId,
                    continuation: continuation)

                if Task.isCancelled || poolContinuation.cancellation.isCancelled {
                    continuation.resume(throwing: PoolError.cancelled)
                    return
                }

                self.continuations.append(poolContinuation)

                // Close the race between enqueueing and the cancellation handler
                // running before the continuation was visible to the actor.
                if poolContinuation.cancellation.isCancelled {
                    self.continuations.removeAll(where: { $0.id == poolContinuation.id })
                    continuation.resume(throwing: PoolError.cancelled)
                    return
                }

                Task { [weak self] in
                    await self?.handleNextContinuation()
                }
            })
        }
        onCancel: {
            Task { [weak self] in
                await self?.cancelContinuation(id: poolContinuationID)
            }
        }
    }

    /// Removes a waiting continuation after its task was cancelled.
    private func cancelContinuation(id: UUID) async {
        guard let index = continuations.firstIndex(where: { $0.id == id }) else { return }

        let poolContinuation = continuations.remove(at: index)
        poolContinuation.cancellation.cancel()
        poolContinuation.continuation.resume(throwing: PoolError.cancelled)

        logger.debug("[\(poolName)] Cancelled waiting connection request \(id)")
    }

    /// Returns a connection to the pool of open connections.
    private func releaseConnection(_ connection: PoolConnection) async {
        if connection.state == .closed {
            // Shouldn't happen
            if let postgresConnection = connection.connection,
               postgresConnection.isClosed == false
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

            if isShutdown {
                await closeConnection(connection)
            }
            else {
                available.append(connection)
            }
        }
        else {
            assert(available.contains(connection), "Connections in state 'available' should be available")
        }

        connection.query = nil
        connection.batchId = nil

        Task { [weak self] in
            await self?.handleNextContinuation()
        }
    }

    /// Aborts all connection requests waiting for the given `batchId`.
    ///
    /// Active queries are not cancelled; cancel the owning task for that.
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

    /// Shuts down the pool, cancelling pending requests and closing all connections.
    ///
    /// All subsequent uses of the pool will throw ``PoolError/poolDestroyed(_:)``.
    /// This method must be called before the pool is released.
    public func shutdown() async {
        await shutdown(resumingWaitingRequestsWith: .cancelled)
    }

    /// Shutdown due to an unrecoverable error.
    private func shutdown(withError error: PSQLError) async {
        guard isShutdown == false else { return }

        shutdownError = error

        await shutdown(resumingWaitingRequestsWith: .poolDestroyed(error))
    }

    /// Shared shutdown implementation.
    private func shutdown(resumingWaitingRequestsWith error: PoolError) async {
        guard isShutdown == false else { return }

        logger.debug("[\(poolName)] shutdown()")

        isShutdown = true
        didShutdown.store(true, ordering: .releasing)

        maintenanceTask?.cancel()
        maintenanceTask = nil

        // Cancel all waiting continuations. Requests waiting when a fatal
        // connection error occurs receive `poolDestroyed` so callers can
        // distinguish a dead pool from an ordinary cancellation.
        for poolContinuation in continuations {
            poolContinuation.continuation.resume(throwing: error)
        }
        continuations.removeAll()

        available.removeAll()

        // Close all open connections
        connections.forEach({ $0.state = .closed })
        for poolConnection in connections {
            await closeConnection(poolConnection)
        }
        connections.removeAll()
    }

    /// Closes all currently idle (available) connections.
    ///
    /// Connections that are in use are not affected. Use this to reduce resource
    /// consumption during low-activity periods.
    public func closeIdleConnections() async {
        guard isShutdown == false else { return }

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

    /// Returns diagnostic information about the pool and its connections.
    ///
    /// - Parameter batchId: Optional batch ID filter — only connections and waiting
    ///   requests with this batch ID are counted.
    /// - Returns: A ``PoolInfo`` struct with connection counts and details.
    public func poolInfo(batchId: Int? = nil) async -> PoolInfo {
        let infos = connections.compactMap { connection -> PoolInfo.ConnectionInfo? in
            if let batchId, connection.batchId != batchId {
                return nil
            }
            guard connection.state != .closed else { return nil }

            return PoolInfo.ConnectionInfo(
                id: connection.id,
                name: nameForConnection(id: connection.id),
                usageCounter: connection.usageCounter.load(ordering: .relaxed),
                batchId: connection.batchId,
                query: connection.query,
                queryRuntime: connection.queryRuntime,
                state: connection.state)
        }

        let activeConnections = infos.reduce(into: 0) { count, info in
            if case .active = info.state {
                count += 1
            }
        }
        let availableConnections = infos.reduce(into: 0) { count, info in
            if info.state == .available {
                count += 1
            }
        }
        let waitingRequests = continuations.reduce(into: 0) { count, continuation in
            if batchId == nil || continuation.batchId == batchId {
                count += 1
            }
        }

        return PoolInfo(
            name: poolName,
            openConnections: infos.count,
            activeConnections: activeConnections,
            availableConnections: availableConnections,
            waitingRequests: waitingRequests,
            connections: infos,
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
                logger.warning("[\(poolName)] onCloseConnection error: \(String(reflecting: error))")
            }
        }

        do {
            try await connection.close()
        }
        catch {
            logger.warning("[\(poolName)] connection.close() error: \(String(reflecting: error))")
        }
    }

    /// Starts the periodic maintenance task if it is not running yet.
    private func startMaintenanceTaskIfNeeded() {
        guard maintenanceTask == nil, isShutdown == false else { return }

        let interval = maintenanceInterval
        maintenanceTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(interval))

                guard Task.isCancelled == false, let self else { return }

                let keepRunning = await checkConnectionsOnce()
                if keepRunning == false {
                    return
                }
            }
        }
    }

    /// Check open connections, close idle connections.
    private func checkConnectionsOnce() async -> Bool {
        guard isShutdown == false else { return false }

        await checkIdleConnections()

        connections.removeAll(where: { connection in
            connection.state == .closed
                || (connection.state != .connecting && connection.connection?.isClosed ?? false)
        })

        let usageCounter = connections.reduce(0) { $0 + $1.usageCounter.load(ordering: .relaxed) }
        logger.debug("[\(poolName)] \(connections.count) connections (\(available.count) available, \(usageCounter) queries), \(continuations.count) continuations left")

        // Check for waiting continuations and open connections while capacity
        // and demand remain. A single maintenance tick can fill the pool.
        while isShutdown == false,
              connections.count < poolSize,
              continuations.isNotEmpty
        {
            let countBefore = connections.count
            await openConnection()

            // No progress means the attempt failed and a retry is scheduled.
            if connections.count == countBefore {
                break
            }
        }

        return true
    }

    // TODO: This doesn't work well with short bursts of activity that fall between the 5 seconds check interval
    /// Close idle connections.
    private func checkIdleConnections() async {
        guard let maxIdleConnections else { return }

        // 60 seconds
        let inUseWindowSize = Int(idleConnectionsCheckInterval / maintenanceInterval)
        assert(inUseWindowSize >= 1, "idleConnectionsCheckInterval must be higher than healthCheckInterval")
        if inUseConnectionCounts.count > inUseWindowSize {
            inUseConnectionCounts.removeFirst()
        }

        let activeConnections = connections.reduce(into: 0) { count, connection in
            if case .active = connection.state {
                count += 1
            }
        }
        inUseConnectionCounts.append(activeConnections)

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
                Task { [weak self] in
                    await self?.openConnection()
                }
            }
            return
        }

        // 3. Check that the Postgres connection is usable, or try to open a new one
        //    (see 2.)
        guard let connection = poolConnection.connection else {
            poolConnection.state = .closed
            connections.removeAll(where: { $0 === poolConnection })

            if connections.count < poolSize {
                Task { [weak self] in
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

            poolContinuation.continuation.resume(returning: poolConnection)
        }
        catch {
            logger.warning("[\(poolName)] Health check for connection \(poolConnection.id) failed: \(String(reflecting: error))")

            await closeConnection(poolConnection)
            connections.removeAll(where: { $0 === poolConnection })

            // One bad idle connection should not fail the caller if a fresh
            // connection can serve the request. The attempt counter lives on
            // the continuation so it survives opening a replacement.
            poolContinuation.healthCheckAttempt += 1
            if poolContinuation.healthCheckAttempt <= 1 {
                continuations.prepend(poolContinuation)

                if available.isNotEmpty {
                    await handleNextContinuation()
                }
                else if connections.count < poolSize {
                    Task { [weak self] in
                        await self?.openConnection()
                    }
                }
                else {
                    poolContinuation.continuation.resume(throwing: PoolError.connectionFailed)
                }
            }
            else {
                poolContinuation.continuation.resume(throwing: PoolError.connectionFailed)
            }
        }
    }

    /// Display name for a connection
    private func nameForConnection(id: Int) -> String {
        "\(connectionName) - CONN:\(id)"
    }

    /// Open a new connection to the Postgres server
    private func openConnection() async {
        guard isShutdown == false else { return }

        startMaintenanceTaskIfNeeded()

        guard continuations.isNotEmpty else { return }

        if available.isNotEmpty {
            await handleNextContinuation()
            return
        }

        guard Date() >= nextConnectionAttempt else {
            failWaitingRequests(with: .connectionFailed)
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
            let connectionRuntime = abs(connectionStartTimestamp.timeIntervalSinceNow)
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
                try? await connection.close()

                logger.warning("[\(poolName)] Connection \(poolConnection.id) setup failed: \(String(reflecting: error))")
                await handleTransientConnectionFailure()

                return
            }

            guard isShutdown == false else {
                poolConnection.state = .closed
                try? await connection.close()
                logger.debug("[\(poolName)] Discarding connection \(poolConnection.id) opened during shutdown")
                return
            }

            poolConnection.connection = connection
            poolConnection.state = .available
            nextConnectionAttempt = .distantPast
            available.append(poolConnection)

            await handleNextContinuation()
        }
        catch {
            let connectionRuntime = abs(connectionStartTimestamp.timeIntervalSinceNow)
            poolConnection.state = .closed
            connections.removeAll(where: { $0 === poolConnection })

            let logMessage: Logger.Message = "[\(poolName)] Connection \(poolConnection.id) failed after \(connectionRuntime.rounded(toPlaces: 2))s: \(String(reflecting: error))"

            // Don't retry permanent errors such as wrong credentials or an
            // unsupported TLS setup forever; shut the pool down so callers can
            // replace it.
            if let psqlError = error as? PSQLError,
               Self.isPermanentConnectionError(psqlError)
            {
                logger.error(logMessage)
                await shutdown(withError: psqlError)
                return
            }

            logger.warning(logMessage)
            await handleTransientConnectionFailure()
        }
    }

    /// Whether a connection error is permanent for this configuration.
    ///
    /// Network failures, server restarts and connection resets are transient:
    /// they fail the current request, leave the pool alive and apply a short
    /// cooldown before the next attempt. Authentication, TLS and protocol
    /// configuration errors cannot recover without operator action.
    private static func isPermanentConnectionError(_ error: PSQLError) -> Bool {
        if let underlying = error.underlying {
            let description = String(reflecting: underlying).lowercased()
            if description.contains("ssl") || description.contains("tls") || description.contains("handshake") {
                return true
            }
        }

        switch error.code {
        case .authMechanismRequiresPassword,
             .failedToAddSSLHandler,
             .invalidCommandTag,
             .messageDecodingFailure,
             .receivedUnencryptedDataAfterSSLRequest,
             .saslError,
             .sslUnsupported,
             .tooManyParameters,
             .unexpectedBackendMessage,
             .unsupportedAuthMechanism:
            return true

        default:
            break
        }

        if let serverInfo = error.serverInfo,
           let code = serverInfo[.sqlState]
        {
            switch PostgresError.Code(raw: code) {
            case .insufficientPrivilege,
                 .invalidAuthorizationSpecification,
                 .invalidCatalogName,
                 .invalidName,
                 .invalidPassword:
                return true

            default:
                break
            }
        }

        return false
    }

    /// Fails waiting requests and prevents a retry storm after a transient
    /// connection failure. A later request will try again after the cooldown.
    private func handleTransientConnectionFailure() async {
        nextConnectionAttempt = Date(timeIntervalSinceNow: connectionRetryInterval)

        if available.isNotEmpty {
            await handleNextContinuation()
        }
        else {
            failWaitingRequests(with: .connectionFailed)
        }
    }

    /// Resumes all queued requests with the given error.
    private func failWaitingRequests(with error: PoolError) {
        let waiting = continuations
        continuations.removeAll()

        for poolContinuation in waiting {
            if poolContinuation.cancellation.isCancelled {
                poolContinuation.continuation.resume(throwing: PoolError.cancelled)
            }
            else {
                poolContinuation.continuation.resume(throwing: error)
            }
        }
    }

}
