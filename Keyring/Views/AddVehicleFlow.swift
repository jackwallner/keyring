import PhotosUI
import StoreKit
import SwiftUI

/// Adding a vehicle in three short steps: what kind, which one, and when the
/// big jobs were last done. The schedule builds itself from the answers.
struct AddVehicleFlow: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    var onFinish: ((Vehicle) -> Void)?

    @State private var draft = NewVehicle()
    @State private var step: Step = .kind

    enum Step { case kind, details, history }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .kind:
                    KindPicker { kind in
                        draft.kind = kind
                        draft.powertrain = kind.defaultPowertrain
                        draft.meter = Locale.current.measurementSystem == .metric && kind.defaultMeter == .miles ? .kilometers : kind.defaultMeter
                        draft.tint = .defaultTint(for: kind)
                        withAnimation(.snappy) { step = .details }
                    }
                case .details:
                    VehicleDetailsForm(draft: $draft) {
                        withAnimation(.snappy) { step = coreItems.isEmpty ? .history : .history }
                    }
                case .history:
                    LastDoneStep(draft: $draft, items: coreItems, finish: finish)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .kind {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button {
                            withAnimation(.snappy) { step = step == .history ? .details : .kind }
                        } label: {
                            Label("Back", systemImage: "chevron.backward")
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(step != .kind)
    }

    private var coreItems: [CatalogItem] {
        MaintenanceCatalog.items(for: draft.kind, powertrain: draft.powertrain).filter(\.isCore).prefix(4).map { $0 }
    }

    private func finish() {
        let vehicle = garage.addVehicle(draft)
        AppGroup.defaults.set(true, forKey: AppGroup.Key.hasCompletedSetup)
        Haptics.success()
        onFinish?(vehicle)
        if garage.vehicles.count >= 2, ReviewPrompter.shouldAsk() {
            ReviewPrompter.markAsked()
            Task {
                try? await Task.sleep(for: .seconds(1))
                requestReview()
            }
        }
        dismiss()
    }
}

/// Nineteen kinds, read as four groups.
struct KindPicker: View {
    let pick: (VehicleKind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                Text("What are you adding?")
                    .font(Theme.title(28))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, Theme.xs)
                ForEach(VehicleKind.pickerSections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Eyebrow(text: section.title)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Theme.xs)], spacing: Theme.xs) {
                            ForEach(section.kinds) { kind in
                                Button {
                                    Haptics.selected()
                                    pick(kind)
                                } label: {
                                    VStack(spacing: Theme.xs) {
                                        Image(systemName: kind.symbol)
                                            .font(.system(size: 26))
                                            .foregroundStyle(VehicleTint.defaultTint(for: kind).isLight ? Theme.brass : VehicleTint.defaultTint(for: kind).color)
                                            .frame(height: 32)
                                        Text(kind.title)
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 84)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityIdentifier("kind.\(kind.rawValue)")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.xl)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Year, make, model and the rest. A VIN fills most of it in.
struct VehicleDetailsForm: View {
    @Binding var draft: NewVehicle
    var buttonTitle = "Continue"
    let next: () -> Void

    @State private var lookingUp = false
    @State private var lookupMessage: String?
    @State private var decoded: DecodedVIN?
    @State private var showingVINScanner = false
    @State private var modelSuggestions: [String] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var yearValue: Double?
    @State private var reading: Double?

    var body: some View {
        Form {
            Section {
                HStack(spacing: Theme.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill((draft.tint ?? .defaultTint(for: draft.kind)).color)
                        if let data = draft.photo, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            Image(systemName: draft.kind.symbol).font(.title).foregroundStyle((draft.tint ?? .defaultTint(for: draft.kind)).foreground)
                        }
                    }
                    .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.kind.title).font(Theme.title(22))
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(draft.photo == nil ? "Add a photo" : "Change photo").font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if draft.kind.hasNHTSARecords {
                Section {
                    HStack {
                        TextField("VIN (optional)", text: $draft.vin)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                        if LiveTextScanner.isAvailable {
                            Button { showingVINScanner = true } label: { Image(systemName: "camera.viewfinder") }
                                .accessibilityLabel("Scan VIN")
                        }
                    }
                    if NHTSAClient.normalizedVIN(draft.vin) != nil {
                        Button {
                            Task { await lookUp() }
                        } label: {
                            HStack {
                                Label("Fill in from the VIN", systemImage: "wand.and.stars")
                                if lookingUp { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(lookingUp)
                    }
                } footer: {
                    if let lookupMessage { Text(lookupMessage) } else {
                        Text("On the driver's side of the windshield or the door jamb. Keyring fills in the year, make, model and engine from NHTSA.")
                    }
                }
            }

            Section("Vehicle") {
                LabeledContent("Year") {
                    NumberField(title: "Year", value: $yearValue)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Make", text: $draft.make)
                    .textInputAutocapitalization(.words)
                if draft.make.isEmpty, !Makes.common(for: draft.kind).isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Makes.common(for: draft.kind), id: \.self) { make in
                                Button(make) {
                                    draft.make = make
                                    Haptics.selected()
                                }
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Theme.raised, in: Capsule())
                                .foregroundStyle(Theme.ink)
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                TextField("Model", text: $draft.model)
                    .textInputAutocapitalization(.words)
                let matches = modelSuggestions.filter { !draft.model.isEmpty && $0.lowercased().hasPrefix(draft.model.lowercased()) && $0.lowercased() != draft.model.lowercased() }
                if !matches.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(matches.prefix(8), id: \.self) { model in
                                Button(model) { draft.model = model }
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Theme.raised, in: Capsule())
                                    .foregroundStyle(Theme.ink)
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                TextField("Trim (optional)", text: $draft.trim)
                TextField("Nickname (optional)", text: $draft.nickname)
            }

            Section {
                if draft.kind.powertrainChoices.count > 1 {
                    Picker("Powertrain", selection: $draft.powertrain) {
                        ForEach(draft.kind.powertrainChoices) { Text($0.title).tag($0) }
                    }
                }
                Picker("Meter", selection: $draft.meter) {
                    ForEach(MeterUnit.allCases) { Text($0.title).tag($0) }
                }
                if draft.meter.hasReading {
                    LabeledContent("Current \(draft.meter.meterName.lowercased())") {
                        NumberField(title: "0", value: $reading, suffix: draft.meter.short, allowsDecimal: draft.meter == .hours)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text("Engine and meter")
            } footer: {
                Text(draft.meter == .hours ? "Engine hours drive the schedule for boats, planes and equipment." : "The schedule picks jobs for this powertrain. You can change any of it later.")
            }

            Section {
                TextField(draft.kind.registrationLabel + " (optional)", text: $draft.plate)
                    .textInputAutocapitalization(.characters)
                if !draft.kind.hasNHTSARecords {
                    TextField(draft.kind.identifierLabel + " (optional)", text: $draft.vin)
                        .textInputAutocapitalization(.characters)
                        .font(.body.monospaced())
                }
            }

            Section("Color") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.sm) {
                        ForEach(VehicleTint.allCases) { tint in
                            Button {
                                draft.tint = tint
                                Haptics.selected()
                            } label: {
                                Circle()
                                    .fill(tint.color)
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: (draft.tint ?? .defaultTint(for: draft.kind)) == tint ? 2.5 : 0).padding(-4))
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tint.title)
                            .accessibilityAddTraits((draft.tint ?? .defaultTint(for: draft.kind)) == tint ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button(buttonTitle) {
                    commitNumbers()
                    next()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isValid)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("vehicle.continue")
            } footer: {
                if !isValid { Text("Give it a make, a model or a nickname.") }
            }
        }
        .paperBackground()
        .navigationTitle(draft.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            yearValue = draft.year > 0 ? Double(draft.year) : nil
            reading = draft.reading > 0 ? draft.reading : nil
        }
        .onChange(of: yearValue) { _, _ in commitNumbers() }
        .onChange(of: reading) { _, _ in commitNumbers() }
        .task(id: "\(draft.make)|\(draft.year)") {
            guard draft.kind.hasNHTSARecords, draft.make.count >= 2 else { modelSuggestions = []; return }
            try? await Task.sleep(for: .milliseconds(400))
            modelSuggestions = await NHTSAClient.models(make: draft.make, year: draft.year > 1980 ? draft.year : nil)
        }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    draft.photo = ImageTools.jpeg(data, maxDimension: 1600, quality: 0.8)
                }
            }
        }
        .sheet(isPresented: $showingVINScanner) {
            VINScanner { vin in
                draft.vin = vin
                showingVINScanner = false
                Task { await lookUp() }
            }
        }
    }

    private var isValid: Bool {
        !draft.make.trimmed.isEmpty || !draft.model.trimmed.isEmpty || !draft.nickname.trimmed.isEmpty
    }

    private func commitNumbers() {
        draft.year = yearValue.map { Int($0) }.flatMap { (1900...2100).contains($0) ? $0 : nil } ?? 0
        draft.reading = reading ?? 0
    }

    private func lookUp() async {
        lookingUp = true
        defer { lookingUp = false }
        do {
            let result = try await NHTSAClient.decode(vin: draft.vin)
            decoded = result
            if let year = result.year { draft.year = year; yearValue = Double(year) }
            if !result.make.isEmpty { draft.make = result.make }
            if !result.model.isEmpty { draft.model = result.model }
            if !result.trim.isEmpty { draft.trim = result.trim }
            if let powertrain = result.powertrain, draft.kind.powertrainChoices.contains(powertrain) { draft.powertrain = powertrain }
            lookupMessage = ["Found it: \(result.year.map(String.init) ?? "") \(result.make) \(result.model)".trimmed, result.summary].filter { !$0.isEmpty }.joined(separator: ". ")
            Haptics.success()
        } catch let error as NHTSAClient.LookupError {
            lookupMessage = error.message
        } catch {
            lookupMessage = NHTSAClient.LookupError.offline.message
        }
    }
}

/// "When was the oil last changed?" for the few jobs that matter most, so
/// the first screen shows real due dates instead of question marks.
struct LastDoneStep: View {
    @Binding var draft: NewVehicle
    let items: [CatalogItem]
    let finish: () -> Void

    enum Answer: String, CaseIterable, Identifiable {
        case recently, months, year, unsure
        var id: String { rawValue }
        var title: String {
            switch self {
            case .recently: "This month"
            case .months: "A few months"
            case .year: "Over a year"
            case .unsure: "Not sure"
            }
        }
        var daysAgo: Double? {
            switch self {
            case .recently: 14
            case .months: 120
            case .year: 400
            case .unsure: nil
            }
        }
    }

    @State private var answers: [String: Answer] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text("When were these last done?")
                        .font(Theme.title(28))
                        .foregroundStyle(Theme.ink)
                    Text("Rough is fine. It sets the first due dates; Keyring learns the rest from what you log.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
                .padding(.top, Theme.xs)
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Label(item.name, systemImage: item.symbol)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text("Every \(Format.interval(distance: item.distanceInterval(for: draft.meter) ?? 0, months: item.months ?? 0, meter: draft.meter))")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                        Picker(item.name, selection: Binding(
                            get: { answers[item.key] ?? .unsure },
                            set: { answers[item.key] = $0 }
                        )) {
                            ForEach(Answer.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .card()
                }
                if items.isEmpty {
                    Text("No regular jobs for this kind yet. Add your own from its schedule.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
                Button("Add to garage") {
                    var lastDone: [String: Date] = [:]
                    for (key, answer) in answers {
                        if let days = answer.daysAgo { lastDone[key] = Date.now.addingTimeInterval(-days * 86_400) }
                    }
                    draft.lastDone = lastDone
                    finish()
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("vehicle.finish")
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.xl)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Changing what was set up: same form, applied to the stored vehicle.
struct EditVehicleView: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var draft = NewVehicle()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            VehicleDetailsForm(draft: $draft, buttonTitle: "Save", next: save)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .navigationTitle("Edit \(vehicle.displayName)")
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = NewVehicle(
                kind: vehicle.kind, powertrain: vehicle.powertrain, meter: vehicle.meter,
                year: Int(vehicle.year), make: vehicle.make ?? "", model: vehicle.model ?? "", trim: vehicle.trim ?? "",
                nickname: vehicle.nickname ?? "", vin: vehicle.vin ?? "", plate: vehicle.plate ?? "",
                reading: vehicle.reading, photo: vehicle.photo, tint: vehicle.tint
            )
        }
    }

    private func save() {
        let powertrainChanged = vehicle.powertrain != draft.powertrain
        vehicle.powertrain = draft.powertrain
        vehicle.meter = draft.meter
        vehicle.year = Int16(clamping: draft.year)
        vehicle.make = draft.make.trimmed.nilIfEmpty
        vehicle.model = draft.model.trimmed.nilIfEmpty
        vehicle.trim = draft.trim.trimmed.nilIfEmpty
        vehicle.nickname = draft.nickname.trimmed.nilIfEmpty
        vehicle.vin = draft.vin.trimmed.uppercased().nilIfEmpty
        vehicle.plate = draft.plate.trimmed.uppercased().nilIfEmpty
        vehicle.photo = draft.photo
        vehicle.tint = draft.tint ?? vehicle.tint
        garage.saveVehicleEdits()
        if draft.meter.hasReading, draft.reading != vehicle.reading, draft.reading > 0 {
            garage.updateReading(vehicle, to: draft.reading)
        }
        if powertrainChanged {
            // New powertrain, new core jobs; the old ones stay with their history.
            let core = MaintenanceCatalog.items(for: vehicle.kind, powertrain: vehicle.powertrain).filter(\.isCore)
            garage.addCatalogItems(core, to: vehicle)
        }
        dismiss()
    }
}
