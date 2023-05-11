//
//  Created by Thomas Rasch on 25.08.22.
//

import Foundation

// MARK: Regexp

extension String {

    /// A Boolean value indicating whether the string matches a regular expression.
    func matches(
        _ regexp: String,
        caseInsensitive: Bool = false)
        -> Bool
    {
        var options: String.CompareOptions = .regularExpression
        if caseInsensitive { options.insert(.caseInsensitive) }

        return self.range(of: regexp, options: options) != nil
    }

    /// Returns a new string with the matches of the regular expression replaced with some other string.
    func replacingPattern(
        _ regexp: String,
        with replacement: String,
        caseInsensitive: Bool = false,
        treatAsOneLine: Bool = false)
        -> String
    {
        var options = NSRegularExpression.Options()

        if caseInsensitive { options.insert(.caseInsensitive) }
        if treatAsOneLine { options.insert(.dotMatchesLineSeparators) }

        guard let pattern = try? NSRegularExpression(pattern: regexp, options: options) else {
            return self
        }

        return pattern.stringByReplacingMatches(
            in: self,
            options: NSRegularExpression.MatchingOptions(),
            range: NSRange(location: 0, length: self.count),
            withTemplate: replacement)
    }

}
