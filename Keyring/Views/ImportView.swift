import CoreData
import SwiftUI
import UniformTypeIdentifiers

/// Brings a service history over from another app or a spreadsheet.
struct ImportView: View {
    @EnvironmentObject private var garage: GarageStore
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    var preselected: Vehicle?
    /// A file opened from Files, Mail or another app's share sheet.
    var fileURL: URL?

    enum Target: Hashable {
        case unchosen
        case vehicle(NSManagedObjectID)
        case new
        case skip
    }

    @State private var picking = false
    @State private var fileName: String?
    @State private var result: ServiceImport.Result?
    @State private var readError = false
    @State private var targets: [String: Target] = [:]
    @State private var newKinds: [String: VehicleKind] = [:]
    @State private var keepFillUps = true
    @State private var showingColumns = false
    @State private var showingPaywall = false
    @State private var summary: Summary?

    struct Summary {
        var added = 0
        var duplicates = 0
        var readings = 0
        var jobsUpdated = 0
        var vehicles: [String] = []
    }

    var body: some View {
        NavigationStack {
            Group {
                if let summary {
                    done(summary)
                } else if let result, !result.isEmpty {
                    review(result)
                } else {
                    intro
                }
            }
            .paperBackground()
            .navigationTitle("Import history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if summary == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]) { outcome in
                if case let .success(url) = outcome { load(url) }
            }
            .sheet(isPresented: $showingColumns) {
                if let result { ColumnsSheet(result: result) { self.result = $0; assignTargets() } }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView(focus: .unlimitedVehicles) }
            .task {
                if let fileURL, result == nil { load(fileURL) }
            }
        }
    }

    // MARK: - Steps

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.brass)
                    .padding(.top, Theme.lg)
                Text("Bring your history").font(Theme.title(28)).foregroundStyle(Theme.ink)
                Text("Export a spreadsheet (CSV) from Fuelly, Drivvo, Simply Auto, aCar, a Keyring backup or your own sheet, then choose it here.")
                    .foregroundStyle(Theme.secondaryInk)
                VStack(alignment: .leading, spacing: Theme.sm) {
                    bullet("calendar", "Dates, odometer, work, cost, shop and notes come across.")
                    bullet("checklist", "Jobs like oil changes and tire rotations restart their countdowns.")
                    bullet("fuelpump", "Fill-ups aren't logged as services. Their odometer readings teach Keyring how much you drive.")
                    bullet("arrow.triangle.2.circlepath", "Anything already in Keyring is skipped, so importing twice is safe.")
                }
                .card()
                if readError {
                    Label("Keyring couldn't find a date column in \(fileName ?? "that file"). Check it's a CSV export with a header row, or try a different export.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.overdue)
                }
                Button { picking = true } label: { Label(readError ? "Choose another file" : "Choose file", systemImage: "doc") }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("import.choose")
                Text("Look for Export or Backup in the other app's settings and pick CSV. Files from Mail or the Files app work too.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.xl)
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.brass)
        }
    }

    private func review(_ result: ServiceImport.Result) -> some View {
        Form {
            Section {
                LabeledContent("Services", value: result.services.count.formatted())
                if !result.fillUps.isEmpty {
                    Toggle(isOn: $keepFillUps) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep \(Format.count(result.fillUps.count, "fill-up", "fill-ups")) as odometer readings")
                            Text("Teaches Keyring how much you drive. Fuel itself isn't tracked.")
                                .font(.footnote).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                }
                if result.skippedExpenses > 0 {
                    LabeledContent("Skipped expenses", value: result.skippedExpenses.formatted())
                }
                if result.unreadable > 0 {
                    LabeledContent("Rows without a readable date", value: result.unreadable.formatted())
                }
            } header: {
                Text("From \(result.source.rawValue)")
            } footer: {
                if result.skippedExpenses > 0 {
                    Text("Insurance, parking, tolls and other non-maintenance costs stay out of the service log.")
                }
            }

            ForEach(result.vehicleNames, id: \.self) { name in
                vehicleSection(name, result: result)
            }

            Section {
                ForEach(result.services.suffix(6).reversed()) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.work.nilIfEmpty ?? "Service").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Spacer()
                            if row.cost > 0 { Text(Format.money(row.cost)).font(.subheadline).foregroundStyle(Theme.secondaryInk) }
                        }
                        Text([Format.shortDate(row.date), row.reading.map { Int($0).formatted() }].compactMap { $0 }.joined(separator: " · "))
                            .font(.footnote).foregroundStyle(Theme.secondaryInk)
                    }
                }
                Button("Columns look wrong?") { showingColumns = true }
                    .accessibilityIdentifier("import.columns")
            } header: {
                Text(result.services.isEmpty ? "Preview" : "Most recent")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: commit) { Text(importTitle(result)) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canImport(result))
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, Theme.sm)
                .background(Theme.paper)
                .accessibilityIdentifier("import.commit")
        }
    }

    private func vehicleSection(_ name: String, result: ServiceImport.Result) -> some View {
        let rows = result.services.filter { $0.vehicleName == name }
        let fills = result.fillUps.filter { $0.vehicleName == name }
        return Section {
            Picker("Add to", selection: binding(for: name)) {
                if targets[name] == .unchosen { Text("Choose").tag(Target.unchosen) }
                ForEach(garage.vehicles) { vehicle in
                    Text(vehicle.displayName).tag(Target.vehicle(vehicle.objectID))
                }
                Text("A new vehicle").tag(Target.new)
                Text("Don't import").tag(Target.skip)
            }
            if targets[name] == .new {
                Picker("Kind", selection: Binding(get: { newKinds[name] ?? .car }, set: { newKinds[name] = $0 })) {
                    ForEach(VehicleKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
            }
        } header: {
            Text(name.isEmpty ? "Everything in this file" : name)
        } footer: {
            Text([Format.count(rows.count, "service", "services"), fills.isEmpty ? nil : Format.count(fills.count, "fill-up", "fill-ups")]
                .compactMap { $0 }.joined(separator: ", "))
        }
    }

    private func done(_ summary: Summary) -> some View {
        VStack(spacing: Theme.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(Theme.good)
            Text(summary.added == 0 ? "Nothing new to add" : "Imported \(Format.count(summary.added, "service", "services"))")
                .font(Theme.title(26))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            VStack(spacing: Theme.xs) {
                if !summary.vehicles.isEmpty {
                    Text("Into \(ListFormatter.localizedString(byJoining: summary.vehicles)).")
                }
                if summary.jobsUpdated > 0 {
                    Text("\(Format.count(summary.jobsUpdated, "schedule item", "schedule items")) now \(summary.jobsUpdated == 1 ? "knows" : "know") when \(summary.jobsUpdated == 1 ? "it was" : "they were") last done.")
                }
                if summary.readings > 0 {
                    Text("\(Format.count(summary.readings, "odometer reading", "odometer readings")) added.")
                }
                if summary.duplicates > 0 {
                    Text("\(Format.count(summary.duplicates, "entry was", "entries were")) already in Keyring.")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryInk)
            .multilineTextAlignment(.center)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("import.done")
        }
        .padding(Theme.margin)
    }

    // MARK: - Logic

    private func binding(for name: String) -> Binding<Target> {
        Binding(get: { targets[name] ?? .skip }, set: { targets[name] = $0 })
    }

    private func importTitle(_ result: ServiceImport.Result) -> String {
        if targets.values.contains(.unchosen) { return "Choose a vehicle" }
        let names = Set(targets.filter { $0.value != .skip }.map(\.key))
        let services = result.services.filter { names.contains($0.vehicleName) }.count
        if services > 0 { return "Import \(Format.count(services, "service", "services"))" }
        let fills = result.fillUps.filter { names.contains($0.vehicleName) }.count
        return keepFillUps && fills > 0 ? "Import \(Format.count(fills, "reading", "readings"))" : "Import"
    }

    private func canImport(_ result: ServiceImport.Result) -> Bool {
        guard !targets.values.contains(.unchosen) else { return false }
        let names = Set(targets.filter { $0.value != .skip }.map(\.key))
        return result.services.contains { names.contains($0.vehicleName) }
            || (keepFillUps && result.fillUps.contains { names.contains($0.vehicleName) && $0.reading != nil })
    }

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        fileName = url.lastPathComponent
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
            readError = true
            return
        }
        let parsed = ServiceImport.parse(text)
        readError = parsed.isEmpty
        result = parsed.isEmpty ? nil : parsed
        assignTargets()
    }

    /// Sends each vehicle in the file to the matching one in the garage, then
    /// to the vehicle the import started from, then to a new vehicle.
    private func assignTargets() {
        guard let result else { return }
        let names = result.vehicleNames
        for name in names where targets[name] == nil {
            if let match = match(name) {
                targets[name] = .vehicle(match.objectID)
            } else if let preselected, name.isEmpty || names.count == 1 {
                targets[name] = .vehicle(preselected.objectID)
            } else if name.isEmpty, garage.vehicles.count == 1, let only = garage.vehicles.first {
                targets[name] = .vehicle(only.objectID)
            } else if name.isEmpty, !garage.vehicles.isEmpty {
                targets[name] = .unchosen
            } else {
                targets[name] = .new
            }
        }
    }

    private func match(_ name: String) -> Vehicle? {
        let wanted = name.lowercased().trimmed
        guard !wanted.isEmpty else { return nil }
        return garage.vehicles.first { vehicle in
            [vehicle.displayName, vehicle.makeAndModel, vehicle.descriptor, vehicle.nickname ?? ""]
                .map { $0.lowercased() }
                .contains { !$0.isEmpty && ($0 == wanted || wanted.contains($0) || $0.contains(wanted)) }
        }
    }

    private func commit() {
        guard let result else { return }
        let newCount = targets.values.filter { $0 == .new }.count
        if newCount > 0, !store.isPro, garage.ownedVehicleCount + newCount > ProFeature.freeVehicleLimit {
            showingPaywall = true
            return
        }
        var summary = Summary()
        for name in result.vehicleNames {
            let rows = (result.services + result.fillUps).filter { $0.vehicleName == name }
            guard let vehicle = vehicle(for: name, rows: rows) else { continue }
            let outcome = garage.importHistory(rows, into: vehicle, keepFillUps: keepFillUps)
            summary.added += outcome.added
            summary.duplicates += outcome.duplicates
            summary.readings += outcome.readings
            summary.jobsUpdated += outcome.jobsUpdated
            if outcome.added > 0 || outcome.readings > 0, !summary.vehicles.contains(vehicle.displayName) {
                summary.vehicles.append(vehicle.displayName)
            }
        }
        Haptics.success()
        withAnimation(.snappy) { self.summary = summary }
    }

    private func vehicle(for name: String, rows: [ServiceImport.Row]) -> Vehicle? {
        switch targets[name] ?? .skip {
        case .skip, .unchosen:
            return nil
        case let .vehicle(id):
            return garage.vehicles.first { $0.objectID == id }
        case .new:
            let kind = newKinds[name] ?? .car
            var draft = NewVehicle()
            draft.kind = kind
            draft.powertrain = kind.defaultPowertrain
            let unit = rows.compactMap(\.unit).first
            draft.meter = unit ?? (Locale.current.measurementSystem == .metric && kind.defaultMeter == .miles ? .kilometers : kind.defaultMeter)
            draft.nickname = name
            if let details = rows.first(where: { $0.make != nil || $0.model != nil }) {
                draft.year = details.year ?? 0
                draft.make = details.make ?? ""
                draft.model = details.model ?? ""
                if draft.model.lowercased() == name.lowercased() { draft.nickname = "" }
            }
            return garage.addVehicle(draft)
        }
    }
}

/// Points each field at a different column when the guess was wrong.
private struct ColumnsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var result: ServiceImport.Result
    let apply: (ServiceImport.Result) -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let table = result.mainTable {
                    Section {
                        ForEach(ServiceImport.Field.editable) { field in
                            Picker(field.title, selection: Binding(
                                get: { table.mapping[field] ?? -1 },
                                set: { column in
                                    result = ServiceImport.remap(result, table: table.id, field: field, to: column < 0 ? nil : column)
                                }
                            )) {
                                Text("None").tag(-1)
                                ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                                    Text(label(header, sample: table.rows.first.map { index < $0.count ? $0[index] : "" } ?? "")).tag(index)
                                }
                            }
                        }
                    } footer: {
                        Text("\(Format.count(result.services.count, "service", "services")) read with these columns.")
                    }
                }
            }
            .paperBackground()
            .navigationTitle("Columns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { apply(result); dismiss() }
                }
            }
        }
    }

    private func label(_ header: String, sample: String) -> String {
        let sample = sample.trimmed
        return sample.isEmpty ? header : "\(header) (\(sample.prefix(18)))"
    }
}
