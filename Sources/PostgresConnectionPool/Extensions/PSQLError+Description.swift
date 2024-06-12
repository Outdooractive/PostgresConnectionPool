//
//  Created by Thomas Rasch on 05.05.23.
//

import OrderedCollections
import PostgresNIO

// MARK: CustomStringConvertible

extension PSQLError {

    /// A short error description.
    public var pgPoolDescription: String {
        if let serverInfo = self.serverInfo,
           let severity = serverInfo[.severity],
           let message = serverInfo[.message]
        {
            if let code = serverInfo[.sqlState] {
                return "<PSQLError (code \(code)): \(severity): \(message)>"
            }
            else {
                return "<PSQLError: \(severity): \(message)>"
            }
        }

        return "<PSQLError: \(self.code.description)>"
    }

}

// MARK: - CustomDebugStringConvertible

extension PSQLError {

    /// A detailed error description suitable for debugging queries and other problems with the server.
    public var pgPoolDebugDescription: String {
        var messageElements: [String] = [
            "code: \(self.code)"
        ]

        if let serverInfo = self.serverInfo {
            // Field -> display name
            let fields: OrderedDictionary<PSQLError.ServerInfo.Field, String> = [
                .severity: "severity",
                .message: "message",
                .hint: "hint",
                .detail: "detail",
                .schemaName: "schemaName",
                .tableName: "tableName",
                .columnName: "columnName",
                .dataTypeName: "dataTypeName",
                .constraintName: "constraintName",
                .internalQuery: "internalQuery",
                .position: "position",
                .locationContext: "locationContext",
                .sqlState: "sqlState",
            ]

            let serverInfoELements = fields.compactMap({ fieldAndName -> String? in
                guard let value = serverInfo[fieldAndName.0] else { return nil }
                return "\(fieldAndName.1): \(value)"
            })

            messageElements.append("serverInfo: [\(serverInfoELements.joined(separator: ", "))]")
        }

        // Not accessible
//        if let backendMessage = self.backendMessage {
//            messageElements.append("backendMessage: \(backendMessage)")
//        }
//
//        if let unsupportedAuthScheme = self.unsupportedAuthScheme {
//            messageElements.append("unsupportedAuthScheme: \(unsupportedAuthScheme)")
//        }
//
//        if let invalidCommandTag = self.invalidCommandTag {
//            messageElements.append("invalidCommandTag: \(invalidCommandTag)")
//        }

        if let underlying = self.underlying {
            messageElements.append("underlying: \(String(reflecting: underlying))")
        }

        if let file = self.file {
            messageElements.append("triggeredFromRequestInFile: \(file)\(self.line.flatMap({ "#\($0)" }) ?? "" )")
        }

        if let query = self.query {
            messageElements.append("query: \(query)")
        }
        return "<PSQLError: \(messageElements.joined(separator: ", "))>"
    }

}
