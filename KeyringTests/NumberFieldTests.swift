import XCTest
@testable import Keyring

/// A figure the locale formatted has to read back as the same figure, or the field clears itself when it shows it.
@MainActor
final class NumberFieldTests: XCTestCase {
    func testNativeDigitsAndTheirMarksReadLikeLatinOnes() {
        let arabic = Locale(identifier: "ar_SA@numbers=arab")
        XCTAssertEqual(NumberField.parse("٤٨٬٢١٠", locale: arabic), 48_210)
        XCTAssertEqual(NumberField.parse("١٢٫٥", locale: arabic), 12.5)
        let persian = Locale(identifier: "fa_IR")
        XCTAssertEqual(NumberField.parse("۴۸۲۱۰", locale: persian), 48_210)
    }

    func testLatinDigitsStillReadByTheLocalesMarks() {
        XCTAssertEqual(NumberField.parse("48,210", locale: Locale(identifier: "en_US")), 48_210)
        XCTAssertEqual(NumberField.parse("12.5", locale: Locale(identifier: "en_US")), 12.5)
        XCTAssertEqual(NumberField.parse("1.234,5", locale: Locale(identifier: "de_DE")), 1_234.5)
        XCTAssertEqual(NumberField.parse("59,99", locale: Locale(identifier: "de_DE")), 59.99)
        XCTAssertNil(NumberField.parse("", locale: Locale(identifier: "en_US")))
        XCTAssertNil(NumberField.parse("abc", locale: Locale(identifier: "en_US")))
    }

    func testAFormattedFigureReadsBackInItsOwnLocale() {
        for identifier in ["en_US", "de_DE", "fr_FR", "ar_SA@numbers=arab", "fa_IR", "hi_IN@numbers=deva", "bn_BD", "my_MM"] {
            let locale = Locale(identifier: identifier)
            let shown = Int(48_210).formatted(.number.locale(locale))
            XCTAssertEqual(NumberField.parse(shown, locale: locale), 48_210, "\(shown) in \(identifier)")
        }
    }
}
