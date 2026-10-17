import SwiftUI

/// Everything about one vehicle on one scroll: what's due, what was done,
/// the numbers you always look up, and the world around it (value, parts,
/// clubs, photos of others like it).
struct VehicleDetailView: View {
    @EnvironmentObject private var garage: GarageStore
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @ObservedObject var vehicle: Vehicle

    @State private var logging = false
    @State private var logPreset: [UUID] = []
    @State private var updatingReading = false
    @State private var editing = false
    @State private var editingFacts = false
    @State private var showingRecord = false
    @State private var showingPaywall = false
    @State private var showingLimitPaywall = false
    @State private var recalls: [Recall] = []
    @State private var recallsFailed = false
    @State private var confirmingDelete = false
    @State private var confirmingRetire = false
    @State private var routed = false

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                hero
                actions
                if vehicle.isRetired { retiredNote }
                recallBanner
                dueSection
                exploreSection.id("explore")
                historySection
                factsSection
                recordSection
                detailsSection
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.xxl)
        }
        .paperBackground()
        .navigationTitle(vehicle.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $logging) { LogServiceView(vehicle: vehicle, preselected: logPreset) }
        .sheet(isPresented: $updatingReading) { UpdateReadingSheet(vehicle: vehicle) }
        .sheet(isPresented: $editing) { EditVehicleView(vehicle: vehicle) }
        .sheet(isPresented: $editingFacts) { FactsEditor(vehicle: vehicle) }
        .sheet(isPresented: $showingRecord) { ServiceRecordView(vehicle: vehicle) }
        .sheet(isPresented: $showingPaywall) { PaywallView(focus: .serviceRecord) }
        .sheet(isPresented: $showingLimitPaywall) { PaywallView(focus: .unlimitedVehicles) }
        .task(id: vehicle.objectID) {
            if !routed, let route = ScreenshotConfig.value(after: "-ScreenshotRoute") {
                routed = true
                if route == "record" { showingRecord = true }
                if route == "explore" {
                    try? await Task.sleep(for: .milliseconds(300))
                    proxy.scrollTo("explore", anchor: .top)
                }
            }
            await loadRecalls()
            // The recall banner can land above Explore once it loads.
            if ScreenshotConfig.value(after: "-ScreenshotRoute") == "explore" {
                try? await Task.sleep(for: .milliseconds(300))
                proxy.scrollTo("explore", anchor: .top)
            }
        }
        }
        .onChange(of: vehicle.isDeleted) { _, deleted in if deleted { dismiss() } }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            VehicleArt(vehicle: vehicle, cornerRadius: 22, symbolScale: 0.38)
                .frame(height: vehicle.photo == nil ? 150 : 210)
                .overlay(alignment: .topLeading) { KeyTagHole(tint: vehicle.tint).padding(Theme.md) }
            VStack(alignment: .leading, spacing: 2) {
                if !vehicle.descriptor.isEmpty {
                    Eyebrow(text: [vehicle.descriptor, vehicle.trim].compactMap { $0 }.joined(separator: " "))
                }
                Text(vehicle.displayName)
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.ink)
            }
        }
        .padding(.top, Theme.xs)
    }

    private var actions: some View {
        HStack(spacing: Theme.sm) {
            Button {
                Haptics.tap()
                logPreset = []
                logging = true
            } label: {
                Label("Log service", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("vehicle.log")
            if vehicle.meter.hasReading {
                Button {
                    updatingReading = true
                } label: {
                    VStack(spacing: 0) {
                        Text(Format.reading(vehicle.reading, vehicle.meter))
                            .font(Theme.figure(16))
                        Text("Update")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("\(vehicle.meter.meterName) \(Format.reading(vehicle.reading, vehicle.meter)). Update")
            }
        }
    }

    private var retiredNote: some View {
        HStack {
            Text("Retired. Its history is kept and reminders are off.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryInk)
            Spacer()
            if !garage.isShared(vehicle) {
                Button("Restore", action: restore)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .card()
    }

    // MARK: - Recalls

    @ViewBuilder
    private var recallBanner: some View {
        let open = recalls.filter { !RecallLedger.reviewed(for: vehicle.id).contains($0.campaign) }
        if !open.isEmpty {
            NavigationLink {
                RecallsView(vehicle: vehicle, recalls: recalls)
            } label: {
                HStack(spacing: Theme.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.overdue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(open.count == 1 ? "1 safety recall may apply" : "\(open.count) safety recalls may apply")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text("NHTSA lists these for the \(vehicle.descriptor). Check your VIN to see which are open.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.faintInk)
                }
                .card()
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func loadRecalls() async {
        guard vehicle.kind.hasNHTSARecords, vehicle.year > 1980, let make = vehicle.make, let model = vehicle.model else { return }
        do {
            recalls = try await NHTSAClient.recalls(year: Int(vehicle.year), make: make, model: model)
            recallsFailed = false
        } catch {
            recallsFailed = true
        }
    }

    // MARK: - Due

    private var dueSection: some View {
        let dues = garage.dues(for: vehicle)
        return VStack(alignment: .leading, spacing: Theme.sm) {
            NavigationLink {
                ScheduleView(vehicle: vehicle)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Maintenance").font(Theme.title(20)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("Schedule").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.brass)
                }
            }
            .buttonStyle(.plain)
            if dues.isEmpty {
                Text("No jobs on the schedule. Add some from the catalog for this \(vehicle.kind.title.lowercased()).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dues.prefix(6).enumerated()), id: \.element.id) { index, due in
                        if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 44) }
                        NavigationLink {
                            TaskDetailView(vehicle: vehicle, taskID: due.taskID)
                        } label: {
                            TaskRow(due: due, vehicle: vehicle)
                        }
                        .buttonStyle(.plain)
                    }
                    if dues.count > 6 {
                        Divider().overlay(Theme.hairline)
                        NavigationLink {
                            ScheduleView(vehicle: vehicle)
                        } label: {
                            Text("All \(dues.count) jobs")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.brass)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
                .card(padding: Theme.xs)
            }
        }
    }

    // MARK: - Explore

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            SectionHeader(title: "Explore")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.sm), GridItem(.flexible(), spacing: Theme.sm)], spacing: Theme.sm) {
                tile("What it's worth", detail: valueDetail, symbol: "dollarsign.circle.fill") { ValueView(vehicle: vehicle) }
                tile("Parts and tools", detail: "For what's due next", symbol: "wrench.and.screwdriver.fill") { GearView(vehicle: vehicle) }
                tile("Upgrades", detail: "Popular add-ons", symbol: "sparkles") { UpgradesView(vehicle: vehicle) }
                tile("Clubs", detail: "Owners like you", symbol: "person.3.fill") { ClubsView(vehicle: vehicle) }
                tile("Photos", detail: "Others like it", symbol: "photo.on.rectangle.angled") { GalleryView(vehicle: vehicle) }
                if vehicle.kind.hasNHTSARecords {
                    tile("Recalls", detail: recallDetail, symbol: "exclamationmark.shield.fill") { RecallsView(vehicle: vehicle, recalls: recalls) }
                } else {
                    tile("Insights", detail: "Where the money goes", symbol: "chart.bar.fill") { InsightsView(vehicles: [vehicle]) }
                }
            }
        }
    }

    private var valueDetail: String {
        if let latest = (vehicle.valuations ?? []).max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) {
            return "Last noted \(Format.money(latest.amount))"
        }
        return vehicle.kind == .car || vehicle.kind == .truck || vehicle.kind == .suv || vehicle.kind == .van ? "Kelley Blue Book and more" : "Price guides"
    }

    private var recallDetail: String {
        guard vehicle.year > 0, vehicle.make != nil else { return "Add year, make and model" }
        if recalls.isEmpty { return recallsFailed ? "Couldn't check" : "None listed" }
        return Format.count(recalls.count, "may apply", "may apply")
    }

    private func tile<Destination: View>(_ title: String, detail: String, symbol: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: Theme.xs) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.brass)
                Spacer(minLength: 0)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .card(padding: Theme.sm)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - History

    private var historySection: some View {
        let entries = vehicle.sortedEntries
        return VStack(alignment: .leading, spacing: Theme.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("History").font(Theme.title(20)).foregroundStyle(Theme.ink)
                Spacer()
                if entries.count > 3 {
                    NavigationLink("All \(entries.count)") { VehicleHistoryView(vehicle: vehicle) }
                        .font(.subheadline.weight(.semibold))
                }
            }
            if entries.isEmpty {
                Text("Nothing logged yet. Log a job and it shows here, signed with your name for the rest of the family.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.prefix(3).enumerated()), id: \.element.objectID) { index, entry in
                        if index > 0 { Divider().overlay(Theme.hairline) }
                        NavigationLink {
                            EntryDetailView(entry: entry)
                        } label: {
                            EntryRow(entry: entry, showsVehicle: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(padding: Theme.sm)
            }
        }
    }

    // MARK: - Facts

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            SectionHeader(title: "Quick facts", trailing: vehicle.facts.isEmpty ? "Add" : "Edit") { editingFacts = true }
            if vehicle.facts.isEmpty {
                Button { editingFacts = true } label: {
                    Text("Oil type, tire size, wiper lengths, paint code. Save the things you look up every time.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                        .multilineTextAlignment(.leading)
                        .card()
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(vehicle.facts.enumerated()), id: \.element.id) { index, fact in
                        if index > 0 { Divider().overlay(Theme.hairline) }
                        HStack(alignment: .firstTextBaseline) {
                            Text(fact.label).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                                .fixedSize()
                            Spacer(minLength: Theme.md)
                            Text(fact.value)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 10)
                    }
                }
                .card(padding: Theme.md)
            }
        }
    }

    // MARK: - Record

    private var recordSection: some View {
        Button {
            Haptics.tap()
            if store.isPro { showingRecord = true } else { showingPaywall = true }
        } label: {
            HStack(spacing: Theme.sm) {
                Image(systemName: "doc.richtext.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.brass)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Service Record")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("A clean PDF of every job, for a buyer, a shop or the glovebox")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if !store.isPro {
                    Image(systemName: "lock.fill").font(.footnote).foregroundStyle(Theme.faintInk)
                } else {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.faintInk)
                }
            }
            .card()
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("vehicle.record")
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            SectionHeader(title: "Details")
            VStack(spacing: 0) {
                if let vin = vehicle.vin {
                    detailRow(vehicle.kind.identifierLabel, vin, copyable: true)
                    Divider().overlay(Theme.hairline)
                }
                if let plate = vehicle.plate {
                    detailRow(vehicle.kind.registrationLabel, plate, copyable: true)
                    Divider().overlay(Theme.hairline)
                }
                detailRow("Powertrain", vehicle.powertrain.title)
                Divider().overlay(Theme.hairline)
                if let garageName = vehicle.garage?.displayName {
                    detailRow("Garage", garage.isShared(vehicle) ? "\(garageName) (shared with you)" : garageName)
                    Divider().overlay(Theme.hairline)
                }
                Toggle(isOn: Binding(
                    get: { !ReminderScheduler.shared.mutedVehicleIDs.contains(vehicle.id?.uuidString ?? "") },
                    set: { ReminderScheduler.shared.setMuted(!$0, vehicleID: vehicle.id, store: garage) }
                )) {
                    Text("Reminders on this iPhone").font(.subheadline)
                }
                .padding(.vertical, 6)
            }
            .card(padding: Theme.md)

            if garage.isShared(vehicle) {
                Text("Shared with you. Only the owner can retire or delete it.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
            } else {
                HStack(spacing: Theme.sm) {
                    Button(vehicle.isRetired ? "Restore vehicle" : "Sold or retired") {
                        if vehicle.isRetired { restore() } else { confirmingRetire = true }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Delete", role: .destructive) { confirmingDelete = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .font(.subheadline)
            }
        }
        .confirmationDialog("Mark \(vehicle.displayName) sold or retired?", isPresented: $confirmingRetire, titleVisibility: .visible) {
                Button("Sold or retired") {
                    garage.retire(vehicle, true)
                    dismiss()
                }
            } message: {
                Text("Its history is kept and its reminders stop. You can restore it from Sold and retired at the bottom of the garage.")
            }
            .confirmationDialog("Delete \(vehicle.displayName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete vehicle and history", role: .destructive) {
                    garage.delete(vehicle)
                    dismiss()
                }
            } message: {
                Text("Its whole history, photos and receipts are deleted for everyone it's shared with. To keep the history, mark it sold or retired instead.")
            }
    }

    private func restore() {
        if !store.isPro, garage.ownedVehicleCount >= ProFeature.freeVehicleLimit {
            showingLimitPaywall = true
        } else {
            garage.retire(vehicle, false)
        }
    }

    private func detailRow(_ label: String, _ value: String, copyable: Bool = false) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                .fixedSize()
            Spacer(minLength: Theme.sm)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if copyable {
                Button {
                    UIPasteboard.general.string = value
                    Haptics.success()
                } label: {
                    Image(systemName: "doc.on.doc").font(.footnote)
                }
                .accessibilityLabel("Copy \(label)")
            }
        }
        .padding(.vertical, 10)
    }
}

/// One job with its status, last done and next due.
struct TaskRow: View {
    let due: TaskDue
    let vehicle: Vehicle

    var body: some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: due.symbol)
                .font(.body)
                .foregroundStyle(due.result.status.color)
                .frame(width: 32, height: 32)
                .background(due.result.status.color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(due.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(due.result.status == .ok ? "" : due.result.status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(due.result.status.color)
                }
                Text(due.dueLine(meter: vehicle.meter, current: vehicle.reading))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
                if due.result.status != .noRecord {
                    DueBar(progress: due.result.progress, status: due.result.status)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Theme.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// "What does the odometer say?" with the last reading as a starting point,
/// and the saved readings below so a typo can be removed.
struct UpdateReadingSheet: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vehicle: Vehicle

    @State private var value: Double?
    @State private var showingScanner = false
    @State private var confirmingJump = false

    private var readings: [MeterReading] {
        (vehicle.readings ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NumberField(title: NumberField.display(vehicle.reading, allowsDecimal: vehicle.meter == .hours), value: $value, suffix: vehicle.meter.short, allowsDecimal: vehicle.meter == .hours)
                        .font(Theme.figure(28))
                    if MeterScanner.isAvailable {
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Read it from the dash", systemImage: "camera.viewfinder")
                        }
                    }
                } header: {
                    Text(vehicle.meter.meterName)
                } footer: {
                    if let value, value < vehicle.reading {
                        Text("That's lower than the last reading of \(Format.reading(vehicle.reading, vehicle.meter)). It will be saved as a past reading. To fix a typo, delete the wrong reading below.")
                    } else {
                        Text("Last updated \(vehicle.readingDate.map { Format.relative($0) } ?? "never"). Keyring learns your pace from these and estimates when things come due.")
                    }
                }
                if !readings.isEmpty {
                    Section {
                        ForEach(readings.prefix(12)) { reading in
                            HStack {
                                Text(Format.reading(reading.value, vehicle.meter))
                                    .font(Theme.figure(15, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text(reading.date.map(Format.shortDate) ?? "")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryInk)
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) { garage.delete(reading) }
                            }
                        }
                    } header: {
                        Text("Saved readings")
                    } footer: {
                        Text("Swipe left on a wrong reading to delete it.")
                    }
                }
            }
            .paperBackground()
            .navigationTitle("Update \(vehicle.meter.meterName.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let value else { return }
                        if garage.isSuspiciousJump(value, for: vehicle) {
                            confirmingJump = true
                        } else {
                            commit(value)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(value == nil)
                }
            }
            .confirmationDialog(
                "Save \(Format.reading(value ?? 0, vehicle.meter))?",
                isPresented: $confirmingJump,
                titleVisibility: .visible
            ) {
                Button("Save \(Format.reading(value ?? 0, vehicle.meter))") { commit(value ?? 0) }
                Button("Fix it", role: .cancel) {}
            } message: {
                Text("That's \(Format.reading((value ?? 0) - vehicle.reading, vehicle.meter)) more than last time, which is a lot. Check for an extra digit.")
            }
            .sheet(isPresented: $showingScanner) {
                MeterScanner { scanned in
                    value = scanned
                    showingScanner = false
                }
                .ignoresSafeArea()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func commit(_ value: Double) {
        garage.updateReading(vehicle, to: value)
        Haptics.success()
        dismiss()
    }
}

/// The owner's own quick-reference lines.
struct FactsEditor: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var facts: [VehicleFact] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($facts) { $fact in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Label", text: $fact.label)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.secondaryInk)
                            TextField("Value", text: $fact.value)
                        }
                    }
                    .onDelete { facts.remove(atOffsets: $0) }
                    .onMove { facts.move(fromOffsets: $0, toOffset: $1) }
                }
                Section("Add") {
                    let used = Set(facts.map { $0.label.lowercased() })
                    ForEach(VehicleFact.suggestions.filter { !used.contains($0.lowercased()) }, id: \.self) { label in
                        Button {
                            facts.append(VehicleFact(label: label, value: ""))
                        } label: {
                            Label(label, systemImage: "plus.circle")
                        }
                    }
                    Button {
                        facts.append(VehicleFact(label: "", value: ""))
                    } label: {
                        Label("Something else", systemImage: "plus.circle")
                    }
                }
            }
            .paperBackground()
            .navigationTitle("Quick facts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vehicle.facts = facts
                            .map { VehicleFact(id: $0.id, label: $0.label.trimmed, value: $0.value.trimmed) }
                            .filter { !$0.label.isEmpty && !$0.value.isEmpty }
                        garage.saveVehicleEdits()
                        dismiss()
                    }
                }
            }
            .onAppear { facts = vehicle.facts }
        }
    }
}
