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

    /// Every job across the garage, most urgent first.
    var upcoming: [(vehicle: VehicleSummary, item: Item)] {
        vehicles.flatMap { vehicle in vehicle.items.map { (vehicle, $0) } }
            .sorted {
                if $0.item.statusRaw != $1.item.statusRaw { return $0.item.statusRaw < $1.item.statusRaw }
                return ($0.item.dueDate ?? .distantFuture) < ($1.item.dueDate ?? .distantFuture)
            }
    }
}
