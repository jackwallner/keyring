import Foundation

/// The reorderable blocks on a vehicle's page. Fuel rides with History and the
/// Service Record leads Details, so the default order matches the original page.
enum VehicleSection: String, CaseIterable, Identifiable {
    case explore, maintenance, history, facts, details

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explore: "Explore"
        case .maintenance: "Maintenance"
        case .history: "History"
        case .facts: "Quick facts"
        case .details: "Details"
        }
    }

    var symbol: String {
        switch self {
        case .explore: "square.grid.2x2"
        case .maintenance: "wrench.and.screwdriver"
        case .history: "book.closed"
        case .facts: "list.bullet.rectangle"
        case .details: "info.circle"
        }
    }

    static let defaultOrder: [VehicleSection] = allCases

    /// Reads a stored order, dropping unknown or repeated names and appending any
    /// section the stored value is missing, so a new section never disappears.
    static func order(from stored: String) -> [VehicleSection] {
        var seen = Set<VehicleSection>()
        let parsed = stored.split(separator: ",").compactMap { VehicleSection(rawValue: String($0)) }.filter { seen.insert($0).inserted }
        return parsed + defaultOrder.filter { !seen.contains($0) }
    }

    static func stored(_ order: [VehicleSection]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }
}
