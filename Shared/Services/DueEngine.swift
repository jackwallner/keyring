import Foundation

/// When each job comes due. Pure value types in and out, so the garage, the
/// reminders, the widget and the PDF can never disagree.
enum DueStatus: Int, Comparable, Sendable {
    case overdue = 0
    case dueSoon = 1
    case noRecord = 2
    case ok = 3

    static func < (lhs: DueStatus, rhs: DueStatus) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .overdue: "Overdue"
        case .dueSoon: "Due soon"
        case .noRecord: "No record yet"
        case .ok: "Up to date"
        }
    }
}

struct DueInput: Sendable {
    var intervalDistance: Double      // 0 = none
    var intervalMonths: Int           // 0 = none
    var lastDate: Date?
    var lastReading: Double?          // nil = unknown
    var currentReading: Double
    var dailyUse: Double              // vehicle's pace, in its own meter
    var meter: MeterUnit
    /// FAA-style "calendar months": due at the end of the month the interval
    /// lands in, so an annual signed off on March 3 runs to March 31 next year.
    var calendarMonths = false
}

struct DueResult: Equatable, Sendable {
    var status: DueStatus
    /// The earlier of the calendar date and the estimated date the meter
    /// reaches its target.
    var dueDate: Date?
    var dueReading: Double?
    /// How much of the interval is used up, 0 to 1 (can exceed 1 when late).
    var progress: Double
    /// True when the due date is an estimate from the meter pace, not the
    /// calendar.
    var dateIsEstimated: Bool
}

enum DueEngine {
    /// Days ahead that count as "due soon".
    static let soonWindowDays = 30.0

    static func evaluate(_ input: DueInput, now: Date = .now, calendar: Calendar = .current) -> DueResult {
        let usesDistance = input.intervalDistance > 0 && input.meter.hasReading
        let usesTime = input.intervalMonths > 0

        guard usesDistance || usesTime else {
            return DueResult(status: .ok, dueDate: nil, dueReading: nil, progress: 0, dateIsEstimated: false)
        }
        let knowsTime = usesTime && input.lastDate != nil
        let knowsDistance = usesDistance && input.lastReading != nil
        guard knowsTime || knowsDistance else {
            return DueResult(status: .noRecord, dueDate: nil, dueReading: nil, progress: 0, dateIsEstimated: false)
        }

        var candidates: [(date: Date, estimated: Bool)] = []
        var progress = 0.0
        var dueReading: Double?
        var overdue = false

        if knowsTime, let last = input.lastDate,
           let due = timeDue(after: last, input: input, calendar: calendar) {
            candidates.append((due, false))
            let total = due.timeIntervalSince(last)
            if total > 0 { progress = max(progress, now.timeIntervalSince(last) / total) }
            if now >= due { overdue = true }
        }

        if knowsDistance, let lastReading = input.lastReading {
            let target = lastReading + input.intervalDistance
            dueReading = target
            let used = input.currentReading - lastReading
            progress = max(progress, used / input.intervalDistance)
            if input.currentReading >= target {
                overdue = true
                candidates.append((now, true))
            } else if input.dailyUse > 0 {
                let days = (target - input.currentReading) / input.dailyUse
                if days.isFinite, days < 365 * 30 {
                    candidates.append((now.addingTimeInterval(days * 86_400), true))
                }
            }
        }

        let earliest = candidates.min { $0.date < $1.date }
        let status: DueStatus
        if overdue {
            status = .overdue
        } else if let earliest, earliest.date.timeIntervalSince(now) <= soonWindowDays * 86_400 {
            status = .dueSoon
        } else if let dueReading, input.currentReading >= dueReading - input.intervalDistance * 0.1 {
            status = .dueSoon
        } else {
            status = .ok
        }
        return DueResult(
            status: status,
            dueDate: earliest?.date,
            dueReading: dueReading,
            progress: max(0, progress),
            dateIsEstimated: earliest?.estimated ?? false
        )
    }

    private static func timeDue(after last: Date, input: DueInput, calendar: Calendar) -> Date? {
        guard let due = calendar.date(byAdding: .month, value: input.intervalMonths, to: last) else { return nil }
        guard input.calendarMonths, let month = calendar.dateInterval(of: .month, for: due) else { return due }
        return month.end.addingTimeInterval(-1)
    }

    /// Use per day from the vehicle's own history: readings and service
    /// entries over the last year, needing two weeks of spread before the
    /// owner's pace beats the kind's typical figure.
    static func dailyUse(readings: [(date: Date, value: Double)], fallback: Double, now: Date = .now) -> Double {
        let yearAgo = now.addingTimeInterval(-365 * 86_400)
        let recent = readings.filter { $0.date >= yearAgo && $0.value >= 0 }.sorted { $0.date < $1.date }
        guard let first = recent.first, let last = recent.last else { return fallback }
        let days = last.date.timeIntervalSince(first.date) / 86_400
        let delta = last.value - first.value
        guard days >= 14, delta > 0 else { return fallback }
        return delta / days
    }
}
