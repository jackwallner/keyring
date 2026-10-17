import PhotosUI
import SwiftUI

/// A fill-up at the pump: a photo of the pump display and one of the dash
/// fill in the gallons, price, total and odometer. Any two of gallons, price
/// and total work out the third.
struct FuelLogView: View {
    @EnvironmentObject private var garage: GarageStore
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle
    var editing: ServiceEntry?

    private enum Figure: Hashable { case volume, price, total }
    private enum Shot: String, Identifiable { case pump, dash; var id: String { rawValue } }

    @State private var draft = GarageStore.FuelDraft()
    @State private var volume: Double?
    @State private var price: Double?
    @State private var total: Double?
    /// The two figures typed or read most recently; the third is worked out.
    @State private var entered: [Figure] = []
    @State private var derived: (figure: Figure, value: Double)?
    @State private var reading: Double?
    @State private var camera: Shot?
    @State private var pumpItem: PhotosPickerItem?
    @State private var dashItem: PhotosPickerItem?
    @State private var readingPump = false
    @State private var readingDash = false
    @State private var pumpNote: String?
    @State private var dashNote: String?
    @State private var showingPaywall = false
    @State private var confirmingJump = false
    @State private var loaded = false
    @State private var baseline: Snapshot?
    @State private var confirmingDiscard = false

    private struct Snapshot: Equatable {
        var draft: GarageStore.FuelDraft
        var volume: Double?
        var price: Double?
        var total: Double?
        var reading: Double?
    }

    private var snapshot: Snapshot { Snapshot(draft: draft, volume: volume, price: price, total: total, reading: reading) }
    private var isDirty: Bool { baseline.map { $0 != snapshot } ?? false }

    private var unit: FuelVolumeUnit { draft.unit }
    private var symbol: String { Locale.current.currencySymbol ?? "$" }

    var body: some View {
        NavigationStack {
            Form {
                pumpSection
                figuresSection
                if vehicle.meter.hasReading { meterSection }
                whenSection
            }
            .paperBackground()
            .navigationTitle(editing == nil ? "Fill-up" : "Edit fill-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { confirmingDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: attemptSave)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .accessibilityIdentifier("fuel.save")
                }
            }
            .onAppear(perform: load)
            .discardGuard(isDirty: isDirty, confirming: $confirmingDiscard) { dismiss() }
            .onChange(of: pumpItem) { _, item in Task { await loadPicked(item, as: .pump) } }
            .onChange(of: dashItem) { _, item in Task { await loadPicked(item, as: .dash) } }
            .fullScreenCover(item: $camera) { shot in
                CameraPicker { image in
                    camera = nil
                    guard let image, let data = ImageTools.jpeg(image, maxDimension: 2000, quality: 0.7) else { return }
                    Task { await add(data, as: shot) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingPaywall) { PaywallView(focus: .receiptScan) }
            .confirmationDialog("Save at \(Format.reading(reading ?? 0, vehicle.meter))?", isPresented: $confirmingJump, titleVisibility: .visible) {
                Button("Save at \(Format.reading(reading ?? 0, vehicle.meter))", action: save)
                Button("Fix it", role: .cancel) {}
            } message: {
                Text("That's \(Format.reading((reading ?? 0) - vehicle.reading, vehicle.meter)) more than the last reading, which is a lot. Check for an extra digit.")
            }
        }
    }

    private var meterWord: String { vehicle.meter == .hours ? "hour meter" : "odometer" }

    private var canSave: Bool { (volume ?? 0) > 0 || (total ?? 0) > 0 || reading != nil }

    // MARK: - Sections

    private var pumpSection: some View {
        Section {
            if !draft.pumpPhotos.isEmpty {
                photoRow(draft.pumpPhotos, busy: readingPump, busyText: "Reading the pump", note: pumpNote) { draft.pumpPhotos.remove(at: $0) }
            }
            if !store.isPro, !draft.pumpPhotos.isEmpty {
                Button { showingPaywall = true } label: {
                    HStack {
                        Label("Fill in from the photo", systemImage: "text.viewfinder")
                        Spacer()
                        Image(systemName: "lock.fill").font(.footnote).foregroundStyle(Theme.faintInk)
                    }
                }
            }
            if CameraPicker.isAvailable {
                Button { camera = .pump } label: { Label("Take a photo of the pump", systemImage: "camera") }
                    .accessibilityIdentifier("fuel.pumpCamera")
            }
            let pumpLabel = CameraPicker.isAvailable ? "Choose a photo instead" : "Choose a photo of the pump"
            PhotosPicker(selection: $pumpItem, matching: .images) {
                Label(pumpLabel, systemImage: "photo")
            }
            .accessibilityIdentifier("fuel.pumpPhoto")
        } header: {
            Text("Pump")
        } footer: {
            Text(store.isPro
                 ? "The app reads the \(unit.plural.lowercased()), price and total on this iPhone. Check what it fills in."
                 : "The photo is always saved. With Pro, the \(unit.plural.lowercased()), price and total fill in by themselves.")
        }
    }

    private var figuresSection: some View {
        Section {
            LabeledContent(unit.plural) {
                NumberField(title: "0", value: binding(.volume), suffix: unit.short, allowsDecimal: true, fractionDigits: 3)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("fuel.volume")
            }
            LabeledContent("Price per \(unit.name)") {
                NumberField(title: "0", value: binding(.price), isCurrency: true, fractionDigits: 3)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("fuel.price")
            }
            LabeledContent("Total") {
                NumberField(title: "0", value: binding(.total), isCurrency: true)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("fuel.total")
            }
            gradeRow
            Toggle("Filled the tank", isOn: Binding(get: { !draft.partial }, set: { draft.partial = !$0 }))
        } footer: {
            if draft.partial {
                Text("A top-up. Fuel economy waits for the next full tank.")
            } else if let derived {
                Text(derivedText(derived.figure))
            }
        }
    }

    @ViewBuilder private var gradeRow: some View {
        let choices = vehicle.fuelGradeChoices
        if choices.count > 1 {
            Picker("Grade", selection: $draft.grade) {
                ForEach(choices) { grade in Text(grade.title).tag(Optional(grade)) }
            }
        } else if let only = choices.first {
            LabeledContent("Grade", value: only.title)
        }
    }

    private var meterSection: some View {
        Section {
            LabeledContent(vehicle.meter.meterName) {
                NumberField(title: "Optional", value: $reading, suffix: vehicle.meter.short, allowsDecimal: vehicle.meter == .hours)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("fuel.reading")
            }
            if !draft.meterPhotos.isEmpty {
                photoRow(draft.meterPhotos, busy: readingDash, busyText: "Reading the dash", note: dashNote) { draft.meterPhotos.remove(at: $0) }
            }
            if CameraPicker.isAvailable {
                Button { camera = .dash } label: { Label("Take a photo of the \(meterWord)", systemImage: "camera") }
            }
            let dashLabel = CameraPicker.isAvailable ? "Choose a photo instead" : "Choose a photo of the \(meterWord)"
            PhotosPicker(selection: $dashItem, matching: .images) {
                Label(dashLabel, systemImage: "photo")
            }
            .accessibilityIdentifier("fuel.dashPhoto")
        } footer: {
            if let text = meterFooter { Text(text) }
        }
    }

    private var whenSection: some View {
        Section {
            DatePicker("Date", selection: $draft.date, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: [.date, .hourAndMinute])
            HStack {
                TextField("Station", text: $draft.station)
                    .textContentType(.organizationName)
                    .accessibilityIdentifier("fuel.station")
                ScanFieldButton(kind: .text) { draft.station = $0 }
            }
            let recent = garage.recentStations(for: vehicle)
            if draft.station.isEmpty, !recent.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(recent, id: \.self) { station in
                            SuggestionChip(station) { draft.station = station }
                        }
                    }
                }
            }
        }
    }

    /// The last three photos, each with an x to take it off again before saving.
    private func photoRow(_ photos: [Data], busy: Bool, busyText: String, note: String?, remove: @escaping (Int) -> Void) -> some View {
        let shown = Array(photos.enumerated()).suffix(3)
        return HStack(spacing: Theme.sm) {
            ForEach(shown, id: \.offset) { index, data in
                Group {
                    if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() } else { Theme.raised }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button { remove(index) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.6))
                            .padding(2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove photo")
                }
            }
            if busy {
                ProgressView()
                Text(busyText).font(.footnote).foregroundStyle(Theme.secondaryInk)
            } else if let note {
                Text(note).font(.footnote).foregroundStyle(Theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Figures

    private func derivedText(_ figure: Figure) -> String {
        switch figure {
        case .total: "Total worked out from the \(unit.plural.lowercased()) and price."
        case .price: "Price worked out from the total and \(unit.plural.lowercased())."
        case .volume: "\(unit.plural) worked out from the total and price."
        }
    }

    private func value(_ figure: Figure) -> Double? {
        switch figure {
        case .volume: volume
        case .price: price
        case .total: total
        }
    }

    private func set(_ figure: Figure, _ value: Double?) {
        switch figure {
        case .volume: volume = value
        case .price: price = value
        case .total: total = value
        }
    }

    /// Only typing comes through here; a figure set from a photo or worked
    /// out doesn't count as typed. The field echoes its own display back, so
    /// an unchanged value is ignored.
    private func binding(_ figure: Figure) -> Binding<Double?> {
        Binding(
            get: { value(figure) },
            set: { newValue in
                guard newValue != value(figure) else { return }
                set(figure, newValue)
                edited(figure, newValue)
            }
        )
    }

    /// Typing a figure keeps it, and the one not typed follows the other two.
    private func edited(_ figure: Figure, _ newValue: Double?) {
        if derived?.figure == figure { derived = nil }
        entered.removeAll { $0 == figure }
        if newValue != nil { entered.insert(figure, at: 0) }
        entered = Array(entered.prefix(2))
        guard entered.count == 2, let open = [Figure.volume, .price, .total].first(where: { !entered.contains($0) }) else { return }
        let fields = PumpReader.completed(PumpFields(
            volume: open == .volume ? nil : volume,
            unitPrice: open == .price ? nil : price,
            total: open == .total ? nil : total
        ))
        let worked: Double? = switch open {
        case .volume: fields.volume
        case .price: fields.unitPrice
        case .total: fields.total
        }
        guard let worked, worked > 0 else { return }
        derived = (open, worked)
        set(open, worked)
    }

    private var meterFooter: String? {
        var parts: [String] = []
        if vehicle.reading > 0 {
            parts.append("Last reading \(Format.reading(vehicle.reading, vehicle.meter))\(vehicle.readingDate.map { " on \(Format.shortDate($0))" } ?? "").")
        }
        if let economy = previewEconomy { parts.append("That's \(economy) since the last full tank.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The figure this fill-up will show once saved.
    private var previewEconomy: String? {
        guard editing == nil, !draft.partial, let reading, let volume, volume > 0 else { return nil }
        let economy = FuelEconomy(meter: vehicle.meter, unit: unit)
        let id = UUID()
        let fills = FuelEconomy.fills(for: vehicle) + [FuelEconomy.Fill(id: id, date: draft.date, reading: reading, liters: unit.liters(volume), partial: false)]
        return economy.values(fills)[id].map(economy.format)
    }

    // MARK: - Photos

    private func loadPicked(_ item: PhotosPickerItem?, as shot: Shot) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self), let jpeg = ImageTools.jpeg(data, maxDimension: 2000, quality: 0.7) {
            await add(jpeg, as: shot)
        }
        if shot == .pump { pumpItem = nil } else { dashItem = nil }
    }

    private func add(_ data: Data, as shot: Shot) async {
        switch shot {
        case .pump:
            draft.pumpPhotos.append(data)
            guard store.isPro else { return }
            readingPump = true
            let fields = await PumpReader.read(data, unit: unit)
            readingPump = false
            apply(fields)
        case .dash:
            draft.meterPhotos.append(data)
            readingDash = true
            let value = await OdometerReader.read(data, last: vehicle.reading, meter: vehicle.meter)
            readingDash = false
            if let value {
                reading = value
                dashNote = "Read \(Format.reading(value, vehicle.meter)). Check it's right."
                Haptics.success()
            } else {
                dashNote = "Couldn't pick out the \(meterWord). The photo is saved; type the number above."
            }
        }
    }

    private func apply(_ fields: PumpFields) {
        var filled: [String] = []
        if let value = fields.volume { volume = value; filled.append(unit.plural.lowercased()) }
        if let value = fields.unitPrice { price = value; filled.append("price") }
        if let value = fields.total { total = value; filled.append("total") }
        // What the photo said stands as if typed.
        entered = [Figure.price, .volume, .total].filter { value($0) != nil }.prefix(2).map { $0 }
        derived = nil
        if let grade = fields.grade, vehicle.fuelGradeChoices.contains(grade) { draft.grade = grade; filled.append("grade") }
        if draft.station.isEmpty, let station = fields.station { draft.station = station; filled.append("station") }
        if let date = fields.date, Calendar.current.isDateInToday(draft.date), !Calendar.current.isDateInToday(date) { draft.date = date; filled.append("date") }
        pumpNote = filled.isEmpty
            ? "Couldn't read this one clearly. The photo is saved; fill in the figures below."
            : "Filled in the \(ListFormatter.localizedString(byJoining: filled)). Check they're right."
        if !filled.isEmpty { Haptics.success() }
    }

    // MARK: - Saving

    private func load() {
        guard !loaded else { return }
        loaded = true
        defer { baseline = snapshot }
        draft.grade = vehicle.fuelEntries.first?.grade.flatMap { vehicle.fuelGradeChoices.contains($0) ? $0 : nil } ?? vehicle.fuelGradeChoices.first
        guard let editing else {
            #if DEBUG
            if ScreenshotConfig.isEnabled {
                volume = 12.345
                price = 3.659
                total = 45.17
                draft.station = "Costco"
            }
            #endif
            return
        }
        draft.date = editing.date ?? .now
        draft.grade = editing.grade ?? draft.grade
        draft.partial = editing.fuelPartial
        draft.station = editing.shop ?? ""
        reading = editing.hasReading ? editing.reading : nil
        if editing.fuelVolume > 0 { volume = (unit.fromLiters(editing.fuelVolume) * 1_000).rounded() / 1_000 }
        if editing.fuelUnitPrice > 0 { price = (unit.fromPerLiter(editing.fuelUnitPrice) * 1_000).rounded() / 1_000 }
        if editing.cost > 0 { total = editing.cost }
        entered = [.price, .volume]
    }

    private func attemptSave() {
        if let reading, editing == nil, garage.isSuspiciousJump(reading, for: vehicle) {
            confirmingJump = true
        } else {
            save()
        }
    }

    private func save() {
        draft.reading = reading
        draft.volume = volume
        draft.unitPrice = price
        draft.total = total
        garage.logFuel(draft, for: vehicle, editing: editing)
        Haptics.success()
        dismiss()
    }
}
