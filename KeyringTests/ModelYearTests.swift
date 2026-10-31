import XCTest
@testable import Keyring

/// A model year is a Gregorian year. The calendar a phone shows follows its region, and Saudi Arabia's
/// (Islamic, year 1448) once made the check for a valid year build the range 1900...1449 and crash.
@MainActor
final class ModelYearTests: XCTestCase {
    func testTheLatestModelYearIsNextYearInTheGregorianCalendar() {
        let september2026 = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(VehicleDetailsForm.latestModelYear(now: september2026), 2027)
        let december2026 = Date(timeIntervalSince1970: 1_798_000_000)
        XCTAssertEqual(VehicleDetailsForm.latestModelYear(now: december2026), 2027)
        let january2027 = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(VehicleDetailsForm.latestModelYear(now: january2027), 2028)
    }

    func testOnlyYearsFrom1900ToNextYearAreModelYears() {
        let latest = VehicleDetailsForm.maxYear
        XCTAssertGreaterThanOrEqual(latest, 2026)
        XCTAssertTrue(VehicleDetailsForm.isModelYear(2019))
        XCTAssertTrue(VehicleDetailsForm.isModelYear(1900))
        XCTAssertTrue(VehicleDetailsForm.isModelYear(latest))
        XCTAssertFalse(VehicleDetailsForm.isModelYear(1899))
        XCTAssertFalse(VehicleDetailsForm.isModelYear(1448), "an Islamic calendar year is not a model year")
        XCTAssertFalse(VehicleDetailsForm.isModelYear(2569), "a Buddhist calendar year is not a model year")
        XCTAssertFalse(VehicleDetailsForm.isModelYear(latest + 1))
    }
}
