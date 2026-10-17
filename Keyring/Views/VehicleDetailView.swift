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
    @State private var importing = false
    @State private var storing = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                hero
                actions
                if vehicle.isRetired { retiredNote } else if vehicle.storedSince != nil { storedNote }
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
        .sheet(isPresented: $importing) { ImportView(preselected: vehicle) }
        .sheet(isPresented: $storing) { StorageSheet(vehicle: vehicle) }
        .task(id: vehicle.objectID) {
            if !routed, let route = ScreenshotConfig.value(after: "-ScreenshotRoute") {
                routed = true
                if route == "record" { showingRecord = true }
                if route == "explore" {
                    try? await Task.sleep(for: .milliseconds(300))
                    proxy.scrollTo("explore", anchor: .top)
                }
            }
            if recalls.isEmpty, let cached = RecallWatcher.cached(for: vehicle) { recalls = cached }
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

    private var retiredText: String {
        guard let sold = vehicle.soldDate else { return "Retired. Its history is kept and reminders are off." }
        let price = vehicle.soldPrice > 0 && !AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts) ? " for \(Format.money(vehicle.soldPrice))" : ""
        return "Sold \(Format.shortDate(sold))\(price). Its history is kept and reminders are off."
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
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.sm))
            : AnyLayout(HStackLayout(spacing: Theme.sm))
        return layout {
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
                        Text(vehicle.reading > 0 ? Format.reading(vehicle.reading, vehicle.meter) : "\(vehicle.meter.meterName) not set")
                            .font(Theme.figure(16))
                            .multilineTextAlignment(.center)
                        Text(vehicle.reading > 0 ? "Update" : "Add")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel(vehicle.reading > 0 ? "\(vehicle.meter.meterName) \(Format.reading(vehicle.reading, vehicle.meter)). Update" : "\(vehicle.meter.meterName) not set. Add")
            }
        }
    }

    private var retiredNote: some View {
        HStack {
            Text(retiredText)
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

    private var storedNote: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Label {
                Text(storedText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "moon.zzz.fill").foregroundStyle(Theme.brass)
            }
            Button("Back on the road") { storing = true }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("vehicle.unstore")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var storedText: String {
        let since = vehicle.storedSince.map { " since \(Format.shortDate($0))" } ?? ""
        let until = vehicle.storedUntil.map { "You'll get a nudge \(Format.shortDate($0))." } ?? "Its reminders are paused."
        return "In storage\(since). \(until)"
    }

    // MARK: - Recalls

    @ViewBuilder
    private var recallBanner: some View {
        let open = garage.openRecalls(recalls, for: vehicle)
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
                        Text(open.contains { $0.parkIt } ? "NHTSA says not to drive it until it's fixed. Check your VIN to see if yours is affected." : "NHTSA lists these for the \(vehicle.descriptor). Check your VIN, then log the fix.")
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
            RecallWatcher.record(recalls, for: vehicle)
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
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())]
                      : [GridItem(.flexible(), spacing: Theme.sm), GridItem(.flexible(), spacing: Theme.sm)], spacing: Theme.sm) {
                tile("What it's worth", detail: valueDetail, symbol: "dollarsign.circle.fill") { ValueView(vehicle: vehicle) }
                tile("Parts and tools", detail: "For what's due next", symbol: "wrench.and.screwdriver.fill") { GearView(vehicle: vehicle) }
                tile("Upgrades", detail: "Popular add-ons", symbol: "sparkles") { UpgradesView(vehicle: vehicle) }
                tile("Clubs", detail: "Owners like you", symbol: "person.3.fill") { ClubsView(vehicle: vehicle) }
                tile("Photos", detail: "Others like it", symbol: "photo.on.rectangle.angled") { GalleryView(vehicle: vehicle) }
                if vehicle.kind.hasNHTSARecords {
                    tile(RecallRegion.isUS ? "Recalls" : "US recalls", detail: recallDetail, symbol: "exclamationmark.shield.fill") { RecallsView(vehicle: vehicle, recalls: recalls) }
                }
                if !insightsSpansRow {
                    tile("Insights", detail: "Where the money goes", symbol: "chart.bar.fill") { InsightsView(vehicles: [vehicle]) }
                }
            }
            if insightsSpansRow {
                wideTile("Insights", detail: "Where the money goes", symbol: "chart.bar.fill") { InsightsView(vehicles: [vehicle]) }
            }
        }
    }

    /// Seven tiles leave Insights alone in the last row of two, so it takes the full width instead.
    private var insightsSpansRow: Bool {
        vehicle.kind.hasNHTSARecords && !dynamicTypeSize.isAccessibilitySize
    }

    private var valueDetail: String {
        if let latest = (vehicle.valuations ?? []).max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) {
            return "Last noted \(Format.money(latest.amount))"
        }
        let isRoad = [.car, .truck, .suv, .van].contains(vehicle.kind)
        if isRoad, let first = ValueSource.sources(for: vehicle).first { return "\(first.name) and more" }
        return "Price guides"
    }

    private var recallDetail: String {
        guard vehicle.year > 0, vehicle.make != nil else { return "Add year, make and model" }
        if recalls.isEmpty { return recallsFailed ? "Couldn't check" : "None listed" }
        let open = garage.openRecalls(recalls, for: vehicle).count
        return open == 0 ? "All handled" : Format.count(open, "may apply", "may apply")
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
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .card(padding: Theme.sm)
        }
        .buttonStyle(PressableStyle())
    }

    private func wideTile<Destination: View>(_ title: String, detail: String, symbol: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: Theme.sm) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.brass)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.faintInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                VStack(alignment: .leading, spacing: Theme.sm) {
                    Text("Nothing logged yet. Log a job and it shows here, signed with your name for the rest of the family.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                    if !vehicle.isRetired {
                        Button { importing = true } label: {
                            Label("Import from another app", systemImage: "tray.and.arrow.down")
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityIdentifier("vehicle.import")
                    }
                }
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
                if vehicle.hasAuxMeter {
                    Button { updatingReading = true } label: {
                        detailRow("\(vehicle.auxMeterName ?? "Second meter") hours", Format.reading(vehicle.auxReading, .hours))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Update")
                    Divider().overlay(Theme.hairline)
                }
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

            if !vehicle.isRetired, vehicle.storedSince == nil {
                Button {
                    storing = true
                } label: {
                    Label("Put in storage", systemImage: "moon.zzz")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .font(.subheadline)
                .accessibilityIdentifier("vehicle.store")
            }
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
        .sheet(isPresented: $confirmingRetire) { RetireVehicleSheet(vehicle: vehicle) }
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
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout())
        return layout {
            Text(label).font(.subheadline).foregroundStyle(Theme.secondaryInk)
                .fixedSize(horizontal: !stacked, vertical: stacked)
            if !stacked { Spacer(minLength: Theme.sm) }
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .multilineTextAlignment(stacked ? .leading : .trailing)
                .lineLimit(stacked ? 4 : 1)
                .minimumScaleFactor(stacked ? 1 : 0.6)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: due.symbol)
                .font(.body)
                .foregroundStyle(due.result.status.color)
                .frame(width: 32, height: 32)
                .background(due.result.status.color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                layout {
                    Text(due.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.xs) }
                    if due.result.status != .ok {
                        Text(due.result.status.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(due.result.status.color)
                            .fixedSize()
                    }
                }
                Text(due.dueLine())
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
    @State private var auxValue: Double?
    @State private var showingScanner = false
    @State private var confirmingJump = false

    private var readings: [MeterReading] {
        (vehicle.readings ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private var auxName: String { vehicle.auxMeterName ?? "Second meter" }

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
                if vehicle.hasAuxMeter {
                    Section {
                        NumberField(title: NumberField.display(vehicle.auxReading, allowsDecimal: true), value: $auxValue, suffix: "hrs", allowsDecimal: true)
                            .font(Theme.figure(28))
                    } header: {
                        Text("\(auxName) hours")
                    } footer: {
                        Text("Last updated \(vehicle.auxReadingDate.map { Format.relative($0) } ?? "never").")
                    }
                }
                if !readings.isEmpty {
                    Section {
                        ForEach(readings.prefix(12)) { reading in
                            HStack {
                                Text(reading.isAux ? "\(auxName) \(Format.reading(reading.value, .hours))" : Format.reading(reading.value, vehicle.meter))
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
            .fittedSheet(expandable: true)
            .navigationTitle("Update \(vehicle.meter.meterName.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let value else { return saveAux() }
                        if garage.isSuspiciousJump(value, for: vehicle) {
                            confirmingJump = true
                        } else {
                            commit(value)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(value == nil && auxValue == nil)
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
    }

    private func commit(_ value: Double) {
        garage.updateReading(vehicle, to: value)
        saveAux()
    }

    private func saveAux() {
        if let auxValue { garage.updateAuxReading(vehicle, to: auxValue) }
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

/// Sold or retired. A sale keeps its date and price, then offers the
/// history to hand the buyer.
struct RetireVehicleSheet: View {
    @EnvironmentObject private var garage: GarageStore
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vehicle: Vehicle

    @State private var sold = true
    @State private var date = Date.now
    @State private var price: Double?
    @State private var handingOver = false
    @State private var showingRecord = false
    @State private var showingPaywall = false
    @State private var exportFile: SharedFile?

    var body: some View {
        NavigationStack {
            Group {
                if handingOver { handover } else { form }
            }
            .paperBackground()
            .navigationTitle(handingOver ? "Sold" : vehicle.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !handingOver {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
            .sheet(isPresented: $showingRecord) { ServiceRecordView(vehicle: vehicle) }
            .sheet(isPresented: $showingPaywall) { PaywallView(focus: .serviceRecord) }
            .sheet(item: $exportFile) { file in ShareSheet(items: [file.url]) }
        }
        .interactiveDismissDisabled(handingOver)
    }

    private var form: some View {
        Form {
            Section {
                Picker("What happened", selection: $sold) {
                    Text("Sold").tag(true)
                    Text("Retired").tag(false)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if sold {
                Section {
                    DatePicker("Sold on", selection: $date, in: ...Date.now, displayedComponents: .date)
                    LabeledContent("Price (optional)") {
                        NumberField(title: "0", value: $price, isCurrency: true)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Kept with its history, so you know what it cost to own.")
                }
            }
            Section {
                Button(sold ? "Mark sold" : "Retire") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("retire.save")
            } footer: {
                Text("Its history stays, reminders stop, and it no longer counts toward the free limit. Restore it any time from Sold and retired.")
            }
        }
    }

    private var handover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                Image(systemName: "key.horizontal.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.brass)
                    .padding(.top, Theme.lg)
                Text("Hand over its history").font(Theme.title(28)).foregroundStyle(Theme.ink)
                Text("A clean record of every job helps the buyer trust the price.")
                    .foregroundStyle(Theme.secondaryInk)
                VStack(spacing: Theme.sm) {
                    Button {
                        if store.isPro { showingRecord = true } else { showingPaywall = true }
                    } label: {
                        Label("Service Record (PDF)", systemImage: "doc.richtext")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("retire.record")
                    Button {
                        if let url = try? CSVExport.url(for: [vehicle], name: "\(vehicle.displayName) service log") { exportFile = SharedFile(url: url) }
                    } label: {
                        Label("Spreadsheet (CSV)", systemImage: "tablecells")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                Button("Done") { dismiss() }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.sm)
                    .accessibilityIdentifier("retire.done")
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.xl)
        }
    }

    private func save() {
        Haptics.success()
        if sold {
            garage.markSold(vehicle, on: date, price: price)
            withAnimation(.snappy) { handingOver = true }
        } else {
            garage.retire(vehicle, true)
            dismiss()
        }
    }
}
