//
//  Created by Thomas Rasch on 05.05.23.
//

import PostgresNIO

extension PSQLError: CustomStringConvertible {

    public var description: String {
        if let serverInfo = self.serverInfo,
           let severity = serverInfo[.severity],
           let message = serverInfo[.message]
        {
            return "\(severity): \(message)"
        }

        return "Database error: \(self.code.description)"
    }

}
