import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// What the widget shows, written by the app after every change. The widget
/// never opens the database, so it can't show anything the app wouldn't.
struct WidgetSnapshot: Codable, Sendable {
    struct Item: Codable, Hashable, Sendable {
        var name: String
        /// `DueStatus` raw value: 0 overdue, 1 due soon, 3 up to date.
        var statusRaw: Int
        var dueDate: Date?
        var estimated: Bool
        /// "At 54,000 mi" for a job due by the meter with no date to show.
        var dueAt: String?

        /// The status on `now`. The snapshot is written when the app runs, so a
        /// due date that has come since then moves the job along.
        func status(on now: Date) -> DueStatus {
            let written = DueStatus(rawValue: statusRaw) ?? .ok
            guard written != .overdue, let dueDate else { return written }
            // Only the calendar is certain; an estimate from the pace is due about now.
            if now >= dueDate { return estimated ? .dueSoon : .overdue }
            if written == .ok, dueDate.timeIntervalSince(now) <= DueEngine.soonWindowDays * 86_400 { return .dueSoon }
            return written
        }
    }

    struct VehicleSummary: Codable, Hashable, Identifiable, Sendable {
        var id: String
        var name: String
        var symbol: String
        var tintHex: UInt32
        var items: [Item]
    }

    var vehicles: [VehicleSummary]
    var updatedAt: Date

    /// `keyring://vehicle/<id>`, which the app opens on that vehicle.
    static func url(forVehicle id: String) -> URL? {
        URL(string: "keyring://vehicle/\(id)")
    }

    static let empty = WidgetSnapshot(vehicles: [], updatedAt: .distantPast)

    static func read() -> WidgetSnapshot {
        guard let data = AppGroup.defaults.data(forKey: AppGroup.Key.widgetSnapshot),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }

    static func write(_ snapshot: WidgetSnapshot) {
        let previous = AppGroup.defaults.data(forKey: AppGroup.Key.widgetSnapshot)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // Comparing without the timestamp keeps a plain reload from waking
        // every widget.
        var stripped = snapshot
        stripped.updatedAt = .distantPast
        if let previous, var old = try? JSONDecoder().decode(WidgetSnapshot.self, from: previous) {
            old.updatedAt = .distantPast
            if old.vehicles == stripped.vehicles { return }
        }
        AppGroup.defaults.set(data, forKey: AppGroup.Key.widgetSnapshot)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Every job across the garage, most urgent first on `now`.
    func upcoming(on now: Date) -> [(vehicle: VehicleSummary, item: Item)] {
        vehicles.flatMap { vehicle in vehicle.items.map { (vehicle, $0) } }
            .sorted {
                let lhs = $0.item.status(on: now), rhs = $1.item.status(on: now)
                if lhs != rhs { return lhs < rhs }
                return ($0.item.dueDate ?? .distantFuture) < ($1.item.dueDate ?? .distantFuture)
            }
    }
}
