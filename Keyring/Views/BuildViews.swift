import Charts
import SwiftUI
import UniformTypeIdentifiers

/// A file picked from Files, read while its security scope is open.
enum PickedFile {
    /// Big enough for a scanned title or a long dealer invoice, small enough
    /// to sync.
    static let maxBytes = 25_000_000

    static func read(_ url: URL) -> (name: String, data: Data)? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count <= maxBytes else { return nil }
        return (url.deletingPathExtension().lastPathComponent, data)
    }
}

// MARK: - Parts and measurements

/// Parts with numbers and prices, and the figures worth keeping (torque,
/// pressures, an oil analysis). Collapsed to two buttons until used.
struct PartsSection: View {
    @Binding var parts: [EntryPart]
    @Binding var specs: [EntrySpec]
    @Binding var cost: Double?
    @FocusState private var focus: UUID?

    var body: some View {
        Section {
            ForEach($parts) { $part in
                VStack(alignment: .leading, spacing: Theme.xs) {
                    HStack {
                        TextField("Part", text: $part.name)
                            .font(.body.weight(.medium))
                            .focused($focus, equals: part.id)
                        ScanFieldButton(kind: .text) { part.name = $0 }
                    }
                    HStack(spacing: Theme.sm) {
                        TextField("Brand", text: $part.brand)
                        TextField("Part number", text: $part.number)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                    .font(.subheadline)
                    HStack(spacing: Theme.sm) {
                        NumberField(title: "Qty 1", value: $part.quantity, allowsDecimal: true)
                            .frame(maxWidth: 90)
                        NumberField(title: "Price each", value: $part.price, isCurrency: true)
                    }
                    .font(.subheadline)
                }
                .padding(.vertical, 2)
            }
            .onDelete { parts.remove(atOffsets: $0) }
            Button {
                let part = EntryPart()
                parts.append(part)
                focus = part.id
            } label: {
                Label(parts.isEmpty ? "Add parts" : "Add another part", systemImage: "shippingbox")
            }
            .accessibilityIdentifier("log.addPart")
            if let total = partsTotal, total > 0, (cost ?? 0) == 0 {
                Button("Use \(Format.money(total)) as the cost") { cost = total }
            }

            ForEach($specs) { $spec in
                HStack(spacing: Theme.sm) {
                    TextField("Measurement", text: $spec.name)
                        .focused($focus, equals: spec.id)
                    TextField("Value", text: $spec.value)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                    TextField("Unit", text: $spec.unit)
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(maxWidth: 56)
                }
            }
            .onDelete { specs.remove(atOffsets: $0) }
            Menu {
                let used = Set(specs.map { $0.name.lowercased() })
                ForEach(EntrySpec.suggestions.filter { !used.contains($0.name.lowercased()) }, id: \.name) { suggestion in
                    Button(suggestion.name) { addSpec(suggestion.name, unit: suggestion.unit) }
                }
                Button("Something else") { addSpec("", unit: "") }
            } label: {
                Label(specs.isEmpty ? "Add measurements" : "Add another measurement", systemImage: "ruler")
            }
            .accessibilityIdentifier("log.addSpec")
        } header: {
            Text("Parts and specs")
        } footer: {
            if !specs.isEmpty {
                Text("Log a measurement under the same name next time and it charts as a trend.")
            }
        }
    }

    private var partsTotal: Double? {
        EntryDetails(parts: parts).partsTotal
    }

    private func addSpec(_ name: String, unit: String) {
        let spec = EntrySpec(name: name, unit: unit)
        specs.append(spec)
        if name.isEmpty { focus = spec.id }
    }
}

/// Parts and measurements on an entry's page.
struct EntryDetailsCards: View {
    let details: EntryDetails
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if !details.parts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.stackGap) {
                SectionHeader(title: "Parts")
                VStack(spacing: 0) {
                    ForEach(Array(details.parts.enumerated()), id: \.element.id) { index, part in
                        if index > 0 { Divider().overlay(Theme.hairline) }
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text([part.brand, part.name].map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " "))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                if !part.number.trimmed.isEmpty {
                                    Text(part.number)
                                        .font(.footnote.monospaced())
                                        .foregroundStyle(Theme.secondaryInk)
                                        .textSelection(.enabled)
                                }
                            }
                            Spacer(minLength: Theme.sm)
                            VStack(alignment: .trailing, spacing: 2) {
                                if let total = part.lineTotal, !hideCosts {
                                    Text(Format.money(total)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.ink)
                                }
                                if let quantity = part.quantity, quantity != 1 {
                                    Text("× \(Format.number(quantity))").font(.caption).foregroundStyle(Theme.secondaryInk)
                                }
                            }
                        }
                        .cardRow()
                    }
                }
                .listCard()
            }
        }
        if !details.specs.isEmpty {
            VStack(alignment: .leading, spacing: Theme.stackGap) {
                SectionHeader(title: "Measurements")
                VStack(spacing: 0) {
                    ForEach(Array(details.specs.enumerated()), id: \.element.id) { index, spec in
                        if index > 0 { Divider().overlay(Theme.hairline) }
                        HStack {
                            Text(spec.name).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                            Spacer(minLength: Theme.sm)
                            Text(spec.display).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.ink)
                        }
                        .cardRow()
                    }
                }
                .listCard()
            }
        }
    }

    private var hideCosts: Bool { AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts) }
}

// MARK: - Events

/// A track day, a river crossing, a dusty trail: logged in two taps, and the
/// jobs it brings due show right away. A future date plans for it.
struct LogEventSheet: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    var editing: ServiceEntry?

    @State private var event: UsageEvent = .trackDay
    @State private var date = Date.now
    @State private var notes = ""
    @State private var loaded = false

    private var choices: [UsageEvent] { UsageEvent.choices(for: vehicle.kind) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("What happened", selection: $event) {
                        ForEach(choices) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Track, trail or notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                } footer: {
                    Text(date > .now ? "Coming up: its jobs come due by then." : "Its jobs come due now.")
                }
                Section {
                    let jobs = garage.jobs(triggeredBy: event, on: vehicle)
                    if jobs.isEmpty {
                        Text("No jobs follow a \(event.title.lowercased()) yet. Set one in a job's schedule, such as brake fluid every track day.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                    } else {
                        ForEach(jobs) { task in
                            Label(task.displayName, systemImage: task.displaySymbol).foregroundStyle(Theme.ink)
                        }
                    }
                } header: {
                    Text("Brings due")
                }
                if let editing {
                    Section {
                        Button("Delete event", role: .destructive) {
                            garage.delete(editing)
                            dismiss()
                        }
                    }
                }
            }
            .paperBackground()
            .navigationTitle(editing == nil ? "Log an event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).accessibilityIdentifier("event.save")
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        event = choices.first ?? .waterCrossing
        if let editing {
            event = editing.details.event ?? event
            date = editing.date ?? .now
            notes = editing.notes ?? ""
        }
    }

    private func save() {
        var draft = GarageStore.ServiceDraft()
        draft.kind = .event
        draft.date = date
        draft.notes = notes
        draft.details.event = event
        if let editing {
            draft.reading = editing.hasReading ? vehicle.shownReading(true: editing.reading, on: editing.date ?? .now) : nil
        }
        garage.log(draft, for: vehicle, editing: editing)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Build list

/// Every mod on the vehicle: what went on, when, what it cost, and what came
/// off since. The build thread in one list.
struct BuildListView: View {
    @EnvironmentObject private var garage: GarageStore
    @ObservedObject var vehicle: Vehicle
    @State private var logging = false

    private var mods: [ServiceEntry] { vehicle.sortedEntries.filter { $0.kind == .mod } }

    var body: some View {
        let installed = mods.filter { $0.details.removedOn == nil }
        let removed = mods.filter { $0.details.removedOn != nil }
        List {
            if mods.isEmpty {
                Section {
                    Text("Log a mod and it lands here with its parts, cost and install date. Mods stay out of what it costs to keep running.")
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            if !installed.isEmpty {
                Section {
                    ForEach(installed) { row($0) }
                } header: {
                    Text("On the \(vehicle.kind.title.lowercased())")
                } footer: {
                    if total(installed) > 0, !hideCosts { Text("\(Format.money(total(installed))) in mods on it now.") }
                }
            }
            if !removed.isEmpty {
                Section("Came off") { ForEach(removed) { row($0) } }
            }
        }
        .paperBackground()
        .navigationTitle("Build")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { logging = true } label: { Label("Log a mod", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $logging) { LogServiceView(vehicle: vehicle, startingKind: .mod) }
    }

    private func row(_ entry: ServiceEntry) -> some View {
        NavigationLink { EntryDetailView(entry: entry) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title ?? "Mod").font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                    Spacer()
                    if entry.cost > 0, !hideCosts {
                        Text(Format.money(entry.cost)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondaryInk)
                    }
                }
                Text(subtitle(entry)).font(.footnote).foregroundStyle(Theme.secondaryInk)
            }
        }
        .swipeActions {
            if entry.details.removedOn == nil {
                Button("Came off") { garage.setRemoved(entry, on: .now) }.tint(Theme.brass)
            } else {
                Button("Back on") { garage.setRemoved(entry, on: nil) }.tint(Theme.brass)
            }
        }
    }

    private func subtitle(_ entry: ServiceEntry) -> String {
        var parts: [String] = []
        if let date = entry.date { parts.append(Format.shortDate(date)) }
        if entry.hasReading { parts.append(Format.reading(entry.reading, vehicle.meter)) }
        if let removed = entry.details.removedOn { parts.append("off \(Format.shortDate(removed))") }
        let numbers = entry.details.parts.map(\.number).filter { !$0.trimmed.isEmpty }
        if !numbers.isEmpty { parts.append(numbers.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private func total(_ entries: [ServiceEntry]) -> Double { entries.reduce(0) { $0 + $1.cost } }
    private var hideCosts: Bool { AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts) }
}

// MARK: - Measurements

/// Every figure logged under the same name, charted over time: oil
/// analysis iron creeping up, camber drifting, wheel horsepower after a tune.
struct MeasurementsView: View {
    @ObservedObject var vehicle: Vehicle

    struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let reading: Double?
    }

    static func series(for vehicle: Vehicle) -> [(name: String, unit: String, points: [Point])] {
        var groups: [String: (name: String, unit: String, points: [Point])] = [:]
        for entry in vehicle.sortedEntries {
            guard let date = entry.date else { continue }
            for spec in entry.details.specs {
                guard let value = spec.number else { continue }
                let key = spec.name.trimmed.lowercased()
                var group = groups[key] ?? (spec.name.trimmed, spec.unit.trimmed, [])
                group.points.append(Point(date: date, value: value, reading: entry.hasReading ? entry.reading : nil))
                groups[key] = group
            }
        }
        return groups.values
            .map { ($0.name, $0.unit, $0.points.sorted { $0.date < $1.date }) }
            .sorted { $0.points.count != $1.points.count ? $0.points.count > $1.points.count : $0.name < $1.name }
    }

    var body: some View {
        let series = Self.series(for: vehicle)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionGap) {
                if series.isEmpty {
                    Text("Add a measurement when you log a job (a torque, a pressure, an oil analysis result) and it shows here. Two under the same name make a trend.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                        .card()
                }
                ForEach(series, id: \.name) { item in
                    VStack(alignment: .leading, spacing: Theme.stackGap) {
                        SectionHeader(title: item.name) {
                            if let last = item.points.last {
                                Text([Format.number(last.value), item.unit].filter { !$0.isEmpty }.joined(separator: " "))
                            }
                        }
                        VStack(alignment: .leading, spacing: Theme.sm) {
                            if item.points.count > 1 {
                                Chart(item.points) { point in
                                    LineMark(x: .value("Date", point.date), y: .value(item.name, point.value))
                                        .foregroundStyle(Theme.brass)
                                    PointMark(x: .value("Date", point.date), y: .value(item.name, point.value))
                                        .foregroundStyle(Theme.brass)
                                }
                                .chartYScale(domain: .automatic(includesZero: false))
                                .frame(height: 150)
                            }
                            ForEach(item.points.reversed().prefix(4)) { point in
                                HStack {
                                    Text(Format.shortDate(point.date)).font(.footnote).foregroundStyle(Theme.secondaryInk)
                                    if let reading = point.reading {
                                        Text(Format.reading(reading, vehicle.meter)).font(.footnote).foregroundStyle(Theme.faintInk)
                                    }
                                    Spacer()
                                    Text(Format.number(point.value)).font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.ink)
                                }
                            }
                        }
                        .card()
                    }
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.xxl)
        }
        .paperBackground()
        .navigationTitle("Measurements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Documents

/// Papers kept with the vehicle: title, build sheet, Marti Report or COA,
/// appraisals, window sticker, insurance card.
struct DocumentsView: View {
    @EnvironmentObject private var garage: GarageStore
    @ObservedObject var vehicle: Vehicle
    @State private var importing = false
    @State private var scanning = false
    @State private var viewing: Attachment?
    @State private var renaming: Attachment?
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                if vehicle.sortedDocuments.isEmpty {
                    Text("Keep the title, build sheet, appraisals and window sticker with the vehicle. They sync to everyone who shares the garage.")
                        .foregroundStyle(Theme.secondaryInk)
                }
                ForEach(vehicle.sortedDocuments) { document in
                    Button { viewing = document } label: {
                        HStack(spacing: Theme.sm) {
                            Image(systemName: document.isPDF ? "doc.richtext.fill" : "photo.fill")
                                .foregroundStyle(Theme.brass)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(document.name ?? "Document").foregroundStyle(Theme.ink)
                                Text(document.createdAt.map(Format.shortDate) ?? "").font(.footnote).foregroundStyle(Theme.secondaryInk)
                            }
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { garage.delete(document) }
                        Button("Rename") {
                            newName = document.name ?? ""
                            renaming = document
                        }
                    }
                }
            }
            Section {
                Button { importing = true } label: { Label("Add from Files", systemImage: "folder") }
                if ReceiptScanner.isAvailable {
                    Button { scanning = true } label: { Label("Scan a paper", systemImage: "doc.viewfinder") }
                }
            }
        }
        .paperBackground()
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            guard case let .success(urls) = result else { return }
            for file in urls.compactMap(PickedFile.read) { garage.addDocument(file.name, data: file.data, to: vehicle) }
            Haptics.success()
        }
        .sheet(isPresented: $scanning) {
            ReceiptScanner { images in
                scanning = false
                guard !images.isEmpty, let pdf = DocumentPDF.make(images) else { return }
                garage.addDocument("Scan \(Format.shortDate(.now))", data: pdf, to: vehicle)
                Haptics.success()
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewing) { document in
            AttachmentViewer(attachment: document) { viewing = nil }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") { if let renaming { garage.rename(renaming, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Scanned pages as one PDF, so a multi-page title stays one document.
enum DocumentPDF {
    static func make(_ images: [UIImage]) -> Data? {
        guard let first = images.first else { return nil }
        let width: CGFloat = 612
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: width, height: width * first.size.height / max(first.size.width, 1)))
        return renderer.pdfData { context in
            for image in images {
                let height = width * image.size.height / max(image.size.width, 1)
                let bounds = CGRect(x: 0, y: 0, width: width, height: height)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                image.draw(in: bounds)
            }
        }
    }
}

// MARK: - Odometer

/// The odometer rolled over or was swapped. The app keeps counting the true
/// total, so mileage jobs don't all come due or go quiet.
struct OdometerChangeSheet: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vehicle: Vehicle

    @State private var replaced = false
    @State private var date = Date.now
    @State private var lastShown: Double?
    @State private var newShown: Double?
    @State private var status: MileageStatus = .actual
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("What happened", selection: $replaced) {
                        Text("Rolled over").tag(false)
                        Text("Replaced").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    DatePicker("When", selection: $date, in: ...Date.now, displayedComponents: .date)
                    LabeledContent("It showed before") {
                        NumberField(title: "99,999", value: $lastShown, suffix: vehicle.meter.short)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("It showed after") {
                        NumberField(title: "0", value: $newShown, suffix: vehicle.meter.short)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    if let lastShown, let newShown {
                        Text("The app adds \(Format.reading(lastShown - newShown, vehicle.meter)) to everything the odometer shows from then on. Type what the gauge reads; the true total carries on.")
                    }
                }
                Section {
                    Picker("Mileage", selection: $status) {
                        ForEach(MileageStatus.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text("Printed on the Service Record. Use not actual (TMU) when the true total is unknown.")
                }
                let changes = vehicle.profile.odometerChanges
                if !changes.isEmpty {
                    Section("Earlier changes") {
                        ForEach(changes) { change in
                            HStack {
                                Text(change.replaced ? "Replaced" : "Rolled over")
                                Spacer()
                                Text("\(Format.shortDate(change.date)) · +\(Format.reading(change.offset, vehicle.meter))")
                                    .font(.footnote).foregroundStyle(Theme.secondaryInk)
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) { garage.removeOdometerChange(change, from: vehicle) }
                            }
                        }
                    }
                }
            }
            .paperBackground()
            .navigationTitle("Odometer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                status = vehicle.profile.mileageStatus
                lastShown = vehicle.shownReading > 0 ? vehicle.shownReading : nil
                newShown = 0
            }
        }
    }

    private var hasChange: Bool {
        guard let lastShown, let newShown else { return false }
        return lastShown != newShown
    }

    private var canSave: Bool { hasChange || status != vehicle.profile.mileageStatus }

    private func save() {
        if status != vehicle.profile.mileageStatus { garage.setMileageStatus(status, on: vehicle) }
        if hasChange, let lastShown, let newShown {
            garage.recordOdometerChange(vehicle, on: date, lastShown: lastShown, newShown: newShown, replaced: replaced)
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Trip check

/// Before a long trip: what comes due on the way, by the miles you'll cover
/// and the days you'll be gone.
struct TripCheckView: View {
    @EnvironmentObject private var garage: GarageStore
    @ObservedObject var vehicle: Vehicle
    @State private var distance: Double?
    @State private var days: Double? = 7
    @State private var logging = false
    @State private var preset: [UUID] = []

    var body: some View {
        let dues = garage.dues(for: vehicle)
        let owed = Self.owed(dues, distance: distance ?? 0, days: days ?? 0, current: vehicle.reading)
        List {
            Section {
                if vehicle.meter.hasReading {
                    LabeledContent("Distance") {
                        NumberField(title: "1,500", value: $distance, suffix: vehicle.meter.short)
                            .multilineTextAlignment(.trailing)
                    }
                }
                LabeledContent("Days away") {
                    NumberField(title: "7", value: $days)
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("Includes what's already due and what comes due before you're back.")
            }
            Section {
                if owed.isEmpty {
                    Label("Nothing comes due on this trip.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DueStatus.ok.color)
                } else {
                    ForEach(owed) { due in
                        Button {
                            preset = [due.taskID]
                            logging = true
                        } label: {
                            TaskRow(due: due, vehicle: vehicle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text(owed.isEmpty ? "Ready" : "Do before you go")
            }
        }
        .paperBackground()
        .navigationTitle("Trip check")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $logging) { LogServiceView(vehicle: vehicle, preselected: preset) }
    }

    /// Jobs owed now, due by date before the return, or due by a reading the
    /// trip will pass.
    static func owed(_ dues: [TaskDue], distance: Double, days: Double, current: Double, now: Date = .now) -> [TaskDue] {
        let back = now.addingTimeInterval(max(0, days) * 86_400)
        return dues.filter { due in
            guard due.hasInterval || due.pendingEvent != nil else { return false }
            switch due.result.status {
            case .overdue: return true
            case .noRecord: return false
            default: break
            }
            if let date = due.result.dueDate, date <= back { return true }
            if let reading = due.result.dueReading, !due.usesAuxMeter, distance > 0, reading <= current + distance { return true }
            return false
        }
    }
}
