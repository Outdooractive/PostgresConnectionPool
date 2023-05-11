//
//  Created by Thomas Rasch on 02.02.18.
//  Copyright © 2018 Outdooractive AG. All rights reserved.
//

import Foundation

extension FloatingPoint {

    /// Returns rounded FloatingPoint to specified number of places.
    func rounded(toPlaces places: Int) -> Self {
        guard places >= 0 else { return self }
        var divisor: Self = 1
        for _ in 0..<places { divisor *= 10 }
        return (self * divisor).rounded() / divisor
    }

    /// Rounds current FloatingPoint to specified number of places.
    mutating func round(toPlaces places: Int) {
        self = rounded(toPlaces: places)
    }

}
