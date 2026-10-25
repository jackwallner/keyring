import PhotosUI
import StoreKit
import SwiftUI

/// Logging a job in a few taps: what was done, when, at what reading, who
/// did it and what it cost. A receipt photo can fill most of it in. The same
/// sheet logs planned maintenance, an unplanned repair, or a recall fix.
struct LogServiceView: View {
    @EnvironmentObject private var garage: GarageStore
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    let vehicle: Vehicle
    var preselected: [UUID] = []
    var editing: ServiceEntry?
    /// Logging the dealer visit that closed this recall.
    var recall: Recall?
    /// Opens on Mod (from the build list) rather than Maintenance.
    var startingKind: EntryKind?

    @State private var draft = GarageStore.ServiceDraft()
    @State private var reading: Double?
    @State private var auxReading: Double?
    @State private var cost: Double?
    @State private var selected: Set<UUID> = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var receiptItems: [PhotosPickerItem] = []
    @State private var showingScanner = false
    @State private var showingPaywall = false
    @State private var autofillRequest = ProAutofillRequest()
    @State private var readingReceipt = false
    @State private var receiptNote: String?
    @State private var addingCustom = false
    @State private var customName = ""
    /// One-off jobs typed in for this visit. They live on the entry only, so
    /// nothing is added to the schedule (and Cancel leaves no trace).
    @State private var customJobs: [String] = []
    @State private var loaded = false
    @State private var confirmingJump = false
    @State private var showingScheduled = false
    @State private var addingAnother = false
    @State private var savedInRow = 0
    @State private var baseline: Snapshot?
    @State private var confirmingDiscard = false
    @State private var importingFile = false

    /// Everything the owner can type or pick, compared against the form as it opened.
    private struct Snapshot: Equatable {
        var draft: GarageStore.ServiceDraft
        var reading: Double?
        var auxReading: Double?
        var cost: Double?
        var selected: Set<UUID>
        var customJobs: [String]
    }

    private var snapshot: Snapshot {
        Snapshot(draft: draft, reading: reading, auxReading: auxReading, cost: cost, selected: selected, customJobs: customJobs)
    }

    private var isDirty: Bool { baseline.map { $0 != snapshot } ?? false }

    private var dues: [TaskDue] { garage.dues(for: vehicle) }

    var body: some View {
        NavigationStack {
            Form {
                if draft.kind == .recall {
                    recallSection
                } else {
                    if editing == nil || editing?.kind != .recall { kindPicker }
                    switch draft.kind {
                    case .repair:
                        repairSection
                        scheduledSection
                    case .mod:
                        modSection
                    default:
                        jobsSection
                    }
                }
                whenSection
                whoSection
                PartsSection(parts: $draft.details.parts, specs: $draft.details.specs, cost: $cost)
                receiptSection
                Section("Notes") {
                    HStack(alignment: .top) {
                        TextField(notesPrompt, text: $draft.notes, axis: .vertical)
                            .lineLimit(2...6)
                        ScanFieldButton(kind: .text) { draft.notes = draft.notes.trimmed.isEmpty ? $0 : draft.notes + "\n" + $0 }
                    }
                }
                if editing == nil, draft.kind != .recall {
                    Section {
                        Button("Save and add another") { attemptSave(another: true) }
                            .disabled(!canSave)
                            .accessibilityIdentifier("log.saveAnother")
                    } footer: {
                        Text(savedInRow > 0
                             ? "Saved \(savedInRow == 1 ? "one entry" : "\(savedInRow) entries"). The date stays put for the next old receipt."
                             : "For catching up on old receipts. The date stays put for the next one.")
                    }
                }
            }
            .paperBackground()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { confirmingDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { attemptSave(another: false) }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .accessibilityIdentifier("log.save")
                }
            }
            .onAppear(perform: load)
            .discardGuard(isDirty: isDirty, confirming: $confirmingDiscard) { dismiss() }
            .confirmationDialog("Save at \(Format.reading(reading ?? 0, vehicle.meter))?", isPresented: $confirmingJump, titleVisibility: .visible) {
                Button("Save at \(Format.reading(reading ?? 0, vehicle.meter))") { save() }
                Button("Fix it", role: .cancel) {}
            } message: {
                Text("That's \(Format.reading((reading ?? 0) - vehicle.shownReading, vehicle.meter)) more than the last reading, which is a lot. Check for an extra digit.")
            }
            .sheet(isPresented: $showingScanner) {
                ReceiptScanner { images in
                    showingScanner = false
                    Task { await addReceipts(images.compactMap { ImageTools.jpeg($0, maxDimension: 2000, quality: 0.7) }) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingPaywall, onDismiss: {
                guard let image = autofillRequest.take(isPro: store.isPro) else { return }
                Task { await fillFromReceipt(image) }
            }) { PaywallView(focus: .receiptScan) }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                guard case let .success(urls) = result else { return }
                draft.files += urls.compactMap(PickedFile.read)
            }
            .onChange(of: photoItems) { _, items in Task { await loadPhotos(items) } }
            .onChange(of: receiptItems) { _, items in
                Task {
                    var images: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let jpeg = ImageTools.jpeg(data, maxDimension: 2000, quality: 0.7) {
                            images.append(jpeg)
                        }
                    }
                    receiptItems = []
                    await addReceipts(images)
                }
            }
            .alert("Add a job", isPresented: $addingCustom) {
                TextField("Name", text: $customName)
                Button("Add") {
                    let name = customName.trimmed
                    customName = ""
                    guard !name.isEmpty, !customJobs.contains(name) else { return }
                    customJobs.append(name)
                }
                Button("Cancel", role: .cancel) { customName = "" }
            } message: {
                Text("A one-off for this visit. To have it repeat, add it to the schedule instead.")
            }
        }
    }

    private var navigationTitle: String {
        if editing != nil { return "Edit entry" }
        switch draft.kind {
        case .service: return "Log service"
        case .repair: return "Log a repair"
        case .recall: return "Log the recall fix"
        case .fuel: return "Fill-up"
        case .mod: return "Log a mod"
        case .event: return "Log an event"
        }
    }

    private var notesPrompt: String {
        switch draft.kind {
        case .repair: "What went wrong, what the shop found, warranty"
        case .mod: "Why, how it went on, what to know next time"
        default: "What the shop said, anything to remember"
        }
    }

    private var canSave: Bool {
        if draft.kind == .recall { return true }
        if draft.kind == .repair { return !draft.title.trimmed.isEmpty }
        if draft.kind == .mod { return !draft.title.trimmed.isEmpty || draft.details.parts.contains { !$0.isBlank } }
        return !selected.isEmpty || !customJobs.isEmpty || !draft.title.trimmed.isEmpty || !draft.notes.trimmed.isEmpty || (cost ?? 0) > 0
    }

    // MARK: - Sections

    private var kindPicker: some View {
        Section {
            Picker("Kind", selection: $draft.kind.animation(.snappy)) {
                Text("Maintenance").tag(EntryKind.service)
                Text("Repair").tag(EntryKind.repair)
                Text("Mod").tag(EntryKind.mod)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .accessibilityIdentifier("log.kind")
        }
    }

    private var repairSection: some View {
        Section {
            HStack {
                TextField("Alternator, flat tire, cracked windshield", text: $draft.title)
                    .accessibilityIdentifier("log.repairTitle")
                ScanFieldButton(kind: .text) { draft.title = $0 }
            }
        } header: {
            Text("What was fixed")
        } footer: {
            Text("Repairs are kept apart from maintenance, so you can see what unplanned work really costs.")
        }
    }

    private var modSection: some View {
        Section {
            HStack {
                TextField("Coilovers, intake, tune, lift kit", text: $draft.title)
                    .accessibilityIdentifier("log.modTitle")
                ScanFieldButton(kind: .text) { draft.title = $0 }
            }
        } header: {
            Text("What went on")
        } footer: {
            Text("Mods make the build list and stay out of what it costs to keep running.")
        }
    }

    private var scheduledSection: some View {
        Section {
            if showingScheduled || !selected.isEmpty {
                dueRows
            } else {
                Button { withAnimation(.snappy) { showingScheduled = true } } label: {
                    Label("Scheduled work done on the same visit", systemImage: "plus")
                }
            }
        } header: {
            if showingScheduled || !selected.isEmpty { Text("Scheduled work on the same visit") }
        } footer: {
            if !selected.isEmpty { Text("Each checked job restarts its countdown.") }
        }
    }

    private var recallSection: some View {
        Section {
            if let recall {
                VStack(alignment: .leading, spacing: 3) {
                    Label { Text(recall.componentTitle) } icon: { Image(systemName: EntryKind.recall.symbol).foregroundStyle(Theme.overdue) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("NHTSA campaign \(recall.campaign)")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                }
                .padding(.vertical, 2)
            }
            HStack {
                TextField("Title", text: $draft.title)
                ScanFieldButton(kind: .text) { draft.title = $0 }
            }
        } header: {
            Text("Safety recall")
        } footer: {
            Text("Recall repairs are free at a dealer. Logging it marks the recall fixed for everyone in the garage.")
        }
    }

    @ViewBuilder
    private var dueRows: some View {
        ForEach(dues) { due in
                Button {
                    Haptics.selected()
                    if selected.contains(due.taskID) { selected.remove(due.taskID) } else { selected.insert(due.taskID) }
                } label: {
                    HStack(spacing: Theme.sm) {
                        Image(systemName: selected.contains(due.taskID) ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selected.contains(due.taskID) ? Theme.brass : Theme.faintInk)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(due.name).foregroundStyle(Theme.ink)
                            if due.result.status <= .dueSoon {
                                Text(due.dueLine())
                                    .font(.caption)
                                    .foregroundStyle(due.result.status.color)
                            }
                            // The owner's own spec for the job, right where they log it.
                            if selected.contains(due.taskID), let notes = taskNotes(due.taskID) {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryInk)
                                    .lineLimit(3)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected.contains(due.taskID) ? .isSelected : [])
        }
    }

    private func taskNotes(_ id: UUID) -> String? {
        (vehicle.tasks ?? []).first { $0.id == id }?.notes?.trimmed.nilIfEmpty
    }

    private var jobsSection: some View {
        Section {
            dueRows
            ForEach(customJobs, id: \.self) { name in
                HStack(spacing: Theme.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.brass)
                    Text(name).foregroundStyle(Theme.ink)
                    Spacer()
                    Button {
                        customJobs.removeAll { $0 == name }
                    } label: {
                        Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(Theme.faintInk)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(name)")
                }
            }
            Button {
                addingCustom = true
            } label: {
                Label("Something else", systemImage: "plus")
            }
            HStack {
                TextField("Title (optional)", text: $draft.title)
                ScanFieldButton(kind: .text) { draft.title = $0 }
            }
        } header: {
            Text("What was done")
        } footer: {
            if !selected.isEmpty || !customJobs.isEmpty {
                Text("Saved as \"\(draft.title.trimmed.isEmpty ? generatedTitle : draft.title.trimmed)\".\(selected.isEmpty ? "" : " Each checked job restarts its countdown.")")
            }
        }
    }

    private var whenSection: some View {
        Section {
            DatePicker("Date", selection: $draft.date, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: .date)
            if vehicle.meter.hasReading {
                LabeledContent(vehicle.meter.meterName) {
                    HStack(spacing: Theme.xs) {
                        NumberField(title: "Optional", value: $reading, suffix: vehicle.meter.short, allowsDecimal: vehicle.meter == .hours)
                            .multilineTextAlignment(.trailing)
                        ScanFieldButton(kind: .reading(last: vehicle.shownReading, meter: vehicle.meter)) { reading = Double($0) }
                    }
                }
            }
            if vehicle.hasAuxMeter {
                LabeledContent(vehicle.auxMeterLabel) {
                    HStack(spacing: Theme.xs) {
                        NumberField(title: "Optional", value: $auxReading, suffix: vehicle.auxMeter.short, allowsDecimal: vehicle.auxMeter == .hours)
                            .multilineTextAlignment(.trailing)
                        ScanFieldButton(kind: .reading(last: vehicle.auxReading, meter: vehicle.auxMeter)) { auxReading = Double($0) }
                    }
                }
            }
        } header: {
            Text("When")
        } footer: {
            if let last = lastReadingText { Text(last) }
        }
    }

    private var lastReadingText: String? {
        guard vehicle.meter.hasReading, vehicle.reading > 0 else { return nil }
        let when = vehicle.readingDate.map { " on \(Format.shortDate($0))" } ?? ""
        return "Last reading \(Format.reading(vehicle.shownReading, vehicle.meter))\(when)."
    }

    private var whoSection: some View {
        Section {
            Picker("Done by", selection: $draft.isDIY) {
                Text("A shop").tag(false)
                Text("Myself").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            if !draft.isDIY {
                HStack {
                    TextField(draft.kind == .recall ? "Dealer" : "Shop name", text: $draft.shop)
                        .textContentType(.organizationName)
                    ScanFieldButton(kind: .text) { draft.shop = $0 }
                }
                if draft.shop.isEmpty, !recentShops.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(recentShops, id: \.self) { shop in
                                SuggestionChip(shop) { draft.shop = shop }
                            }
                        }
                    }
                }
            }
            LabeledContent("Cost") {
                HStack(spacing: Theme.xs) {
                    NumberField(title: "0", value: $cost, isCurrency: true)
                        .multilineTextAlignment(.trailing)
                    ScanFieldButton(kind: .amount) { cost = Double($0) }
                }
            }
        } header: {
            Text("Who and how much")
        }
    }

    private var receiptSection: some View {
        Section {
            if !draft.receipts.isEmpty || !draft.photos.isEmpty || !(editing?.sortedAttachments.isEmpty ?? true) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.xs) {
                        ForEach(Array((editing?.sortedAttachments.compactMap(\.data) ?? []).enumerated()), id: \.offset) { _, data in thumb(data) }
                        ForEach(Array(draft.receipts.enumerated()), id: \.offset) { index, data in
                            thumb(data, remove: { draft.receipts.remove(at: index) })
                        }
                        ForEach(Array(draft.photos.enumerated()), id: \.offset) { index, data in
                            thumb(data, remove: { draft.photos.remove(at: index) })
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if readingReceipt {
                HStack(spacing: Theme.xs) {
                    ProgressView()
                    Text("Reading the receipt").foregroundStyle(Theme.secondaryInk)
                }
            }
            if let receiptNote {
                Text(receiptNote).font(.footnote).foregroundStyle(Theme.secondaryInk)
            }
            if !store.isPro, !draft.receipts.isEmpty {
                Button {
                    autofillRequest.image = draft.receipts.first
                    showingPaywall = true
                } label: {
                    HStack {
                        Label("Fill in from the receipt", systemImage: "text.viewfinder")
                        Spacer()
                        Image(systemName: "lock.fill").font(.footnote).foregroundStyle(Theme.faintInk)
                    }
                }
            }
            if ReceiptScanner.isAvailable {
                Button { showingScanner = true } label: { Label("Scan a receipt", systemImage: "doc.viewfinder") }
            }
            PhotosPicker(selection: $receiptItems, maxSelectionCount: 4, matching: .images) {
                Label("Receipt from photos", systemImage: "doc.text.image")
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 8, matching: .images) {
                Label("Add photos of the work", systemImage: "photo.on.rectangle")
            }
            ForEach(Array(draft.files.enumerated()), id: \.offset) { index, file in
                HStack {
                    Label(file.name, systemImage: "doc.fill").foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer()
                    Button { draft.files.remove(at: index) } label: {
                        Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(Theme.faintInk)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(file.name)")
                }
            }
            Button { importingFile = true } label: {
                Label("Attach a file (PDF or image)", systemImage: "paperclip")
            }
        } header: {
            Text("Receipt and photos")
        } footer: {
            if store.isPro {
                Text("The app reads the total, date, shop and mileage from a receipt on this iPhone. Check what it fills in.")
            } else {
                Text("Receipts and photos are always saved. With Pro, the total, date, shop and mileage fill in by themselves.")
            }
        }
    }

    /// A picked photo can be taken off again before it's saved. Ones already
    /// on the entry are deleted from the entry page, where they open full size.
    private func thumb(_ data: Data, remove: (() -> Void)? = nil) -> some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.raised
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if let remove {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.6))
                        .padding(3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove photo")
            }
        }
        .padding(.top, 4)
    }

    /// "Oil change and new wipers", counting one-offs alongside scheduled jobs.
    private var generatedTitle: String {
        guard !customJobs.isEmpty else { return garage.title(for: Array(selected), on: vehicle) }
        let scheduled = selected.isEmpty ? [] : [garage.title(for: Array(selected), on: vehicle)]
        let names = scheduled + customJobs.map(\.lowercasedFirst)
        let joined = ListFormatter.localizedString(byJoining: names)
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    private var recentShops: [String] {
        let shops = garage.allEntries().filter { $0.kind != .fuel }.compactMap(\.shop).filter { !$0.isEmpty }
        var seen = Set<String>()
        return shops.filter { seen.insert($0.lowercased()).inserted }.prefix(5).map { $0 }
    }

    // MARK: - Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let editing {
            draft.kind = editing.kind
            draft.recallCampaign = editing.recallCampaign
            draft.date = editing.date ?? .now
            draft.title = editing.title ?? ""
            draft.shop = editing.shop ?? ""
            draft.isDIY = editing.isDIY
            draft.notes = editing.notes ?? ""
            reading = editing.hasReading ? vehicle.shownReading(true: editing.reading, on: editing.date ?? .now) : nil
            draft.details = editing.details
            auxReading = editing.hasAuxReading ? editing.auxReading : nil
            cost = editing.cost > 0 ? editing.cost : nil
            selected = Set(editing.coveredTaskIDs)
            // A custom title that matches the generated one stays generated.
            if editing.kind == .service, draft.title == garage.title(for: editing.coveredTaskIDs, on: vehicle) { draft.title = "" }
        } else if let recall {
            draft.kind = .recall
            draft.recallCampaign = recall.campaign
            draft.title = "Recall: \(recall.componentTitle.lowercased())"
        } else {
            draft.kind = startingKind ?? .service
            selected = Set(preselected)
            #if DEBUG
            if ScreenshotConfig.isEnabled, preselected.isEmpty, startingKind == nil {
                selected = Set(dues.filter { $0.result.status <= .dueSoon }.prefix(2).map(\.taskID))
                reading = vehicle.shownReading
                cost = 94.50
                draft.shop = "Lithia Toyota"
            }
            #endif
        }
        baseline = snapshot
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let jpeg = ImageTools.jpeg(data) {
                draft.photos.append(jpeg)
            }
        }
        photoItems = []
    }

    private func addReceipts(_ images: [Data]) async {
        guard !images.isEmpty else { return }
        draft.receipts += images
        guard store.isPro else {
            receiptNote = nil
            return
        }
        await fillFromReceipt(images[0])
    }

    private func fillFromReceipt(_ image: Data) async {
        readingReceipt = true
        let (fields, text) = await ReceiptReader.readWithText(image)
        readingReceipt = false
        var filled: [String] = []
        if (cost ?? 0) == 0, let total = fields.total { cost = total; filled.append("total") }
        if let date = fields.date, Calendar.current.isDateInToday(draft.date) { draft.date = date; filled.append("date") }
        if reading == nil, let value = fields.reading, vehicle.meter.hasReading, value <= vehicle.shownReading * 1.5 + 1_000 {
            reading = value
            filled.append(vehicle.meter.meterName.lowercased())
        }
        if draft.shop.isEmpty, let shop = fields.shop, !draft.isDIY { draft.shop = shop; filled.append("shop") }
        receiptNote = filled.isEmpty
            ? "Couldn't read this one clearly. The receipt is attached; fill in the details above."
            : "Filled in the \(ListFormatter.localizedString(byJoining: filled)) from the receipt. Check they're right."
        // Dealer paperwork names the recall it closed.
        if draft.recallCampaign == nil,
           let recall = (RecallWatcher.cached(for: vehicle) ?? []).first(where: { RecallMatcher.mentions($0, in: text) }) {
            draft.recallCampaign = recall.campaign
            receiptNote = (receiptNote ?? "") + " It also shows the \(recall.componentTitle.lowercased()) recall was done, so that recall is marked fixed."
        }
        Haptics.success()
    }

    private func attemptSave(another: Bool) {
        addingAnother = another
        if let reading, editing == nil, garage.isSuspiciousJump(reading, for: vehicle) {
            confirmingJump = true
        } else {
            save()
        }
    }

    private func save() {
        if draft.kind == .service, draft.title.trimmed.isEmpty, !customJobs.isEmpty { draft.title = generatedTitle }
        if draft.kind == .mod { draft.taskIDs = [] }
        draft.reading = reading
        draft.auxReading = auxReading
        draft.cost = cost ?? 0
        if draft.kind != .mod {
            draft.taskIDs = dues.map(\.taskID).filter(selected.contains) + selected.filter { id in !dues.contains { $0.taskID == id } }
        }
        garage.log(draft, for: vehicle, editing: editing)
        Haptics.success()
        if addingAnother {
            startAnother()
            return
        }
        // Catching up on an old receipt isn't a moment to ask for a rating.
        let recent = abs(draft.date.timeIntervalSinceNow) < 30 * 86_400
        if editing == nil, recent, savedInRow == 0, ReviewPrompter.shouldAsk() {
            ReviewPrompter.markAsked()
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                requestReview()
            }
        }
        dismiss()
    }

    /// A clean form for the next entry, keeping the kind and date.
    private func startAnother() {
        var next = GarageStore.ServiceDraft()
        next.kind = draft.kind
        next.date = draft.date
        draft = next
        reading = nil
        auxReading = nil
        cost = nil
        selected = []
        customJobs = []
        receiptNote = nil
        addingAnother = false
        savedInRow += 1
        baseline = snapshot
    }
}
