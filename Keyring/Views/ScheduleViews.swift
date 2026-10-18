import SwiftUI

/// The vehicle's maintenance plan: what's on it, how often, and the catalog
/// of everything else that applies to this kind of vehicle.
struct ScheduleView: View {
    @EnvironmentObject private var garage: GarageStore
    @ObservedObject var vehicle: Vehicle
    @State private var addingCustom = false

    var body: some View {
        let dues = garage.dues(for: vehicle)
        let enabledKeys = Set(vehicle.enabledTasks.compactMap(\.catalogKey))
        let available = MaintenanceCatalog.items(for: vehicle.kind, powertrain: vehicle.powertrain, year: Int(vehicle.year)).filter { !enabledKeys.contains($0.key) }
        List {
            Section {
                ForEach(dues) { due in
                    NavigationLink {
                        TaskDetailView(vehicle: vehicle, taskID: due.taskID)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                StatusDot(status: due.result.status)
                                Text(due.name).font(.body.weight(.medium))
                            }
                            Text(Format.interval(distance: due.intervalDistance, months: due.intervalMonths, meter: due.meter, auxName: due.usesAuxMeter ? vehicle.auxMeterName : nil))
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryInk)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        if let task = vehicle.enabledTasks.first(where: { $0.id == dues[index].taskID }) { garage.remove(task) }
                    }
                }
            } header: {
                Text("On the schedule")
            } footer: {
                Text("Intervals are typical figures for normal use, not your manufacturer's. Check your owner's manual and change any of them to match.")
            }

            if !available.isEmpty {
                Section("Add from the catalog") {
                    ForEach(available) { item in
                        Button {
                            garage.addCatalogItems([item], to: vehicle)
                            Haptics.success()
                        } label: {
                            HStack(spacing: Theme.sm) {
                                Image(systemName: item.symbol)
                                    .foregroundStyle(Theme.brass)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).foregroundStyle(Theme.ink)
                                    Text(Format.interval(
                                        distance: (vehicle.hasAuxMeter ? item.auxHours : nil) ?? item.distanceInterval(for: vehicle.meter) ?? 0,
                                        months: item.months ?? 0,
                                        meter: vehicle.hasAuxMeter && item.auxHours != nil ? .hours : vehicle.meter,
                                        auxName: vehicle.hasAuxMeter && item.auxHours != nil ? vehicle.auxMeterName : nil
                                    ))
                                        .font(.footnote)
                                        .foregroundStyle(Theme.secondaryInk)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.brass)
                            }
                        }
                        .accessibilityLabel("Add \(item.name)")
                    }
                }
            }

            Section {
                Button { addingCustom = true } label: { Label("Create your own job", systemImage: "plus") }
            }
        }
        .paperBackground()
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $addingCustom) { TaskEditor(vehicle: vehicle, task: nil) }
    }
}

/// One job: why it matters, how often, when it was last done, what it
/// needs, and every time it's been logged.
struct TaskDetailView: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vehicle: Vehicle
    let taskID: UUID

    @State private var logging = false
    @State private var editing = false
    @State private var settingLast = false

    private var task: MaintenanceTask? { (vehicle.tasks ?? []).first { $0.id == taskID } }
    private var item: CatalogItem? { task?.catalogKey.flatMap { MaintenanceCatalog.item(key: $0, kind: vehicle.kind, powertrain: vehicle.powertrain, year: Int(vehicle.year)) } }
    private var due: TaskDue? { garage.dues(for: vehicle).first { $0.taskID == taskID } }

    var body: some View {
        ScrollView {
            if let task {
                VStack(alignment: .leading, spacing: Theme.lg) {
                    header(task)
                    status
                    Button {
                        logging = true
                    } label: {
                        Label("Log \(task.displayName.lowercasedFirst)", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    if !hasLoggedEntry {
                        Button(task.baselineDate == nil ? "Set when it was last done" : "Change when it was last done") { settingLast = true }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    if let gear = item?.gear, !gear.isEmpty { gearSection(gear) }
                    pastSection
                    if let notes = task.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.xs) {
                            SectionHeader(title: "Notes")
                            Text(notes).font(.subheadline).foregroundStyle(Theme.ink).card()
                        }
                    }
                    if let source = item?.source {
                        Text("Interval guidance: \(source). Always defer to your owner's manual.")
                            .font(.caption)
                            .foregroundStyle(Theme.faintInk)
                    }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, Theme.xxl)
            }
        }
        .paperBackground()
        .navigationTitle(task?.displayName ?? "Job")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
        }
        .sheet(isPresented: $logging) { LogServiceView(vehicle: vehicle, preselected: [taskID]) }
        .sheet(isPresented: $editing, onDismiss: {
            // Removed from the schedule in the editor: nothing left to show here.
            if task == nil || task?.isEnabled == false { dismiss() }
        }) { if let task { TaskEditor(vehicle: vehicle, task: task) } }
        .sheet(isPresented: $settingLast) { if let task { LastDoneSheet(vehicle: vehicle, task: task) } }
    }

    private func header(_ task: MaintenanceTask) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Image(systemName: task.displaySymbol)
                .font(.system(size: 28))
                .foregroundStyle(Theme.brass)
                .frame(width: 56, height: 56)
                .background(Theme.brassSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(task.displayName)
                .font(Theme.title(28))
                .foregroundStyle(Theme.ink)
            if let detail = item?.detail(for: vehicle.meter) {
                Text(detail).font(.body).foregroundStyle(Theme.secondaryInk)
            }
            HStack(spacing: Theme.xs) {
                Label(Format.interval(distance: task.intervalDistance, months: Int(task.intervalMonths), meter: task.countingMeter, auxName: task.countsOnAuxMeter ? vehicle.auxMeterName : nil), systemImage: "arrow.clockwise")
                if let difficulty = item?.difficulty {
                    Text("·")
                    Text(difficulty.title)
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.secondaryInk)
        }
        .padding(.top, Theme.sm)
    }

    @ViewBuilder
    private var status: some View {
        if let due {
            VStack(alignment: .leading, spacing: Theme.sm) {
                // An as-needed job (a wash) has no due status, only its last date.
                if due.hasInterval {
                    HStack {
                        Image(systemName: due.result.status.symbol).foregroundStyle(due.result.status.color)
                        Text(due.result.status.label).font(.subheadline.weight(.semibold)).foregroundStyle(due.result.status.color)
                        Spacer()
                    }
                    if due.result.status != .noRecord {
                        DueBar(progress: due.result.progress, status: due.result.status)
                    }
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Eyebrow(text: "Last done")
                        Text(lastText(due)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    if due.hasInterval {
                        VStack(alignment: .trailing, spacing: 2) {
                            Eyebrow(text: "Next")
                            Text(nextText(due))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .card()
        }
    }

    private var hasLoggedEntry: Bool {
        (vehicle.entries ?? []).contains { $0.coveredTaskIDs.contains(taskID) }
    }

    /// A date from setup was a rough answer ("about 6 months ago"), so it shows
    /// as a month, not a made-up day.
    private func lastText(_ due: TaskDue) -> String {
        let date = due.lastDate.map { hasLoggedEntry ? Format.shortDate($0) : "About " + $0.formatted(.dateTime.month(.abbreviated).year()) }
        let parts = [date, due.lastReading.map { Format.reading($0, due.meter) }].compactMap { $0 }
        return parts.isEmpty ? "Not recorded" : parts.joined(separator: " · ")
    }

    /// The exact due date when the calendar sets it (an annual signed off
    /// March 3 shows "Mar 31"), the relative line when the pace estimates it.
    private func nextText(_ due: TaskDue) -> String {
        guard due.result.status != .noRecord else { return "Not set" }
        guard due.result.status != .overdue, let date = due.result.dueDate, !due.result.dateIsEstimated else { return due.dueLine() }
        let day = date.formatted(.dateTime.month(.abbreviated).day().year())
        if let reading = due.result.dueReading, due.meter.hasReading { return "\(day) or \(Format.reading(reading, due.meter))" }
        return day
    }

    private func gearSection(_ gear: [GearSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            SectionHeader(title: "What you'll need")
            VStack(spacing: 0) {
                ForEach(Array(gear.enumerated()), id: \.offset) { index, suggestion in
                    if index > 0 { Divider().overlay(Theme.hairline) }
                    LinkRow(
                        title: suggestion.title,
                        detail: "Search Amazon for \(AmazonLinks.resolve(suggestion.query, vehicle: vehicle))",
                        symbol: "cart",
                        url: AmazonLinks.search(AmazonLinks.resolve(suggestion.query, vehicle: vehicle))
                    )
                    .padding(.vertical, 10)
                }
            }
            .card(padding: Theme.md)
            if AmazonLinks.isAffiliate {
                Text(AmazonLinks.disclosure).font(.caption2).foregroundStyle(Theme.faintInk)
            }
        }
    }

    @ViewBuilder
    private var pastSection: some View {
        let entries = vehicle.sortedEntries.filter { $0.coveredTaskIDs.contains(taskID) }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: Theme.sm) {
                SectionHeader(title: "Done before")
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.objectID) { index, entry in
                        if index > 0 { Divider().overlay(Theme.hairline) }
                        NavigationLink { EntryDetailView(entry: entry) } label: { EntryRow(entry: entry, showsVehicle: false) }
                            .buttonStyle(.plain)
                    }
                }
                .card(padding: Theme.sm)
            }
        }
    }
}

/// Name and interval of a job, new or existing.
struct TaskEditor: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    let task: MaintenanceTask?

    @State private var name = ""
    @State private var distance: Double?
    @State private var months: Double?
    @State private var notes = ""
    @State private var onAuxMeter = false
    @State private var baseline: Snapshot?
    @State private var confirmingDiscard = false
    @State private var confirmingRemove = false

    private struct Snapshot: Equatable {
        var name: String
        var distance: Double?
        var months: Double?
        var notes: String
        var onAuxMeter: Bool
    }

    private var snapshot: Snapshot { Snapshot(name: name, distance: distance, months: months, notes: notes, onAuxMeter: onAuxMeter) }
    private var isDirty: Bool { baseline.map { $0 != snapshot } ?? false }

    private var meter: MeterUnit {
        if let task { return task.countingMeter }
        return onAuxMeter && vehicle.hasAuxMeter ? .hours : vehicle.meter
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    TextField("Name", text: $name)
                    if task == nil, vehicle.hasAuxMeter {
                        Picker("Counts on", selection: $onAuxMeter) {
                            Text(vehicle.meter.meterName).tag(false)
                            Text("\(vehicle.auxMeterName ?? "Second") hours").tag(true)
                        }
                    }
                }
                Section {
                    if meter.hasReading {
                        LabeledContent("Every") {
                            NumberField(title: "None", value: $distance, suffix: meter.short, allowsDecimal: meter == .hours)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    LabeledContent(meter.hasReading ? "Or every" : "Every") {
                        NumberField(title: "None", value: $months, suffix: "months")
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("How often")
                } footer: {
                    Text(meter.hasReading ? "Whichever comes first. Leave one empty to use only the other." : "Leave empty for a job you log only as needed.")
                }
                Section("Notes") {
                    HStack(alignment: .top) {
                        TextField("Part numbers, torque specs, the shop you trust", text: $notes, axis: .vertical).lineLimit(2...6)
                        ScanFieldButton(kind: .text) { notes = notes.trimmed.isEmpty ? $0 : notes + "\n" + $0 }
                    }
                }
                if let task {
                    Section {
                        Button("Remove from schedule", role: .destructive) { confirmingRemove = true }
                            .confirmationDialog("Remove \(task.displayName.lowercasedFirst) from the schedule?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                                Button("Remove", role: .destructive) {
                                    garage.remove(task)
                                    Haptics.success()
                                    dismiss()
                                }
                            } message: {
                                Text(task.catalogKey == nil
                                     ? "Its reminders stop. Past entries stay in the history."
                                     : "Its reminders stop. Past entries stay in the history, and it can be added back from the catalog.")
                            }
                    } footer: {
                        Text("Past entries stay in the history.")
                    }
                }
            }
            .paperBackground()
            .navigationTitle(task == nil ? "New job" : "Edit job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { confirmingDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let task {
                            garage.update(task, name: name, distance: distance ?? 0, months: Int(months ?? 0), notes: notes)
                        } else {
                            let created = garage.addCustomTask(name: name, distance: distance ?? 0, months: Int(months ?? 0), onAuxMeter: onAuxMeter, to: vehicle)
                            created.notes = notes.trimmed.nilIfEmpty
                            garage.saveVehicleEdits()
                        }
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.trimmed.isEmpty)
                }
            }
            .discardGuard(isDirty: isDirty, confirming: $confirmingDiscard) { dismiss() }
            .onAppear {
                defer { baseline = snapshot }
                guard let task else { return }
                name = task.displayName
                distance = task.intervalDistance > 0 ? task.intervalDistance : nil
                months = task.intervalMonths > 0 ? Double(task.intervalMonths) : nil
                notes = task.notes ?? ""
            }
        }
    }
}

/// "When was it last done?" for jobs done before the app.
struct LastDoneSheet: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    let task: MaintenanceTask

    @State private var date = Date.now
    @State private var reading: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    if task.countingMeter.hasReading {
                        LabeledContent(task.meterLabel) {
                            HStack(spacing: Theme.xs) {
                                NumberField(title: "If you know it", value: $reading, suffix: task.countingMeter.short, allowsDecimal: task.countingMeter == .hours)
                                    .multilineTextAlignment(.trailing)
                                ScanFieldButton(kind: .reading(last: 0, meter: task.countingMeter)) { reading = Double($0) }
                            }
                        }
                    }
                } footer: {
                    Text("A best guess is fine. It only sets when this is next due; it isn't added to the history.")
                }
            }
            .paperBackground()
            .fittedSheet()
            .navigationTitle("Last \(task.displayName.lowercasedFirst)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        garage.setBaseline(task, date: date, reading: reading)
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let baseline = task.baselineDate { date = baseline }
                if task.baselineReading >= 0 { reading = task.baselineReading }
            }
        }
    }
}
