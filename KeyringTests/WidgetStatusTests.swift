import XCTest
@testable import Keyring

/// The widget re-reads the same snapshot every midnight, so a due date that
/// passes after the app last ran has to move the job along on its own.
final class WidgetStatusTests: XCTestCase {
    private let day: TimeInterval = 86_400

    private func item(_ status: DueStatus, dueIn days: Double, estimated: Bool) -> WidgetSnapshot.Item {
        .init(name: "Oil", statusRaw: status.rawValue, dueDate: .now.addingTimeInterval(days * day), estimated: estimated)
    }

    func testACalendarJobThatHasPassedReadsOverdue() {
        XCTAssertEqual(item(.dueSoon, dueIn: -20, estimated: false).status(on: .now), .overdue)
    }

    func testAnEstimatedDateThatHasPassedIsNotUpToDate() {
        XCTAssertEqual(item(.ok, dueIn: -3, estimated: true).status(on: .now), .dueSoon)
    }

    func testAnUpToDateJobComesDueSoonInsideTheWindow() {
        XCTAssertEqual(item(.ok, dueIn: 10, estimated: false).status(on: .now), .dueSoon)
        XCTAssertEqual(item(.ok, dueIn: 80, estimated: false).status(on: .now), .ok)
    }

    func testTheWrittenStatusStandsWhileTheDateIsAhead() {
        XCTAssertEqual(item(.dueSoon, dueIn: 5, estimated: true).status(on: .now), .dueSoon)
        XCTAssertEqual(item(.overdue, dueIn: 5, estimated: true).status(on: .now), .overdue)
    }

    func testAPassedJobSortsFirst() {
        let snapshot = WidgetSnapshot(vehicles: [
            .init(id: "1", name: "Car", symbol: "car", tintHex: 0, items: [
                item(.dueSoon, dueIn: 3, estimated: false),
                .init(name: "Brakes", statusRaw: DueStatus.dueSoon.rawValue, dueDate: .now.addingTimeInterval(-2 * day), estimated: false),
            ]),
        ], updatedAt: .now)
        XCTAssertEqual(snapshot.upcoming(on: .now).first?.item.name, "Brakes")
    }
}
