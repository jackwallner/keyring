import Foundation
import UserNotifications

/// Local reminders, rebuilt from scratch after every change. Each person
/// chooses for themselves: reminders live on the device, so a shared garage
/// doesn't ping the whole family about one car.
///
/// Rules, to stay useful rather than ignored: one heads-up a week ahead, one
/// on the day, and overdue jobs roll up into a single Saturday-morning note
/// instead of a daily nag.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    private let center = UNUserNotificationCenter.current()
    private var pending: Task<Void, Never>?

    var reminderHour: Int {
        let stored = AppGroup.defaults.object(forKey: AppGroup.Key.reminderHour) as? Int
        return stored ?? 9
    }

    func setReminderHour(_ hour: Int, store: GarageStore) {
        AppGroup.defaults.set(hour, forKey: AppGroup.Key.reminderHour)
        schedule(for: store)
    }

    var mutedVehicleIDs: Set<String> {
        Set(AppGroup.defaults.stringArray(forKey: AppGroup.Key.mutedVehicles) ?? [])
    }

    func setMuted(_ muted: Bool, vehicleID: UUID?, store: GarageStore) {
        guard let id = vehicleID?.uuidString else { return }
        var set = mutedVehicleIDs
        if muted { set.insert(id) } else { set.remove(id) }
        AppGroup.defaults.set(Array(set), forKey: AppGroup.Key.mutedVehicles)
        schedule(for: store)
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    struct Planned: Equatable {
        var id: String
        var title: String
        var body: String
        var fireDate: Date
        /// The vehicle a tap opens. The weekend roll-up spans several, so it has none.
        var vehicleID: String?
    }

    /// Pure planning, so the rules are testable without a notification center.
    static func plan(
        dues: [(vehicle: String, vehicleID: String, due: TaskDue)],
        now: Date,
        hour: Int,
        calendar: Calendar = .current
    ) -> [Planned] {
        var planned: [Planned] = []
        func atHour(_ date: Date) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
        }
        for (vehicle, vehicleID, due) in dues {
            guard due.result.status != .noRecord, due.result.status != .overdue,
                  let dueDate = due.result.dueDate else { continue }
            let approximate = due.result.dateIsEstimated ? "around " : ""
            let weekBefore = atHour(dueDate.addingTimeInterval(-7 * 86_400))
            if weekBefore > now {
                planned.append(Planned(
                    id: "week-\(vehicleID)-\(due.taskID.uuidString)",
                    title: "\(vehicle): \(due.name)",
                    body: "Coming due \(approximate)next week. Book it now and it's one less thing.",
                    fireDate: weekBefore,
                    vehicleID: vehicleID
                ))
            }
            let onDay = atHour(dueDate)
            if onDay > now {
                planned.append(Planned(
                    id: "day-\(vehicleID)-\(due.taskID.uuidString)",
                    title: "\(vehicle): \(due.name)",
                    body: due.result.dateIsEstimated
                        ? "Should be due about now, going by your usual pace. Tap to log it or update the meter."
                        : "Due today. Tap to log it when it's done.",
                    fireDate: onDay,
                    vehicleID: vehicleID
                ))
            }
        }
        let overdue = dues.filter { $0.due.result.status == .overdue }
        if !overdue.isEmpty {
            var components = DateComponents()
            components.weekday = 7
            components.hour = hour
            if let saturday = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) {
                let names = overdue.prefix(3).map { "\($0.vehicle) \($0.due.name.lowercasedFirst)" }
                let more = overdue.count > 3 ? " and \(overdue.count - 3) more" : ""
                planned.append(Planned(
                    id: "weekend-overdue",
                    title: overdue.count == 1 ? "One job is overdue" : "\(overdue.count) jobs are overdue",
                    body: names.joined(separator: ", ") + more + ".",
                    fireDate: saturday
                ))
            }
        }
        // iOS keeps 64 pending; the soonest matter most.
        return Array(planned.sorted { $0.fireDate < $1.fireDate }.prefix(60))
    }

    func schedule(for store: GarageStore) {
        let muted = mutedVehicleIDs
        let dues = store.vehicles
            .filter { !muted.contains($0.id?.uuidString ?? "") }
            .flatMap { vehicle in
                store.dues(for: vehicle).map { (vehicle: vehicle.displayName, vehicleID: vehicle.id?.uuidString ?? "", due: $0) }
            }
        let plan = Self.plan(dues: dues, now: .now, hour: reminderHour)
        pending?.cancel()
        pending = Task { [center] in
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else { return }
            center.removeAllPendingNotificationRequests()
            for item in plan {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                if let vehicleID = item.vehicleID { content.userInfo = ["vehicleID": vehicleID] }
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            }
        }
    }
}
