import Foundation

/// Reads a service history exported from another app or a spreadsheet:
/// Fuelly, Drivvo, Simply Auto, aCar, a Keyring export, or any CSV with a
/// date column. Pure, so tests can feed it files.
enum ServiceImport {
    enum Field: String, CaseIterable, Identifiable, Sendable {
        case date, odometer, work, cost, shop, notes, vehicle, kind, diy, loggedBy, unit, year, make, model

        var id: String { rawValue }

        var title: String {
            switch self {
            case .date: "Date"
            case .odometer: "Odometer"
            case .work: "Work done"
            case .cost: "Cost"
            case .shop: "Shop"
            case .notes: "Notes"
            case .vehicle: "Vehicle"
            case .kind: "Type"
            case .diy: "DIY"
            case .loggedBy: "Logged by"
            case .unit: "Unit"
            case .year: "Year"
            case .make: "Make"
            case .model: "Model"
            }
        }

        /// The columns a person might need to fix by hand.
        static let editable: [Field] = [.date, .odometer, .work, .cost, .shop, .notes, .vehicle]

        /// Header spellings, lowercased with everything but letters and digits
        /// removed. Earlier spellings win.
        var names: [String] {
            switch self {
            case .date: ["date", "servicedate", "fuelupdate", "refuelingdate", "refuellingdate", "dateperformed", "performedon",
                         "completed", "completedon", "datetime", "day", "when", "fecha", "datum", "data"]
            case .odometer: ["odometer", "odo", "odometerreading", "odometermi", "odometerkm", "odometermiles", "odometerkilometers",
                             "odometerkilometres", "mileage", "kilometrage", "km", "kms", "kilometers", "kilometres", "hours",
                             "enginehours", "hobbs", "tach", "meter", "reading", "totalmiles", "currentmileage"]
            case .work: ["work", "service", "services", "servicetype", "servicetypes", "servicesperformed", "workdone", "servicename",
                         "maintenance", "task", "tasks", "job", "jobs", "item", "items", "title", "description", "type",
                         "expensetype", "expense", "category", "repair", "parts"]
            case .cost: ["cost", "totalcost", "total", "amount", "totalamount", "totalprice", "price", "paid", "charge", "value"]
            case .shop: ["shop", "place", "location", "vendor", "garage", "station", "servicecenter", "provider", "where",
                         "mechanic", "dealer", "business", "store", "performedby", "servicedby"]
            case .notes: ["notes", "note", "comments", "comment", "memo", "remarks", "details", "description"]
            case .vehicle: ["vehicle", "car", "carname", "vehiclename", "vehiclenickname", "nickname", "auto", "bike", "boat"]
            case .kind: ["entrytype", "kind"]
            case .diy: ["diy", "selfservice", "didityourself"]
            case .loggedBy: ["loggedby", "driver", "enteredby", "user"]
            case .unit: ["unit", "units", "odometerunit", "distanceunit"]
            case .year: ["year", "modelyear"]
            case .make: ["make", "manufacturer", "brand"]
            case .model: ["model"]
            }
        }
    }

    enum Source: String, Sendable {
        case keyring = "Keyring"
        case fuelly = "Fuelly"
        case drivvo = "Drivvo"
        case simplyAuto = "Simply Auto"
        case spreadsheet = "your spreadsheet"
    }

    /// One block of rows under one header line. Exports from Drivvo and
    /// Simply Auto stack fill-ups, services and expenses in one file.
    struct Table: Identifiable, Sendable {
        enum Role: Sendable { case service, fuel, expense }

        let id: Int
        var title: String?
        var headers: [String]
        var rows: [[String]]
        var mapping: [Field: Int]
        var role: Role
    }

    struct Row: Identifiable, Hashable, Sendable {
        var id: Int
        var vehicleName: String
        var date: Date
        var reading: Double?
        var unit: MeterUnit?
        var work: String
        var cost: Double
        var shop: String?
        var notes: String?
        var kind: EntryKind
        var isDIY: Bool
        var loggedBy: String?
        var isFillUp: Bool
        var year: Int?
        var make: String?
        var model: String?
    }

    struct Result: Sendable {
        var source: Source
        var tables: [Table]
        var services: [Row]
        var fillUps: [Row]
        /// Insurance, parking, tolls and the like: real costs, not maintenance.
        var skippedExpenses: Int
        /// Rows with no date Keyring could read.
        var unreadable: Int

        var isEmpty: Bool { services.isEmpty && fillUps.isEmpty }

        /// Each vehicle named in the file, in order of first appearance, with
        /// "" for files that never name one.
        var vehicleNames: [String] {
            var seen: [String] = []
            for row in services + fillUps where !seen.contains(row.vehicleName) { seen.append(row.vehicleName) }
            return seen
        }

        /// The table whose columns the person is most likely to want to fix.
        var mainTable: Table? {
            tables.filter { $0.role == .service }.max { $0.rows.count < $1.rows.count }
                ?? tables.max { $0.rows.count < $1.rows.count }
        }
    }

    // MARK: - Parsing

    static func parse(_ text: String, locale: Locale = .current) -> Result {
        let tables = findTables(in: rows(from: text))
        return build(tables, locale: locale)
    }

    /// Rebuilds the rows after the person points a field at another column.
    static func remap(_ result: Result, table id: Int, field: Field, to column: Int?, locale: Locale = .current) -> Result {
        var tables = result.tables
        guard let index = tables.firstIndex(where: { $0.id == id }) else { return result }
        for (other, value) in tables[index].mapping where value == column && other != field {
            tables[index].mapping[other] = nil
        }
        tables[index].mapping[field] = column
        return build(tables, locale: locale)
    }

    private static func build(_ tables: [Table], locale: Locale) -> Result {
        var services: [Row] = []
        var fillUps: [Row] = []
        var skipped = 0
        var unreadable = 0
        var nextID = 0
        for table in tables {
            guard let dateColumn = table.mapping[.date] else { continue }
            if table.role == .expense {
                skipped += table.rows.count
                continue
            }
            let dates = DateColumn(values: table.rows.map { cell($0, dateColumn) }, locale: locale)
            let thousandsDot = table.mapping[.odometer].map { column in
                usesDotThousands(table.rows.map { cell($0, column) })
            } ?? false
            let headerUnit = table.mapping[.odometer].map { unit(fromHeader: table.headers[$0]) } ?? nil
            for raw in table.rows {
                guard let date = dates.date(from: cell(raw, dateColumn)) else {
                    if raw.contains(where: { !$0.trimmed.isEmpty }) { unreadable += 1 }
                    continue
                }
                let value = { (field: Field) -> String in table.mapping[field].map { cell(raw, $0).trimmed } ?? "" }
                let work = value(.work)
                if table.role == .service, isExpense(work) {
                    skipped += 1
                    continue
                }
                let reading = number(value(.odometer), thousandsDot: thousandsDot).flatMap { $0 > 0 ? $0 : nil }
                let isFillUp = table.role == .fuel
                if !isFillUp, work.isEmpty, reading == nil, number(value(.cost)) == nil { continue }
                let row = Row(
                    id: nextID,
                    vehicleName: value(.vehicle),
                    date: date,
                    reading: reading,
                    unit: unit(from: value(.unit)) ?? headerUnit,
                    work: work,
                    cost: isFillUp ? 0 : max(0, number(value(.cost)) ?? 0),
                    shop: value(.shop).nilIfEmpty,
                    notes: value(.notes).nilIfEmpty,
                    kind: kind(type: value(.kind), work: work),
                    isDIY: ["yes", "y", "true", "1", "x"].contains(value(.diy).lowercased()),
                    loggedBy: value(.loggedBy).nilIfEmpty,
                    isFillUp: isFillUp,
                    year: Int(value(.year)).flatMap { (1900...2100).contains($0) ? $0 : nil },
                    make: value(.make).nilIfEmpty,
                    model: value(.model).nilIfEmpty
                )
                nextID += 1
                if isFillUp { fillUps.append(row) } else { services.append(row) }
            }
        }
        return Result(
            source: source(of: tables),
            tables: tables,
            services: services.sorted { $0.date < $1.date },
            fillUps: fillUps.sorted { $0.date < $1.date },
            skippedExpenses: skipped,
            unreadable: unreadable
        )
    }

    // MARK: - Tables

    private static func findTables(in rows: [[String]]) -> [Table] {
        var tables: [Table] = []
        var index = 0
        var pendingTitle: String?
        while index < rows.count {
            let row = rows[index]
            let filled = row.map(\.trimmed).filter { !$0.isEmpty }
            if let mapping = headerMapping(row), mapping[.date] != nil, mapping.count >= 2 {
                var body: [[String]] = []
                index += 1
                while index < rows.count {
                    let next = rows[index]
                    let nextFilled = next.map(\.trimmed).filter { !$0.isEmpty }
                    if nextFilled.isEmpty { index += 1; if body.isEmpty { continue } else { break } }
                    if let other = headerMapping(next), other[.date] != nil, other.count >= 2 { break }
                    if nextFilled.count == 1, next.count > 1, isSectionTitle(nextFilled[0]) { break }
                    body.append(next)
                    index += 1
                }
                let table = Table(id: tables.count, title: pendingTitle, headers: row, rows: body, mapping: mapping,
                                  role: role(title: pendingTitle, headers: row))
                if !table.rows.isEmpty { tables.append(table) }
                pendingTitle = nil
                continue
            }
            if filled.count == 1 { pendingTitle = filled[0] }
            index += 1
        }
        return tables
    }

    private static func isSectionTitle(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("#") || ["refuel", "fuel", "service", "expense", "income", "route", "trip", "reminder", "maintenance"]
            .contains { lower.contains($0) } && lower.count < 40 && !lower.contains(where: \.isNumber)
    }

    static func headerMapping(_ row: [String]) -> [Field: Int]? {
        let normalized = row.map(normalize)
        guard normalized.contains(where: { !$0.isEmpty }) else { return nil }
        // A Keyring export maps one to one.
        if normalized.starts(with: ["vehicle", "year", "make", "model", "date", "odometer", "unit", "type", "work"]) {
            var mapping: [Field: Int] = [.vehicle: 0, .year: 1, .make: 2, .model: 3, .date: 4, .odometer: 5, .unit: 6, .kind: 7, .work: 8]
            for (field, name) in [(Field.cost, "cost"), (.shop, "shop"), (.diy, "diy"), (.notes, "notes"), (.loggedBy, "loggedby")] {
                if let column = normalized.firstIndex(of: name) { mapping[field] = column }
            }
            return mapping
        }
        var mapping: [Field: Int] = [:]
        var used = Set<Int>()
        for field in Field.allCases {
            for name in field.names {
                if let column = normalized.indices.first(where: { normalized[$0] == name && !used.contains($0) }) {
                    mapping[field] = column
                    used.insert(column)
                    break
                }
            }
        }
        // Looser matches for the two columns that matter most.
        if mapping[.date] == nil, let column = normalized.indices.first(where: { column in
            let name = normalized[column]
            return !used.contains(column) && name.contains("date")
                && !["added", "created", "modified", "due", "next", "updated"].contains { name.contains($0) }
        }) {
            mapping[.date] = column
            used.insert(column)
        }
        if mapping[.odometer] == nil, let column = normalized.indices.first(where: { column in
            !used.contains(column) && (normalized[column].hasPrefix("odometer") || normalized[column].hasPrefix("odo")
                || normalized[column].hasPrefix("mileage"))
        }) {
            mapping[.odometer] = column
            used.insert(column)
        }
        // "Miles" is trip distance in fuel logs; only trust it when nothing
        // else could be the odometer and the file isn't about fuel.
        if mapping[.odometer] == nil, !hasFuelColumns(normalized), let column = normalized.firstIndex(of: "miles") {
            mapping[.odometer] = column
        }
        return mapping.isEmpty ? nil : mapping
    }

    private static func role(title: String?, headers: [String]) -> Table.Role {
        let lower = title?.lowercased() ?? ""
        if ["fuel", "refuel", "gas", "fill"].contains(where: lower.contains) { return .fuel }
        if ["expense", "income", "route", "trip", "reminder"].contains(where: lower.contains) { return .expense }
        if ["service", "maintenance", "repair"].contains(where: lower.contains) { return .service }
        return hasFuelColumns(headers.map(normalize)) ? .fuel : .service
    }

    private static func hasFuelColumns(_ normalized: [String]) -> Bool {
        let markers = ["gallon", "litre", "liter", "volume", "mpg", "l100", "quantity", "fillup", "refuel", "fuelup", "partial", "missed", "kwh"]
        return normalized.contains { name in markers.contains(where: name.contains) }
    }

    private static func source(of tables: [Table]) -> Source {
        let headers = Set(tables.flatMap(\.headers).map(normalize))
        let titles = tables.compactMap(\.title).joined(separator: " ").lowercased()
        if headers.isSuperset(of: ["vehicle", "work", "coveredjobs"]) { return .keyring }
        if headers.contains("fuelupdate") || headers.contains("carname") { return .fuelly }
        if titles.contains("##") || titles.contains("refuelling") { return .drivvo }
        if titles.contains("log") && (titles.contains("fuel") || titles.contains("service")) { return .simplyAuto }
        return .spreadsheet
    }

    // MARK: - Cells

    static func normalize(_ header: String) -> String {
        String(header.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII })
    }

    private static func cell(_ row: [String], _ column: Int) -> String {
        column < row.count ? row[column] : ""
    }

    private static let expenseWords = ["insurance", "parking", "toll", "fine", "ticket", "loan", "payment", "lease", "tax",
                                       "car wash", "wash", "fuel", "gas", "fill-up", "fill up", "financing", "membership", "subscription"]

    private static func isExpense(_ work: String) -> Bool {
        let lower = work.lowercased().trimmed
        guard !lower.isEmpty else { return false }
        return expenseWords.contains(lower) || expenseWords.contains { lower == $0 + "s" }
    }

    private static func kind(type: String, work: String) -> EntryKind {
        let type = type.lowercased()
        if type.contains("recall") { return .recall }
        if type.contains("repair") { return .repair }
        if !type.isEmpty, type.contains("maint") || type.contains("service") { return .service }
        let lower = work.lowercased()
        if lower.contains("recall") { return .recall }
        if lower.contains("repair") { return .repair }
        return .service
    }

    static func unit(from text: String) -> MeterUnit? {
        switch normalize(text) {
        case "mi", "mile", "miles": .miles
        case "km", "kms", "kilometer", "kilometers", "kilometre", "kilometres": .kilometers
        case "hr", "hrs", "hour", "hours", "h": .hours
        default: nil
        }
    }

    private static func unit(fromHeader header: String) -> MeterUnit? {
        let name = normalize(header)
        if name.hasSuffix("km") || name.contains("kilomet") { return .kilometers }
        if name.hasSuffix("mi") || name.hasSuffix("miles") { return .miles }
        if name.contains("hour") || name.contains("hobbs") || name.contains("tach") { return .hours }
        return nil
    }

    /// "1,234.56", "1.234,56", "$45", "45,00 €". With `thousandsDot`, a dot
    /// always groups thousands (European odometers: "45.000").
    static func number(_ raw: String, thousandsDot: Bool = false) -> Double? {
        var text = raw.filter { "0123456789.,".contains($0) }
        guard text.contains(where: \.isNumber) else { return nil }
        if thousandsDot {
            text.removeAll { $0 == "." }
            text = text.replacingOccurrences(of: ",", with: ".")
            return Double(text)
        }
        let dot = text.lastIndex(of: ".")
        let comma = text.lastIndex(of: ",")
        switch (dot, comma) {
        case let (dot?, comma?):
            if dot > comma {
                text.removeAll { $0 == "," }
            } else {
                text.removeAll { $0 == "." }
                text = text.replacingOccurrences(of: ",", with: ".")
            }
        case (nil, _?):
            let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2, parts[1].count != 3 {
                text = text.replacingOccurrences(of: ",", with: ".")
            } else {
                text.removeAll { $0 == "," }
            }
        case (_?, nil):
            if text.filter({ $0 == "." }).count > 1 { text.removeAll { $0 == "." } }
        default:
            break
        }
        return Double(text)
    }

    /// True when every dotted value reads like "45.000" or "1.234.567".
    private static func usesDotThousands(_ values: [String]) -> Bool {
        let dotted = values.map(\.trimmed).filter { $0.contains(".") }
        guard !dotted.isEmpty else { return false }
        return dotted.allSatisfy { value in
            !value.contains(",") && value.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil
        }
    }

    // MARK: - CSV

    /// RFC 4180 rows, with the delimiter (comma, semicolon or tab) taken from
    /// the file itself.
    static func rows(from text: String) -> [[String]] {
        let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let delimiter = detectDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character? = nil
        while let char = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"" where field.isEmpty:
                quoted = true
            case delimiter:
                row.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default:
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func detectDelimiter(_ text: String) -> Character {
        let lines = text.split(whereSeparator: \.isNewline).prefix(20)
        let candidates: [Character] = [",", ";", "\t"]
        return candidates.max { lhs, rhs in
            lines.map { $0.filter { $0 == lhs }.count }.reduce(0, +) < lines.map { $0.filter { $0 == rhs }.count }.reduce(0, +)
        } ?? ","
    }

    // MARK: - Dates

    /// Picks one format for a whole column, so 03/04 means the same thing on
    /// every row: whichever format reads the most values, with the region's
    /// day/month order breaking ties.
    struct DateColumn {
        private let formatter: DateFormatter?

        private static let formats = [
            "yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "M/d/yyyy", "M/d/yy", "d/M/yyyy", "d/M/yy", "d.M.yyyy", "d.M.yy",
            "M-d-yyyy", "d-M-yyyy", "MMM d, yyyy", "MMMM d, yyyy", "MMM d yyyy", "d MMM yyyy", "d MMMM yyyy", "d-MMM-yyyy",
            "d-MMM-yy", "yyyyMMdd",
        ]

        init(values: [String], locale: Locale) {
            let samples = values.map(Self.datePart).filter { !$0.isEmpty }.prefix(400)
            let dayFirst = Self.prefersDayFirst(locale)
            var best: (formatter: DateFormatter, score: Int, rank: Int)?
            for (rank, format) in Self.formats.enumerated() {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = .current
                formatter.dateFormat = format
                formatter.isLenient = false
                let score = samples.filter { Self.plausible(formatter.date(from: $0)) }.count
                guard score > 0 else { continue }
                let localRank = dayFirst && format.hasPrefix("d") ? rank - 100 : rank
                if best == nil || score > best!.score || (score == best!.score && localRank < best!.rank) {
                    best = (formatter, score, localRank)
                }
            }
            formatter = best?.formatter
        }

        func date(from value: String) -> Date? {
            guard let formatter, let date = formatter.date(from: Self.datePart(value)), Self.plausible(date) else { return nil }
            // Noon keeps a date on the same day in every time zone the family is in.
            return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date)
        }

        private static func plausible(_ date: Date?) -> Bool {
            guard let date else { return false }
            let year = Calendar(identifier: .gregorian).component(.year, from: date)
            return year >= 1950 && date < .now.addingTimeInterval(2 * 86_400)
        }

        /// Drops a trailing time: "2024-03-01 14:05", "2024-03-01T14:05:00Z".
        private static func datePart(_ value: String) -> String {
            var text = value.trimmed
            if let range = text.range(of: #"(T|\s)\d{1,2}:\d{2}.*$"#, options: .regularExpression) {
                text.removeSubrange(range)
            }
            return text.trimmed
        }

        private static func prefersDayFirst(_ locale: Locale) -> Bool {
            let pattern = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "M/d/y"
            guard let day = pattern.firstIndex(of: "d"), let month = pattern.firstIndex(of: "M") else { return false }
            return day < month
        }
    }

    // MARK: - Matching the schedule

    /// The catalog jobs a line of work names, most specific first, so "gear
    /// oil" never restarts the engine oil countdown.
    static func catalogKeys(for work: String) -> [String] {
        var text = " " + work.lowercased() + " "
        var keys: [String] = []
        for (patterns, matched) in rules {
            var hit = false
            for pattern in patterns where text.contains(pattern) {
                hit = true
                text = text.replacingOccurrences(of: pattern, with: " ")
            }
            if hit { keys.append(contentsOf: matched.filter { !keys.contains($0) }) }
        }
        return keys
    }

    private static let rules: [([String], [String])] = [
        (["gear oil", "lower unit", "gearcase", "gear case"], ["gearOil", "diffs"]),
        (["fork oil", "fork seal"], ["forks"]),
        (["chaincase", "chain case"], ["chaincase"]),
        (["transmission fluid", "transmission oil", "transmission service", "transmission", "trans fluid", " atf", "cvt fluid"],
         ["transmission", "transmissionFluid", "hydraulic"]),
        (["differential", "diff fluid", "diff oil"], ["diffs"]),
        (["brake fluid"], ["brakeFluid"]),
        (["oil leak", "oil pressure", "oil pan", "oil sensor"], []),
        (["brake pad", "brake job", "rotors", "brakes", "brake"], ["brakes"]),
        (["cabin"], ["cabinFilter"]),
        (["air filter", "engine filter", "air cleaner"], ["airFilter"]),
        (["fuel filter"], ["fuelFilter"]),
        (["fuel/water", "water separator"], ["fuelSeparator"]),
        (["rotation", "rotate"], ["rotate"]),
        (["alignment"], ["alignment"]),
        (["new tires", "tire replacement", "replace tires", "replaced tires", "mount and balance", "tires installed"], ["tires"]),
        (["wiper"], ["wipers"]),
        (["coolant", "antifreeze", "radiator flush"], ["coolant"]),
        (["spark plug", "plugs"], ["plugs"]),
        (["battery"], ["battery", "battery12v", "boatBattery"]),
        (["annual inspection", "annual"], ["annual"]),
        (["smog", "emissions", "state inspection", "safety inspection"], ["inspection"]),
        (["registration", "tabs"], ["registration"]),
        (["impeller"], ["impeller"]),
        (["winteriz", "layup"], ["winterize"]),
        (["timing belt", "serpentine", "drive belt", "cvt belt"], ["belt", "cvt"]),
        (["chain"], ["chain"]),
        (["tune-up", "tune up", "tuneup"], ["tune"]),
        (["diesel exhaust", " def "], ["def"]),
        (["grease", "lube chassis", "chassis lube"], ["grease"]),
        (["valve"], ["valves"]),
        (["anode", "zinc"], ["anodes"]),
        (["generator"], ["generator"]),
        (["oil change", "oil and filter", "oil & filter", "oil/filter", "lube oil", " lof ", "oil service", "synthetic oil",
          "engine oil", " oil"], ["oil"]),
    ]
}
