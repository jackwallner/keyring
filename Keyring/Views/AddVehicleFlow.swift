import PhotosUI
import StoreKit
import SwiftUI

/// Adding a vehicle in three short steps: what kind, which one, and when the
/// big jobs were last done. The schedule builds itself from the answers.
struct AddVehicleFlow: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    /// A kind already picked in onboarding skips straight to the details.
    var startingKind: VehicleKind?
    var onFinish: ((Vehicle) -> Void)?

    @State private var draft = NewVehicle()
    @State private var step: Step = .kind
    /// Where it goes when this person also belongs to someone else's garage.
    @State private var destination: Garage?

    enum Step { case kind, details, history }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .kind:
                    KindPicker { kind in
                        withAnimation(.snappy) { pick(kind) }
                    }
                case .details:
                    VehicleDetailsForm(draft: $draft, destination: $destination, destinations: destinations) {
                        withAnimation(.snappy) { step = .history }
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
        .onAppear {
            if let startingKind, step == .kind, draft.make.isEmpty { pick(startingKind) }
        }
    }

    private func pick(_ kind: VehicleKind) {
        draft.kind = kind
        draft.powertrain = kind.defaultPowertrain
        draft.meter = Locale.current.measurementSystem == .metric && kind.defaultMeter == .miles ? .kilometers : kind.defaultMeter
        draft.tint = freshTint(for: kind)
        step = .details
    }

    /// The first few core jobs, plus any seasonal one (winterize, layup),
    /// which would otherwise never get a first reminder.
    private var coreItems: [CatalogItem] {
        let core = MaintenanceCatalog.items(for: draft.kind, powertrain: draft.powertrain, year: draft.year, traits: draft.traits, drive: draft.drive)
            .filter { $0.isCore && (($0.months ?? 0) > 0 || $0.miles != nil || $0.hours != nil) }
        let first = Array(core.prefix(4))
        let seasonal = core.filter { Self.seasonalKeys.contains($0.key) && !first.contains($0) }
        return first + seasonal
    }

    static let seasonalKeys: Set<String> = ["winterize", "layup", "storage", "commission"]

    private var destinations: [Garage] {
        let joined = garage.joinedGarages
        guard !joined.isEmpty else { return [] }
        return [garage.ownGarage].compactMap { $0 } + joined
    }

    /// The kind's own color unless another vehicle already wears it, so two
    /// cars don't end up the same navy tag.
    private func freshTint(for kind: VehicleKind) -> VehicleTint {
        let used = Set(garage.vehicles.map(\.tint))
        let preferred = VehicleTint.defaultTint(for: kind)
        guard used.contains(preferred) else { return preferred }
        return VehicleTint.allCases.first { !used.contains($0) && $0 != .cream && $0 != .silver && $0 != .white } ?? preferred
    }

    private func finish() {
        let vehicle = garage.addVehicle(draft, to: destination)
        AppGroup.defaults.set(true, forKey: AppGroup.Key.hasCompletedSetup)
        Haptics.success()
        // Reminders are the point of a schedule, so ask right after the first
        // vehicle, when the reason is obvious.
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            let scheduler = ReminderScheduler.shared
            if await scheduler.authorizationStatus() == .notDetermined, await scheduler.requestAuthorization() {
                scheduler.schedule(for: garage)
            }
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 100), spacing: Theme.stackGap)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionGap) {
                Text("What are you adding?")
                    .font(Theme.title(28))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, Theme.xs)
                ForEach(VehicleKind.pickerSections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Eyebrow(text: section.title)
                        LazyVGrid(columns: columns, spacing: Theme.stackGap) {
                            ForEach(section.kinds) { kind in
                                Button {
                                    Haptics.selected()
                                    pick(kind)
                                } label: {
                                    let layout = dynamicTypeSize.isAccessibilitySize
                                        ? AnyLayout(HStackLayout(spacing: Theme.sm))
                                        : AnyLayout(VStackLayout(spacing: Theme.xs))
                                    layout {
                                        Image(systemName: kind.symbol)
                                            .font(.system(size: 26))
                                            .foregroundStyle(VehicleTint.defaultTint(for: kind).isLight ? Theme.brass : VehicleTint.defaultTint(for: kind).color)
                                            .frame(width: dynamicTypeSize.isAccessibilitySize ? 44 : nil, height: 32)
                                        Text(kind.title)
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                                            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .center)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                                    }
                                    .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? Theme.md : 0)
                                    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? Theme.sm : 0)
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
    var title: String?
    /// Someone else's vehicle: its meter is theirs to change.
    var meterLocked = false
    /// A new vehicle guesses its powertrain from the make and model until the
    /// person picks one; an edit never second-guesses what's saved.
    var infersPowertrain = true
    var destination: Binding<Garage?>?
    var destinations: [Garage] = []
    /// Purchase date and price, for an edit.
    var showsOwnership = false
    let next: () -> Void

    @State private var powertrainPicked = false
    @FocusState private var focus: Field?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var lookingUp = false
    @State private var lookupMessage: String?
    @State private var decoded: DecodedVIN?
    @State private var modelSuggestions: [String] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var yearValue: Double?
    @State private var reading: Double?

    var body: some View {
        Form {
            if let destination, destinations.count > 1 {
                Section {
                    Picker("Add to", selection: Binding(
                        get: { destination.wrappedValue ?? destinations.first },
                        set: { destination.wrappedValue = $0 }
                    )) {
                        ForEach(destinations, id: \.objectID) { option in
                            Text(option.displayName).tag(Optional(option))
                        }
                    }
                } footer: {
                    Text("Vehicles in a shared garage show up for everyone in it.")
                }
            }
            Section {
                let stacked = dynamicTypeSize.isAccessibilitySize
                let header = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.sm)) : AnyLayout(HStackLayout(spacing: Theme.sm))
                header {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill((draft.tint ?? .defaultTint(for: draft.kind)).color)
                            .tintOutline(draft.tint ?? .defaultTint(for: draft.kind), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        if let data = draft.photo, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            Image(systemName: draft.kind.symbol).font(.title).foregroundStyle((draft.tint ?? .defaultTint(for: draft.kind)).foreground)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .dynamicTypeSize(.large)
                    VStack(alignment: .leading, spacing: 4) {
                        // The nav bar already names the kind; at large sizes
                        // the second copy only crowds the photo button.
                        if !stacked { Text(draft.kind.title).font(Theme.title(22)) }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(draft.photo == nil ? "Add a photo" : "Change photo").font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if draft.kind.hasNHTSARecords {
                Section {
                    HStack {
                        TextField("VIN (optional)", text: $draft.vin)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.body.monospacedDigit())
                        ScanFieldButton(kind: .vin) { vin in
                            draft.vin = vin
                            Task { await lookUp() }
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
                    if let lookupMessage { Text(lookupMessage) } else if shortVIN {
                        Text("VINs before 1981 are shorter and can't be looked up, so fill in the details below. It's saved as typed.")
                    } else {
                        Text("On the driver's side of the windshield or the door jamb. The year, make, model and engine fill in from NHTSA.")
                    }
                }
            }

            Section {
                LabeledContent("Year") {
                    NumberField(title: "Year", value: $yearValue, grouping: false)
                        .multilineTextAlignment(.trailing)
                }
                textRow("Make", prompt: "Make", text: $draft.make, field: .make)
                if draft.make.isEmpty, !Makes.common(for: draft.kind).isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Makes.common(for: draft.kind), id: \.self) { make in
                                SuggestionChip(make) {
                                    draft.make = make
                                    Haptics.selected()
                                }
                            }
                        }
                    }
                }
                textRow("Model", prompt: "Model", text: $draft.model, field: .model)
                if !modelMatches.isEmpty, focus != .model {
                    modelChips
                }
                textRow("Trim", prompt: "Optional", text: $draft.trim, field: .trim)
                textRow("Nickname", prompt: "Optional", text: $draft.nickname, field: .nickname)
            } header: {
                Text("Vehicle")
            } footer: {
                if yearOutOfRange { Text("Enter a year between 1900 and \(Self.maxYear), or leave it empty.") }
            }
            .toolbar {
                if focus == .model, !modelMatches.isEmpty {
                    ToolbarItem(placement: .keyboard) { modelChips }
                }
            }

            Section {
                if draft.kind.powertrainChoices.count > 1 {
                    Picker("Powertrain", selection: Binding(
                        get: { draft.powertrain },
                        set: { draft.powertrain = $0; powertrainPicked = true }
                    )) {
                        ForEach(draft.kind.powertrainChoices) { Text($0.title).tag($0) }
                    }
                }
                Picker("Meter", selection: $draft.meter) {
                    ForEach(MeterUnit.allCases) { Text($0.title).tag($0) }
                }
                .disabled(meterLocked)
                if draft.meter.hasReading {
                    LabeledContent("Current \(draft.meter.meterName.lowercased())") {
                        HStack(spacing: Theme.xs) {
                            NumberField(title: "0", value: $reading, suffix: draft.meter.short, allowsDecimal: draft.meter == .hours)
                                .multilineTextAlignment(.trailing)
                            ScanFieldButton(kind: .reading(last: 0, meter: draft.meter)) { reading = Double($0) }
                        }
                    }
                    Picker(draft.meter == .hours ? "Hours a year" : "Usual use", selection: $draft.yearlyUse) {
                        Text("Not sure").tag(0.0)
                        ForEach(draft.meter.yearlyUseChoices, id: \.self) { value in
                            Text(yearlyUseLabel(value)).tag(value)
                        }
                        if draft.yearlyUse > 0, !draft.meter.yearlyUseChoices.contains(draft.yearlyUse) {
                            Text(yearlyUseLabel(draft.yearlyUse)).tag(draft.yearlyUse)
                        }
                    }
                }
                if draft.meter.hasReading || draft.kind.offersAuxMeter {
                    Toggle(draft.kind.offersAuxMeter ? "Second meter" : "Second meter (track hours)", isOn: Binding(
                        get: { !draft.auxMeterName.isEmpty },
                        set: { on in
                            let suggestion = draft.kind.auxMeterSuggestions.first
                            draft.auxMeterName = on ? (suggestion?.name ?? "Engine") : ""
                            if on { draft.auxMeter = suggestion?.unit ?? .hours }
                        }
                    ))
                    if !draft.auxMeterName.isEmpty {
                        LabeledContent("Name") {
                            TextField(draft.kind.auxMeterSuggestions.first?.name ?? "Engine", text: $draft.auxMeterName)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.words)
                        }
                        Picker("Counts", selection: $draft.auxMeter) {
                            ForEach([MeterUnit.hours, .miles, .kilometers]) { Text($0.title).tag($0) }
                        }
                    }
                }
            } header: {
                Text("Engine and meter")
            } footer: {
                Text(meterFooter)
            }

            if !VehicleTrait.choices(for: draft.kind).isEmpty {
                Section {
                    if draft.kind == .motorcycle, draft.powertrain != .electric {
                        Picker("Final drive", selection: Binding(
                            get: { draft.drive ?? .chain },
                            set: { draft.drive = $0 }
                        )) {
                            ForEach(FinalDrive.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    ForEach(VehicleTrait.choices(for: draft.kind)) { trait in
                        Toggle(isOn: Binding(
                            get: { draft.traits.contains(trait) },
                            set: { on in if on { draft.traits.insert(trait) } else { draft.traits.remove(trait) } }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trait.title)
                                Text(trait.detail).font(.footnote).foregroundStyle(Theme.secondaryInk)
                            }
                        }
                        .accessibilityIdentifier("trait.\(trait.rawValue)")
                    }
                } header: {
                    Text("How it's used")
                } footer: {
                    Text("Adds the jobs that go with it. Change it any time.")
                }
            }

            if showsOwnership {
                Section {
                    Toggle("Purchase date", isOn: Binding(
                        get: { draft.purchaseDate != nil },
                        set: { draft.purchaseDate = $0 ? (draft.purchaseDate ?? .now) : nil }
                    ))
                    if let date = draft.purchaseDate {
                        DatePicker("Bought on", selection: Binding(get: { date }, set: { draft.purchaseDate = $0 }), in: ...Date.now, displayedComponents: .date)
                    }
                    LabeledContent("Price paid") {
                        NumberField(title: "Optional", value: Binding(
                            get: { draft.purchasePrice > 0 ? draft.purchasePrice : nil },
                            set: { draft.purchasePrice = max(0, $0 ?? 0) }
                        ), isCurrency: true)
                        .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Ownership")
                }
            }

            Section {
                LabeledContent(draft.kind.registrationLabel) {
                    HStack(spacing: Theme.xs) {
                        TextField("Optional", text: $draft.plate)
                            .textInputAutocapitalization(.characters)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("add.plate")
                        ScanFieldButton(kind: .plate) { draft.plate = $0 }
                    }
                }
                if !draft.kind.hasNHTSARecords {
                    LabeledContent(draft.kind.identifierLabel) {
                        HStack(spacing: Theme.xs) {
                            TextField("Optional", text: $draft.vin)
                                .textInputAutocapitalization(.characters)
                                .multilineTextAlignment(.trailing)
                                .font(.body.monospacedDigit())
                            ScanFieldButton(kind: .text) { draft.vin = $0.uppercased() }
                        }
                    }
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
                                    .tintOutline(tint, in: Circle(), lineWidth: 1)
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
                if yearOutOfRange { Text("Fix the year first.") } else if !isValid { Text("Give it a make, a model or a nickname.") }
            }
        }
        .paperBackground()
        .navigationTitle(title ?? draft.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            yearValue = draft.year > 0 ? Double(draft.year) : nil
            reading = draft.reading > 0 ? draft.reading : nil
        }
        .onChange(of: "\(draft.make)|\(draft.model)|\(draft.trim)") { _, _ in inferPowertrain() }
        .onChange(of: yearValue) { _, _ in commitNumbers() }
        .onChange(of: reading) { _, _ in commitNumbers() }
        .onChange(of: draft.meter) { old, new in
            // Miles and kilometers convert; hours can't, so the field clears.
            if let value = reading, let converted = old.convert(value, to: new) {
                reading = converted.rounded()
            } else {
                reading = nil
            }
            draft.yearlyUse = old.convert(draft.yearlyUse, to: new).flatMap { converted in
                new.yearlyUseChoices.min { abs($0 - converted) < abs($1 - converted) }
            } ?? 0
        }
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
    }

    enum Field: Hashable { case make, model, trim, nickname }

    /// A label that stays put once the field is filled, and Next on the
    /// keyboard to the following one.
    private func textRow(_ label: String, prompt: String, text: Binding<String>, field: Field) -> some View {
        LabeledContent(label) {
            TextField(label, text: text, prompt: Text(prompt))
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                .textInputAutocapitalization(.words)
                .focused($focus, equals: field)
                .submitLabel(field == .nickname ? .done : .next)
                .onSubmit {
                    switch field {
                    case .make: focus = .model
                    case .model: focus = .trim
                    case .trim: focus = .nickname
                    case .nickname: focus = nil
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { focus = field }
    }

    private var modelMatches: [String] {
        modelSuggestions.filter { !draft.model.isEmpty && $0.lowercased().hasPrefix(draft.model.lowercased()) && $0.lowercased() != draft.model.lowercased() }
    }

    private var modelChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(modelMatches.prefix(8), id: \.self) { model in
                    Button(model) {
                        draft.model = model
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

    private var shortVIN: Bool {
        let cleaned = draft.vin.filter { $0.isLetter || $0.isNumber }
        return cleaned.count >= 5 && cleaned.count < 17
    }

    private func yearlyUseLabel(_ value: Double) -> String {
        let choices = draft.meter.yearlyUseChoices
        let figure = Format.reading(value, draft.meter)
        if value == choices.first { return "Under \(figure) a year" }
        if value == choices.last { return "\(figure) or more" }
        return "About \(figure) a year"
    }

    private func inferPowertrain() {
        guard infersPowertrain, !powertrainPicked,
              let guess = Makes.inferredPowertrain(make: draft.make, model: draft.model, trim: draft.trim),
              draft.kind.powertrainChoices.contains(guess) else { return }
        draft.powertrain = guess
    }

    private var meterFooter: String {
        var text = draft.meter == .hours ? "Engine hours drive the schedule for boats, planes and equipment." : "The schedule picks jobs for this powertrain. You can change any of it later."
        if draft.meter.hasReading { text += " \(draft.meter == .hours ? "Hours a year" : "Usual use") sets due dates until a couple of readings show the real pace." }
        if meterLocked { text = "Only the person who shared this vehicle can change its meter. " + text }
        if draft.kind.offersAuxMeter {
            text += " A second hour meter tracks a generator or second engine on its own schedule."
        }
        return text
    }

    private var isValid: Bool {
        (!draft.make.trimmed.isEmpty || !draft.model.trimmed.isEmpty || !draft.nickname.trimmed.isEmpty) && !yearOutOfRange
    }

    /// Next year's models are on sale from late summer.
    static let maxYear = Calendar.current.component(.year, from: .now) + 1

    /// Typed but not a year the app can use, so it would otherwise be dropped quietly.
    private var yearOutOfRange: Bool {
        guard let yearValue else { return false }
        return !(1900...Self.maxYear).contains(Int(yearValue))
    }

    private func commitNumbers() {
        draft.year = yearValue.map { Int($0) }.flatMap { (1900...Self.maxYear).contains($0) ? $0 : nil } ?? 0
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
            if let powertrain = result.powertrain, draft.kind.powertrainChoices.contains(powertrain) { draft.powertrain = powertrain; powertrainPicked = true }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private func answerChips(for item: CatalogItem, in options: [Answer] = Answer.allCases) -> some View {
        ForEach(options) { answer in
            let chosen = (answers[item.key] ?? .unsure) == answer
            Button {
                Haptics.selected()
                answers[item.key] = answer
            } label: {
                Text(answer.title)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .padding(.horizontal, Theme.xs)
                    .foregroundStyle(chosen ? Theme.onAction : Theme.ink)
                    .background(chosen ? Theme.action : Theme.raised, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(chosen ? .isSelected : [])
            .accessibilityLabel("\(item.name), \(answer.title)")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stackGap) {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text("When were these last done?")
                        .font(Theme.title(28))
                        .foregroundStyle(Theme.ink)
                    Text("Rough is fine. It sets the first due dates; the app learns the rest from what you log.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
                .padding(.top, Theme.xs)
                .padding(.bottom, Theme.xxs)
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Label(item.name, systemImage: item.symbol)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text(Format.interval(distance: item.distanceInterval(for: draft.meter) ?? 0, months: item.months ?? 0, meter: draft.meter, trigger: item.trigger))
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                        // One row, then two, then one chip per line at the
                        // largest text sizes, so nothing is ever cut off.
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: Theme.xs) { answerChips(for: item) }
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: Theme.xs) { answerChips(for: item) }
                                Grid(horizontalSpacing: Theme.xs, verticalSpacing: Theme.xs) {
                                    GridRow { answerChips(for: item, in: [.recently, .months]) }
                                    GridRow { answerChips(for: item, in: [.year, .unsure]) }
                                }
                                VStack(spacing: Theme.xs) { answerChips(for: item) }
                            }
                        }
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
                .padding(.top, Theme.md)
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
    /// Filled before the form first appears, so its year and meter fields
    /// start from the vehicle rather than blank.
    @State private var draft: NewVehicle
    private let original: NewVehicle

    init(vehicle: Vehicle) {
        self.vehicle = vehicle
        let draft = NewVehicle(
            kind: vehicle.kind, powertrain: vehicle.powertrain, meter: vehicle.meter,
            year: Int(vehicle.year), make: vehicle.make ?? "", model: vehicle.model ?? "", trim: vehicle.trim ?? "",
            nickname: vehicle.nickname ?? "", vin: vehicle.vin ?? "", plate: vehicle.plate ?? "",
            reading: vehicle.shownReading, auxMeterName: vehicle.auxMeterName ?? "", auxMeter: vehicle.auxMeter,
            traits: vehicle.traits, drive: vehicle.profile.drive, yearlyUse: vehicle.yearlyUse,
            photo: vehicle.photo, tint: vehicle.tint,
            purchaseDate: vehicle.purchaseDate, purchasePrice: vehicle.purchasePrice
        )
        _draft = State(initialValue: draft)
        original = draft
    }

    @State private var confirmingMeter = false
    @State private var confirmingDiscard = false

    var body: some View {
        NavigationStack {
            VehicleDetailsForm(
                draft: $draft, buttonTitle: "Save", title: "Edit \(vehicle.displayName)",
                meterLocked: garage.isShared(vehicle), infersPowertrain: false, showsOwnership: true, next: attemptSave
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if draft != original { confirmingDiscard = true } else { dismiss() } }
                }
            }
            .discardGuard(isDirty: draft != original, confirming: $confirmingDiscard) { dismiss() }
            .confirmationDialog(meterWarningTitle, isPresented: $confirmingMeter, titleVisibility: .visible) {
                Button("Switch to \(draft.meter.title.lowercased())", role: .destructive, action: save)
                Button("Keep \(vehicle.meter.title.lowercased())", role: .cancel) { draft.meter = vehicle.meter }
            } message: {
                Text(meterWarning)
            }
        }
    }

    /// Miles and kilometers convert cleanly; a switch to or from hours drops
    /// every saved reading, so it asks first.
    private var meterSwitchLosesReadings: Bool {
        draft.meter != vehicle.meter
            && vehicle.meter.convert(1, to: draft.meter) == nil
            && (!vehicle.mainReadings.isEmpty || (vehicle.entries ?? []).contains(where: \.hasReading))
    }

    private var meterWarningTitle: String { "Switch \(vehicle.displayName) to \(draft.meter.title.lowercased())?" }

    private var meterWarning: String {
        let readings = vehicle.mainReadings.count
        let entries = (vehicle.entries ?? []).filter(\.hasReading).count
        var parts: [String] = []
        if readings > 0 { parts.append(readings == 1 ? "1 saved reading" : "\(readings) saved readings") }
        if entries > 0 { parts.append(entries == 1 ? "the \(vehicle.meter.meterName.lowercased()) on 1 entry" : "the \(vehicle.meter.meterName.lowercased()) on \(entries) entries") }
        return "\(vehicle.meter.title) can't convert to \(draft.meter.title.lowercased()), so \(parts.joined(separator: " and ")) will be cleared. Dates, costs and notes stay."
    }

    private func attemptSave() {
        if meterSwitchLosesReadings { confirmingMeter = true } else { save() }
    }

    private func save() {
        let powertrainChanged = vehicle.powertrain != draft.powertrain
        let readingTyped = draft.reading != vehicle.shownReading
        if !garage.isShared(vehicle) { garage.changeMeter(vehicle, to: draft.meter) }
        vehicle.powertrain = draft.powertrain
        vehicle.year = Int16(clamping: draft.year)
        vehicle.make = draft.make.trimmed.nilIfEmpty
        vehicle.model = draft.model.trimmed.nilIfEmpty
        vehicle.trim = draft.trim.trimmed.nilIfEmpty
        vehicle.nickname = draft.nickname.trimmed.nilIfEmpty
        vehicle.vin = draft.vin.trimmed.uppercased().nilIfEmpty
        vehicle.plate = draft.plate.trimmed.uppercased().nilIfEmpty
        vehicle.photo = draft.photo
        vehicle.tint = draft.tint ?? vehicle.tint
        vehicle.yearlyUse = vehicle.meter.hasReading ? draft.yearlyUse : 0
        vehicle.purchaseDate = draft.purchaseDate
        vehicle.purchasePrice = draft.purchasePrice
        garage.saveVehicleEdits()
        let auxName = draft.auxMeterName.trimmed.nilIfEmpty
        if auxName != vehicle.auxMeterName || (auxName != nil && draft.auxMeter != vehicle.auxMeter) {
            garage.setAuxMeter(vehicle, name: auxName, unit: draft.auxMeter)
        }
        garage.setProfile(vehicle, traits: draft.traits, drive: draft.kind == .motorcycle ? draft.drive : nil)
        // Edit sets the meter exactly, so a typo can be walked back.
        if draft.meter.hasReading, readingTyped, draft.reading > 0 {
            garage.correctReading(vehicle, to: draft.reading)
        }
        if powertrainChanged {
            // New powertrain, new core jobs; the old ones stay with their history.
            let core = vehicle.catalogItems.filter(\.isCore)
            garage.addCatalogItems(core, to: vehicle)
            garage.switchOffInapplicableTasks(on: vehicle)
        }
        Haptics.success()
        dismiss()
    }
}
