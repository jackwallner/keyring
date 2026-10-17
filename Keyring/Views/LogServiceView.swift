import PhotosUI
import StoreKit
import SwiftUI

/// Logging a job in a few taps: what was done, when, at what reading, who
/// did it and what it cost. A receipt photo can fill most of it in.
struct LogServiceView: View {
    @EnvironmentObject private var garage: GarageStore
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    let vehicle: Vehicle
    var preselected: [UUID] = []
    var editing: ServiceEntry?

    @State private var draft = GarageStore.ServiceDraft()
    @State private var reading: Double?
    @State private var cost: Double?
    @State private var selected: Set<UUID> = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var receiptItems: [PhotosPickerItem] = []
    @State private var showingScanner = false
    @State private var showingPaywall = false
    @State private var readingReceipt = false
    @State private var receiptNote: String?
    @State private var addingCustom = false
    @State private var customName = ""
    @State private var loaded = false

    private var dues: [TaskDue] { garage.dues(for: vehicle) }

    var body: some View {
        NavigationStack {
            Form {
                jobsSection
                whenSection
                whoSection
                receiptSection
                Section("Notes") {
                    TextField("Parts used, what the shop said, anything to remember", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .paperBackground()
            .navigationTitle(editing == nil ? "Log service" : "Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .accessibilityIdentifier("log.save")
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showingScanner) {
                ReceiptScanner { images in
                    showingScanner = false
                    Task { await addReceipts(images.compactMap { ImageTools.jpeg($0, maxDimension: 2000, quality: 0.7) }) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingPaywall) { PaywallView(focus: .receiptScan) }
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
                    guard !name.isEmpty else { return }
                    let task = garage.addCustomTask(name: name, distance: 0, months: 0, to: vehicle)
                    if let id = task.id { selected.insert(id) }
                    customName = ""
                }
                Button("Cancel", role: .cancel) { customName = "" }
            } message: {
                Text("A one-off or anything not on the schedule. You can set how often it repeats later.")
            }
        }
    }

    private var canSave: Bool {
        !selected.isEmpty || !draft.title.trimmed.isEmpty || !draft.notes.trimmed.isEmpty || (cost ?? 0) > 0
    }

    // MARK: - Sections

    private var jobsSection: some View {
        Section {
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
                                Text(due.dueLine(meter: vehicle.meter, current: vehicle.reading))
                                    .font(.caption)
                                    .foregroundStyle(due.result.status.color)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected.contains(due.taskID) ? .isSelected : [])
            }
            Button {
                addingCustom = true
            } label: {
                Label("Something else", systemImage: "plus")
            }
            TextField("Title (optional)", text: $draft.title)
        } header: {
            Text("What was done")
        } footer: {
            if !selected.isEmpty {
                Text("Saved as \"\(draft.title.trimmed.isEmpty ? garage.title(for: Array(selected), on: vehicle) : draft.title.trimmed)\". Each checked job restarts its countdown.")
            }
        }
    }

    private var whenSection: some View {
        Section("When") {
            DatePicker("Date", selection: $draft.date, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: .date)
            if vehicle.meter.hasReading {
                LabeledContent(vehicle.meter.meterName) {
                    NumberField(title: Format.reading(vehicle.reading, vehicle.meter), value: $reading, suffix: vehicle.meter.short, allowsDecimal: vehicle.meter == .hours)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
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
                TextField("Shop name", text: $draft.shop)
                    .textContentType(.organizationName)
                if draft.shop.isEmpty, !recentShops.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(recentShops, id: \.self) { shop in
                                Button(shop) { draft.shop = shop }
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Theme.raised, in: Capsule())
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                    }
                }
            }
            LabeledContent("Cost") {
                NumberField(title: "0", value: $cost, suffix: Locale.current.currencySymbol ?? "$", allowsDecimal: true)
                    .multilineTextAlignment(.trailing)
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
                        ForEach(Array((draft.receipts + draft.photos).enumerated()), id: \.offset) { _, data in thumb(data) }
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
                Button { showingPaywall = true } label: {
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
        } header: {
            Text("Receipt and photos")
        } footer: {
            if store.isPro {
                Text("Keyring reads the total, date, shop and mileage from a receipt on this iPhone. Check what it fills in.")
            } else {
                Text("Receipts and photos are always saved. With Keyring Pro, the total, date, shop and mileage fill in by themselves.")
            }
        }
    }

    private func thumb(_ data: Data) -> some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Theme.raised
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var recentShops: [String] {
        let shops = garage.allEntries().compactMap(\.shop).filter { !$0.isEmpty }
        var seen = Set<String>()
        return shops.filter { seen.insert($0.lowercased()).inserted }.prefix(5).map { $0 }
    }

    // MARK: - Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let editing {
            draft.date = editing.date ?? .now
            draft.title = editing.title ?? ""
            draft.shop = editing.shop ?? ""
            draft.isDIY = editing.isDIY
            draft.notes = editing.notes ?? ""
            reading = editing.hasReading ? editing.reading : nil
            cost = editing.cost > 0 ? editing.cost : nil
            selected = Set(editing.coveredTaskIDs)
            // A custom title that matches the generated one stays generated.
            if draft.title == garage.title(for: editing.coveredTaskIDs, on: vehicle) { draft.title = "" }
        } else {
            selected = Set(preselected)
            #if DEBUG
            if ScreenshotConfig.isEnabled {
                selected = Set(dues.filter { $0.result.status <= .dueSoon }.prefix(2).map(\.taskID))
                reading = vehicle.reading
                cost = 94.50
                draft.shop = "Lithia Toyota"
            }
            #endif
        }
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
        readingReceipt = true
        let fields = await ReceiptReader.read(images[0])
        readingReceipt = false
        var filled: [String] = []
        if (cost ?? 0) == 0, let total = fields.total { cost = total; filled.append("total") }
        if let date = fields.date, Calendar.current.isDateInToday(draft.date) { draft.date = date; filled.append("date") }
        if reading == nil, let value = fields.reading, vehicle.meter.hasReading, value <= vehicle.reading * 1.5 + 1_000 {
            reading = value
            filled.append(vehicle.meter.meterName.lowercased())
        }
        if draft.shop.isEmpty, let shop = fields.shop, !draft.isDIY { draft.shop = shop; filled.append("shop") }
        receiptNote = filled.isEmpty
            ? "Couldn't read this one clearly. The receipt is attached; fill in the details above."
            : "Filled in the \(ListFormatter.localizedString(byJoining: filled)) from the receipt. Check they're right."
        Haptics.success()
    }

    private func save() {
        draft.reading = reading
        draft.cost = cost ?? 0
        draft.taskIDs = dues.map(\.taskID).filter(selected.contains) + selected.filter { id in !dues.contains { $0.taskID == id } }
        garage.log(draft, for: vehicle, editing: editing)
        Haptics.success()
        if editing == nil, ReviewPrompter.shouldAsk() {
            ReviewPrompter.markAsked()
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                requestReview()
            }
        }
        dismiss()
    }
}
