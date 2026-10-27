//
//  Created by Thomas Rasch on 05.05.23.
//

import OrderedCollections
import PostgresNIO

// MARK: CustomStringConvertible

extension PSQLError {

    /// A short error description.
    public var pgPoolDescription: String {
        if let serverInfo,
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

        if let underlying {
            return "<PSQLError: \(code.description) (\(underlying))>"
        }
        else {
            return "<PSQLError: \(code.description)>"
        }
    }

}

// MARK: - CustomDebugStringConvertible

extension PSQLError {

    /// A detailed error description suitable for debugging queries and other problems with the server.
    public var pgPoolDebugDescription: String {
        var messageElements = [
            "code: \(code)",
        ]

        if let serverInfo {
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

            let serverInfoElements = fields.compactMap({ fieldAndName -> String? in
                guard let value = serverInfo[fieldAndName.0] else { return nil }

                return "\(fieldAndName.1): \(value)"
            })

            messageElements.append("serverInfo: [\(serverInfoElements.joined(separator: ", "))]")
        }

        if let underlying {
            messageElements.append("underlying: \(String(reflecting: underlying))")
        }

        if let file {
            messageElements.append("triggeredFromRequestInFile: \(file)\(line.flatMap({ "#\($0)" }) ?? "")")
        }

        if let query {
            messageElements.append("query: \(query)")
        }

        return "<PSQLError: \(messageElements.joined(separator: ", "))>"
    }

}
