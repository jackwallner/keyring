import UIKit

/// Turns a vehicle into the Service Record and the spreadsheet. Both read
/// the same rows so the PDF and the CSV never disagree.
@MainActor
enum RecordBuilder {
    static func record(
        for vehicle: Vehicle, store: GarageStore, showCosts: Bool, includeReceipts: Bool,
        includeSchedule: Bool = true, includeNotes: Bool = true
    ) -> ServiceRecord {
        let tasks = (vehicle.tasks ?? [])
        // Fill-ups and events stay out: a buyer or a shop reads the work.
        let rows = vehicle.serviceEntries.filter { $0.kind != .event }.map { entry -> ServiceRecord.Row in
            let covered = tasks.filter { task in task.id.map(entry.coveredTaskIDs.contains) ?? false }
                .map(\.displayName)
            let title = entry.title ?? "Service"
            var details: [String] = []
            if entry.kind == .repair { details.append("Repair") }
            if entry.kind == .mod {
                details.append(entry.details.removedOn.map { "Modification, removed \(Format.shortDate($0))" } ?? "Modification")
            }
            if entry.kind == .recall, let campaign = entry.recallCampaign { details.append("Safety recall, NHTSA \(campaign)") }
            if covered.count > 1 || (covered.count == 1 && covered[0] != title) {
                details.append(covered.joined(separator: ", "))
            }
            let parts = entry.details.parts.map(\.summary).filter { !$0.isEmpty }
            if !parts.isEmpty { details.append("Parts: \(parts.joined(separator: "; "))") }
            if includeNotes {
                let specs = entry.details.specs.map { "\($0.name) \($0.display)" }
                if !specs.isEmpty { details.append(specs.joined(separator: ", ")) }
            }
            if includeNotes, let notes = entry.notes, !notes.isEmpty { details.append(notes) }
            return ServiceRecord.Row(
                date: entry.date,
                reading: entry.hasReading ? entry.reading : nil,
                title: title,
                detail: details.joined(separator: ". "),
                shop: entry.isDIY ? "Owner (DIY)" : (entry.shop ?? ""),
                cost: entry.cost,
                receipts: includeReceipts ? entry.sortedAttachments.filter(\.isReceipt).compactMap { ImageTools.thumbnail($0.data, maxDimension: 900) } : []
            )
        }
        let schedule = !includeSchedule ? [] : store.dues(for: vehicle).map { due -> ServiceRecord.ScheduleRow in
            let last = [due.lastDate.map { Format.shortDate($0) }, due.lastReading.map { Format.reading($0, due.meter) }]
                .compactMap { $0 }.joined(separator: " · ")
            var next = ""
            if due.result.status == .overdue {
                next = "Overdue"
            } else if let date = due.result.dueDate {
                next = (due.result.dateIsEstimated ? "About " : "") + Format.shortDate(date)
                if let reading = due.result.dueReading, due.meter.hasReading { next += " · \(Format.reading(reading, due.meter))" }
            } else if let reading = due.result.dueReading {
                next = Format.reading(reading, due.meter)
            }
            return ServiceRecord.ScheduleRow(
                name: due.name,
                interval: due.intervalText(auxName: vehicle.auxMeterName),
                last: last.isEmpty ? "Not recorded" : last,
                next: next.isEmpty ? "Not recorded" : next,
                status: due.result.status
            )
        }
        var identifiers: [(String, String)] = []
        if let vin = vehicle.vin { identifiers.append((vehicle.kind.identifierLabel, vin)) }
        if let plate = vehicle.plate { identifiers.append((vehicle.kind.registrationLabel, plate)) }
        if let trim = vehicle.trim { identifiers.append(("Trim", trim)) }
        identifiers.append(("Powertrain", vehicle.powertrain.title))
        if let bought = vehicle.purchaseDate { identifiers.append(("Owned since", bought.formatted(.dateTime.month(.abbreviated).year()))) }
        let profile = vehicle.profile
        if profile.mileageStatus != .actual { identifiers.append(("Mileage", profile.mileageStatus.title)) }
        for change in profile.odometerChanges {
            identifiers.append((change.replaced ? "Odometer replaced" : "Odometer rolled over",
                                "\(change.date.formatted(.dateTime.month(.abbreviated).year())) at \(Format.reading(change.lastShown, vehicle.meter))"))
        }
        // The owner's own facts: engine and chassis numbers, paint code.
        for fact in vehicle.facts.prefix(10) { identifiers.append((fact.label, fact.value)) }
        return ServiceRecord(
            vehicleName: vehicle.displayName,
            descriptor: [vehicle.descriptor, vehicle.trim].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "),
            kind: vehicle.kind,
            identifiers: identifiers,
            meter: vehicle.meter,
            reading: vehicle.reading,
            photo: ImageTools.thumbnail(vehicle.photo, maxDimension: 500),
            schedule: schedule,
            rows: rows,
            showCosts: showCosts,
            includeReceipts: includeReceipts,
            preparedBy: store.ownerName
        )
    }
}

/// Every entry as a spreadsheet. Free, always: a log you can't take with you
/// isn't yours.
enum CSVExport {
    static let header = ["Vehicle", "Year", "Make", "Model", "Date", "Odometer", "Unit", "Type", "Work", "Covered jobs", "Cost", "Shop", "DIY", "Notes", "Logged by", "Fuel", "Fuel unit", "Price per unit", "Grade", "Partial fill", "Parts", "Measurements", "Second meter"]

    @MainActor
    static func csv(for vehicles: [Vehicle]) -> String {
        var lines = [header.map(escape).joined(separator: ",")]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        for vehicle in vehicles {
            let tasks = vehicle.tasks ?? []
            for entry in vehicle.sortedEntries {
                let covered = tasks.filter { task in task.id.map(entry.coveredTaskIDs.contains) ?? false }.map(\.displayName)
                let fields = [
                    vehicle.displayName,
                    vehicle.year > 0 ? String(vehicle.year) : "",
                    vehicle.make ?? "",
                    vehicle.model ?? "",
                    entry.date.map(formatter.string(from:)) ?? "",
                    entry.hasReading ? String(Int(entry.reading.rounded())) : "",
                    vehicle.meter.short,
                    entry.kind.title,
                    entry.title ?? "",
                    covered.joined(separator: "; "),
                    entry.cost > 0 ? String(format: "%.2f", entry.cost) : "",
                    entry.shop ?? "",
                    entry.isDIY ? "Yes" : "",
                    entry.notes ?? "",
                    entry.loggedBy ?? "",
                ] + fuelFields(entry) + [
                    entry.details.parts.map(\.summary).filter { !$0.isEmpty }.joined(separator: "; "),
                    entry.details.specs.map { "\($0.name): \($0.display)" }.joined(separator: "; "),
                    entry.hasAuxReading ? Format.reading(entry.auxReading, vehicle.auxMeter) : "",
                ]
                lines.append(fields.map(escape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func fuelFields(_ entry: ServiceEntry) -> [String] {
        guard entry.kind == .fuel else { return ["", "", "", "", ""] }
        let unit = FuelVolumeUnit.current
        return [
            entry.fuelVolume > 0 ? String(format: "%.3f", unit.fromLiters(entry.fuelVolume)) : "",
            unit.short,
            entry.fuelUnitPrice > 0 ? String(format: "%.3f", unit.fromPerLiter(entry.fuelUnitPrice)) : "",
            entry.grade?.title ?? "",
            entry.fuelPartial ? "Yes" : "",
        ]
    }

    static func escape(_ field: String) -> String {
        var value = field
        // A leading = + - @ makes spreadsheets run the cell as a formula.
        if let first = value.first, "=+-@".contains(first) { value = "'" + value }
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    @MainActor
    static func url(for vehicles: [Vehicle], name: String = "Vehicle-Service-Log") throws -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).csv")
        try csv(for: vehicles).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// Spending and use, for the Insights screen.
struct CostInsights: Equatable {
    struct Month: Identifiable, Equatable {
        let start: Date
        let total: Double
        var id: Date { start }
    }

    struct Slice: Identifiable, Equatable {
        let name: String
        let total: Double
        var id: String { name }
    }

    var lastTwelveMonths: Double
    var allTime: Double
    var months: [Month]
    var byVehicle: [Slice]
    var byJob: [Slice]
    var diyShare: Double
    /// Unplanned repairs, last 12 months: the number owners most want to see.
    var repairs: Double
    /// Spent on mods, last 12 months, kept apart from upkeep.
    var mods: Double = 0
    var costPerDistance: Double?
    var distanceUnit: String

    @MainActor
    static func compute(vehicles: [Vehicle], now: Date = .now, calendar: Calendar = .current) -> CostInsights {
        let entries = vehicles.flatMap { vehicle in vehicle.sortedEntries.map { (vehicle, $0) } }
        let yearAgo = calendar.date(byAdding: .month, value: -12, to: now) ?? now
        let recent = entries.filter { ($0.1.date ?? .distantPast) >= yearAgo }
        let allTime = entries.reduce(0) { $0 + $1.1.cost }
        let lastYear = recent.reduce(0) { $0 + $1.1.cost }

        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let months = (0..<12).reversed().compactMap { offset -> Month? in
            guard let start = calendar.date(byAdding: .month, value: -offset, to: thisMonth),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            let total = entries.filter { guard let date = $0.1.date else { return false }; return date >= start && date < end }
                .reduce(0) { $0 + $1.1.cost }
            return Month(start: start, total: total)
        }

        var vehicleTotals: [String: Double] = [:]
        for (vehicle, entry) in recent { vehicleTotals[vehicle.displayName, default: 0] += entry.cost }
        var jobTotals: [String: Double] = [:]
        for (_, entry) in recent where entry.cost > 0 {
            let name = switch entry.kind {
            case .fuel: "Fuel"
            case .mod: "Mods"
            default: entry.title ?? "Service"
            }
            jobTotals[name, default: 0] += entry.cost
        }

        // The DIY share is of upkeep spending, so fuel and mods stay out of it.
        let upkeep = recent.filter { $0.1.kind.isUpkeep }
        let diy = upkeep.filter { $0.1.isDIY }.reduce(0) { $0 + $1.1.cost }
        let maintenance = upkeep.reduce(0) { $0 + $1.1.cost }
        let mods = recent.filter { $0.1.kind == .mod }.reduce(0) { $0 + $1.1.cost }
        let repairs = recent.filter { $0.1.kind == .repair }.reduce(0) { $0 + $1.1.cost }

        // Cost per mile (or km) from distance-metered vehicles with enough
        // history, each converted to one unit so a mixed garage adds up.
        let hasKm = vehicles.contains { $0.meter == .kilometers }
        let hasMiles = vehicles.contains { $0.meter == .miles }
        let target: MeterUnit = hasKm && (!hasMiles || Locale.current.measurementSystem == .metric) ? .kilometers : .miles
        var distance = 0.0
        var spend = 0.0
        for vehicle in vehicles where vehicle.meter == .miles || vehicle.meter == .kilometers {
            let points = vehicle.sortedEntries.filter { $0.hasReading && ($0.date ?? .distantPast) >= yearAgo }.map(\.reading)
                + vehicle.mainReadings.filter { ($0.date ?? .distantPast) >= yearAgo }.map(\.value)
            guard let low = points.min(), let high = points.max(), high - low > 500 else { continue }
            distance += vehicle.meter.convert(high - low, to: target) ?? 0
            // Running cost: mods make it better, they don't keep it going.
            spend += vehicle.sortedEntries.filter { ($0.date ?? .distantPast) >= yearAgo && $0.kind != .mod }.reduce(0) { $0 + $1.cost }
        }
        let unit = target.short

        return CostInsights(
            lastTwelveMonths: lastYear,
            allTime: allTime,
            months: months,
            byVehicle: vehicleTotals.map { Slice(name: $0.key, total: $0.value) }.sorted { $0.total > $1.total },
            byJob: jobTotals.map { Slice(name: $0.key, total: $0.value) }.sorted { $0.total > $1.total }.prefix(6).map { $0 },
            diyShare: maintenance > 0 ? diy / maintenance : 0,
            repairs: repairs,
            mods: mods,
            costPerDistance: distance > 0 ? spend / distance : nil,
            distanceUnit: unit
        )
    }
}
