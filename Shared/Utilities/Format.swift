import Foundation

/// Every number and date the app shows, formatted one way.
enum Format {
    static func reading(_ value: Double, _ meter: MeterUnit) -> String {
        switch meter {
        case .hours:
            // Hobbs and tach meters read in tenths.
            let tenths = (value * 10).rounded() / 10
            let text = tenths == tenths.rounded()
                ? Int(tenths).formatted()
                : tenths.formatted(.number.precision(.fractionLength(1)))
            return "\(text) hrs"
        case .none:
            return ""
        default:
            return "\(Int(value.rounded()).formatted()) \(meter.short)"
        }
    }

    /// "Every 7,500 mi or 1 year", "Every year", "As needed". A second meter's
    /// name goes in front of its hours: "Every 150 generator hrs". A second
    /// meter's whichever-first figure and an event join the list: "Every
    /// 100 hrs, 1,000 mi or 1 year", "Every 6 months and every track day".
    static func interval(
        distance: Double, months: Int, meter: MeterUnit, auxName: String? = nil,
        second: Double = 0, secondMeter: MeterUnit = .hours, secondName: String? = nil,
        trigger: UsageEvent? = nil
    ) -> String {
        var amounts: [String] = []
        if distance > 0 && meter.hasReading { amounts.append(amount(distance, meter, name: auxName)) }
        if second > 0 && secondMeter.hasReading { amounts.append(amount(second, secondMeter, name: secondName)) }
        var base: String?
        switch (amounts.isEmpty, months > 0) {
        case (false, true): base = "Every \(list(amounts + [monthsText(months)]))"
        case (false, false): base = "Every \(list(amounts))"
        case (true, true): base = months == 12 ? "Every year" : months == 1 ? "Every month" : "Every \(monthsText(months))"
        case (true, false): base = nil
        }
        switch (base, trigger) {
        case let (base?, trigger?): return "\(base) and \(trigger.dueRule.lowercasedFirst)"
        case let (base?, nil): return base
        case let (nil, trigger?): return trigger.dueRule
        case (nil, nil): return "As needed"
        }
    }

    private static func amount(_ value: Double, _ meter: MeterUnit, name: String?) -> String {
        let text = reading(value, meter)
        guard let name, meter == .hours else { return text }
        return text.replacingOccurrences(of: " hrs", with: " \(name.lowercased()) hrs")
    }

    /// "a", "a or b", "a, b or c".
    private static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " or " + (items.last ?? "")
    }

    /// "1 year", "18 months".
    static func monthsText(_ months: Int) -> String {
        if months % 12 == 0 {
            let years = months / 12
            return years == 1 ? "1 year" : "\(years) years"
        }
        return months == 1 ? "1 month" : "\(months) months"
    }

    static func money(_ value: Double, code: String = Locale.current.currency?.identifier ?? "USD") -> String {
        let fraction = value.rounded() == value || value >= 1_000 ? 0 : 2
        return value.formatted(.currency(code: code).precision(.fractionLength(fraction)))
    }

    /// A pump price, to the tenth of a cent pumps show: $3.659.
    static func unitPrice(_ value: Double, code: String = Locale.current.currency?.identifier ?? "USD") -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(2...3)))
    }

    /// "2", "1.5": a quantity without trailing zeros.
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n.formatted()) \(n == 1 ? singular : plural)"
    }

    /// "in 3 weeks", "today", "2 months ago", in plain words.
    static func relative(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case 2...13: return "in \(days) days"
        case -13 ... -2: return "\(-days) days ago"
        case 14...59: return "in \(days / 7) weeks"
        case -59 ... -14: return "\(-days / 7) weeks ago"
        case 60...729: return "in \(Int((Double(days) / 30.4).rounded())) months"
        case -729 ... -60: return "\(Int((Double(-days) / 30.4).rounded())) months ago"
        default:
            let years = Int((Double(abs(days)) / 365).rounded())
            return days > 0 ? "in \(years) years" : "\(years) years ago"
        }
    }

    static func shortDate(_ date: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.month(.abbreviated).day()) : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
