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

    /// Twenty digits used to read as 1e20, and showing it as a whole number trapped on the next keystroke.
    func testARunOfDigitsTooLongForAFigureIsNotOne() {
        let locale = Locale(identifier: "en_US")
        XCTAssertNil(NumberField.parse("99999999999999999999", locale: locale))
        XCTAssertNil(NumberField.parse(String(repeating: "9", count: 400), locale: locale))
        XCTAssertEqual(NumberField.parse("999,999,999", locale: locale), 999_999_999)
        XCTAssertNil(ServiceImport.number("12345678901234567890"))
        XCTAssertNil(ServiceImport.number(String(repeating: "9", count: 400)))
        XCTAssertEqual(ServiceImport.number("248,210"), 248_210)
    }

    /// A barcode tapped in the scanner used to fill in 1e19 and trap the field showing it.
    func testAScannedRunOfDigitsTooLongForAFigureFillsNothing() {
        XCTAssertNil(FieldReader.tapped("12345678901234567890", for: .reading(last: 0, meter: .miles)))
        XCTAssertNil(FieldReader.tapped("$12345678901234567890", for: .amount))
        XCTAssertEqual(FieldReader.tapped("48210", for: .reading(last: 0, meter: .miles)), "48210")
        XCTAssertEqual(FieldReader.tapped("$412.37", for: .amount), "412.37")
    }
}
