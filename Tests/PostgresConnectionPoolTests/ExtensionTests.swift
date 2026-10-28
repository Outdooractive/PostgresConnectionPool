//
//  Created by Thomas Rasch on 07.07.26.
//

import Collections
import Foundation
@testable import PostgresConnectionPool
import Testing

@Suite("Extensions")
struct ExtensionTests {

    // MARK: - isNotEmpty

    @Test
    func arrayIsNotEmpty() {
        #expect([1].isNotEmpty)
        #expect([Int]().isNotEmpty == false)
    }

    @Test
    func dequeIsNotEmpty() {
        var deque = Deque<Int>()
        #expect(deque.isNotEmpty == false)
        deque.append(1)
        #expect(deque.isNotEmpty)
    }

    @Test
    func dictionaryIsNotEmpty() {
        #expect(["a": 1].isNotEmpty)
        #expect([:].isNotEmpty == false)
    }

    @Test
    func setIsNotEmpty() {
        #expect(Set([1]).isNotEmpty)
        #expect(Set<Int>().isNotEmpty == false)
    }

    @Test
    func stringIsNotEmpty() {
        #expect("a".isNotEmpty)
        #expect("".isNotEmpty == false)
    }

    // MARK: - atLeast (Double)

    @Test
    func doubleAtLeastClampsBelowMinimum() {
        #expect(0.5.atLeast(1.0) == 1.0)
    }

    @Test
    func doubleAtLeastPassesThroughAboveMinimum() {
        #expect(2.0.atLeast(1.0) == 2.0)
    }

    @Test
    func doubleAtLeastEquality() {
        #expect(1.0.atLeast(1.0) == 1.0)
    }

    // MARK: - atLeast (Int)

    @Test
    func intAtLeastClampsBelowMinimum() {
        #expect(0.atLeast(1) == 1)
    }

    @Test
    func intAtLeastPassesThroughAboveMinimum() {
        #expect(5.atLeast(1) == 5)
    }

    @Test
    func intAtLeastEquality() {
        #expect(1.atLeast(1) == 1)
    }

    @Test
    func intAtLeastNegativeValues() {
        #expect((-5).atLeast(-10) == -5)
        #expect((-15).atLeast(-10) == -10)
    }

    // MARK: - FloatingPoint rounded(toPlaces:)

    @Test
    func doubleRoundedToPlaces() {
        #expect(1.23456.rounded(toPlaces: 2) == 1.23)
        #expect(1.23556.rounded(toPlaces: 2) == 1.24)
    }

    @Test
    func doubleRoundedToZeroPlaces() {
        #expect(1.5.rounded(toPlaces: 0) == 2.0)
    }

    @Test
    func doubleRoundedToManyPlaces() {
        #expect(1.1.rounded(toPlaces: 10) == 1.1)
    }

    @Test
    func doubleRoundMutating() {
        var value = 1.23456
        value.round(toPlaces: 2)
        #expect(value == 1.23)
    }

    // MARK: - String.matches()

    @Test
    func stringMatchesSimplePattern() {
        #expect("hello world".matches("hello"))
    }

    @Test
    func stringMatchesRegexPattern() {
        #expect("abc123".matches("[a-z]+\\d+"))
    }

    @Test
    func stringNoMatchReturnsFalse() {
        #expect("abc".matches("\\d+") == false)
    }

    @Test
    func stringMatchesCaseInsensitive() {
        #expect("Hello".matches("hello", caseInsensitive: true))
        #expect("Hello".matches("hello") == false)
    }

    // MARK: - String.replacingPattern()

    @Test
    func stringReplacingPatternBasic() {
        let result = "hello 123 world".replacingPattern("\\d+", with: "NUM")
        #expect(result == "hello NUM world")
    }

    @Test
    func stringReplacingPatternNoMatch() {
        let result = "hello".replacingPattern("\\d+", with: "NUM")
        #expect(result == "hello")
    }

    @Test
    func stringReplacingPatternCaseInsensitive() {
        let result = "Hello World".replacingPattern("hello", with: "Hi", caseInsensitive: true)
        #expect(result == "Hi World")
    }

    @Test
    func stringReplacingPatternInvalidRegexReturnsSelf() {
        let result = "hello".replacingPattern("[invalid", with: "")
        #expect(result == "hello")
    }

    @Test
    func stringReplacingPatternTreatAsOneLine() {
        #expect("a\nb".replacingPattern("a.b", with: "X", treatAsOneLine: true) == "X")
        #expect("a\nb".replacingPattern("a.b", with: "X") == "a\nb")
    }

    @Test
    func stringReplacingPatternHandlesNonBmpCharacters() {
        #expect("a👍🏽b".replacingPattern("👍🏽", with: "X") == "aXb")
        #expect("a👍🏽b".replacingPattern("b", with: "Y") == "a👍🏽Y")
        #expect("e\u{301}clair".replacingPattern("e\u{301}", with: "E") == "Eclair")
    }

}
