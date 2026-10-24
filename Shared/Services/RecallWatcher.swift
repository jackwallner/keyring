import Foundation
import UserNotifications

/// Watches NHTSA for new recalls on every road vehicle in the garage, the way
/// a letter in the mail would, but sooner. The latest list per vehicle is
/// cached so the garage can flag a recall without a network trip, and only a
/// campaign that wasn't on the last list sends a notification: adding a car
/// shows its existing recalls in the app instead of pinging about each one.
@MainActor
enum RecallWatcher {
    static let refreshTaskID = "com.jackwallner.keyring.recalls"
    static let minimumGap: TimeInterval = 12 * 3600

    static func eligible(_ vehicle: Vehicle) -> Bool {
        vehicle.kind.hasNHTSARecords && vehicle.year > 1980 && vehicle.make != nil && vehicle.model != nil
    }

    // MARK: - Cache

    /// The last list fetched for this vehicle, or nil if it was never checked.
    static func cached(for vehicle: Vehicle) -> [Recall]? {
        guard let key = vehicle.id?.uuidString,
              let map = AppGroup.defaults.dictionary(forKey: AppGroup.Key.recallCache) as? [String: Data],
              let data = map[key] else { return nil }
        return try? JSONDecoder().decode([Recall].self, from: data)
    }

    /// Saves the latest list and returns the campaigns that are new since the last one.
    @discardableResult
    static func record(_ recalls: [Recall], for vehicle: Vehicle) -> [Recall] {
        guard let key = vehicle.id?.uuidString else { return [] }
        let previous = cached(for: vehicle)
        var map = (AppGroup.defaults.dictionary(forKey: AppGroup.Key.recallCache) as? [String: Data]) ?? [:]
        map[key] = try? JSONEncoder().encode(recalls)
        AppGroup.defaults.set(map, forKey: AppGroup.Key.recallCache)
        return newRecalls(recalls, since: previous)
    }

    /// Pure, for tests: nothing is new on the first look at a vehicle.
    nonisolated static func newRecalls(_ recalls: [Recall], since previous: [Recall]?) -> [Recall] {
        guard let previous else { return [] }
        let known = Set(previous.map(\.campaign))
        return recalls.filter { !known.contains($0.campaign) }
    }

    // MARK: - Checking

    /// On launch and foreground, at most twice a day.
    static func checkIfDue(store: GarageStore) async {
        let last = AppGroup.defaults.object(forKey: AppGroup.Key.lastRecallCheck) as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(last) > minimumGap else { return }
        await check(store: store)
    }

    static func check(store: GarageStore) async {
        var reached = false
        for vehicle in store.vehicles where eligible(vehicle) {
            guard let make = vehicle.make, let model = vehicle.model,
                  let recalls = try? await NHTSAClient.recalls(year: Int(vehicle.year), make: make, model: model) else { continue }
            reached = true
            let fresh = store.openRecalls(record(recalls, for: vehicle), for: vehicle)
            if !fresh.isEmpty { await notify(fresh, vehicle: vehicle) }
        }
        if reached { AppGroup.defaults.set(Date.now, forKey: AppGroup.Key.lastRecallCheck) }
        store.objectWillChange.send()
    }

    private static func notify(_ recalls: [Recall], vehicle: Vehicle) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Safety recall: \(vehicle.displayName)"
        let lead = recalls.count == 1 ? recalls[0].componentTitle : "\(recalls.count) new recalls"
        let urgent = recalls.contains { $0.parkIt } ? " NHTSA says not to drive it until it's fixed." : ""
        content.body = "\(lead). Just listed for the \(vehicle.descriptor).\(urgent) Recall repairs are free at a dealer."
        content.sound = .default
        if let id = vehicle.id?.uuidString { content.userInfo = ["vehicleID": id, "recalls": true] }
        let identifier = "recall-\(vehicle.id?.uuidString ?? "")-\(recalls.map(\.campaign).joined(separator: "-"))"
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }
}

/// Where a tapped notification should land.
@MainActor
final class NotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    struct Destination: Equatable {
        let vehicleID: UUID
        let showsRecalls: Bool
    }

    @Published var destination: Destination?

    /// A CSV opened in Keyring from Files, Mail or another app.
    @Published var importFile: URL?

    /// Opens `WidgetSnapshot.url(forVehicle:)` links and shared spreadsheets.
    func open(_ url: URL) {
        if url.isFileURL {
            importFile = url
            return
        }
        guard url.scheme == "keyring", url.host() == "vehicle" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let raw = parts.first, let id = UUID(uuidString: raw) else { return }
        destination = Destination(vehicleID: id, showsRecalls: parts.dropFirst().first == "recalls")
    }

    // Completion handler form, answered on the main thread. The async form's
    // compiler-made thunk calls UIKit's handler from a background thread, and
    // UIKit asserts the main thread there, so a tap could abort the app (the
    // crash Baby build 66 and Recharge build 39 shipped).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let id = (info["vehicleID"] as? String).flatMap(UUID.init(uuidString:))
        let recalls = info["recalls"] as? Bool ?? false
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in
            if let id { destination = Destination(vehicleID: id, showsRecalls: recalls) }
            done()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
