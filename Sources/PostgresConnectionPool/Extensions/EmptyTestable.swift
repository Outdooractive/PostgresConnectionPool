//
//  Created by Thomas Rasch on 25.08.22.
//

import DequeModule
import Foundation

// MARK: EmptyTestable

protocol EmptyTestable {

    var isEmpty: Bool { get }

    /// A Boolean value indicating whether the collection is **not** empty.
    var isNotEmpty: Bool { get }

}

extension EmptyTestable {

    var isNotEmpty: Bool {
        !isEmpty
    }

}

extension Array: EmptyTestable {}
extension Deque: EmptyTestable {}
extension Dictionary: EmptyTestable {}
extension Set: EmptyTestable {}
extension String: EmptyTestable {}
