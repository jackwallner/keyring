import Charts
import PhotosUI
import SwiftUI

// MARK: - Value

/// What it's worth: the price guides for this kind of vehicle, opened with
/// the year, make, model and mileage already filled in, and the figures the
/// owner noted over time.
struct ValueView: View {
    @EnvironmentObject private var garage: GarageStore
    @ObservedObject var vehicle: Vehicle
    @State private var adding = false
    @State private var amount: Double?
    @State private var source = ""

    var body: some View {
        List {
            Section {
                ForEach(ValueSource.sources(for: vehicle)) { source in
                    LinkRow(title: source.name, detail: source.detail, symbol: "safari", url: source.url)
                }
            } header: {
                Text("Check the value")
            } footer: {
                Text(vehicle.descriptor.isEmpty
                     ? "Add the year, make and model so these open on your exact vehicle."
                     : "Opens on the \(vehicle.descriptor)\(vehicle.meter == .miles && vehicle.reading > 0 ? " with \(Format.reading(vehicle.reading, vehicle.meter))" : ""). Keyring isn't affiliated with these guides.")
            }

            Section {
                let valuations = (vehicle.valuations ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                if valuations.count > 1 {
                    Chart(valuations.reversed()) { valuation in
                        LineMark(x: .value("Date", valuation.date ?? .now), y: .value("Value", valuation.amount))
                            .foregroundStyle(Theme.brass)
                        PointMark(x: .value("Date", valuation.date ?? .now), y: .value("Value", valuation.amount))
                            .foregroundStyle(Theme.brass)
                    }
                    .frame(height: 140)
                    .padding(.vertical, Theme.xs)
                }
                ForEach(valuations) { valuation in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(Format.money(valuation.amount)).font(Theme.figure(17))
                            Text([valuation.source, valuation.date.map(Format.shortDate)].compactMap { $0 }.joined(separator: " · "))
                                .font(.footnote).foregroundStyle(Theme.secondaryInk)
                        }
                    }
                }
                .onDelete { offsets in offsets.map { valuations[$0] }.forEach(garage.delete) }
                Button { adding = true } label: { Label("Note a value", systemImage: "plus") }
            } header: {
                Text("Your notes")
            } footer: {
                Text("Jot down a quote or a trade-in offer to watch it over time. It goes in the Service Record if you sell.")
            }
        }
        .paperBackground()
        .navigationTitle("What it's worth")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    LabeledContent("Value") {
                        NumberField(title: "0", value: $amount, isCurrency: true)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Source, such as KBB trade-in", text: $source)
                }
                .paperBackground()
                .navigationTitle("Note a value")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if let amount { garage.addValuation(amount, source: source, to: vehicle) }
                            amount = nil
                            source = ""
                            adding = false
                        }
                        .disabled(amount == nil)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Parts and tools

/// The parts and tools for the jobs coming up, most urgent first.
struct GearView: View {
    @EnvironmentObject private var garage: GarageStore
    let vehicle: Vehicle

    var body: some View {
        let dues = garage.dues(for: vehicle)
        let groups = dues.compactMap { due -> (TaskDue, [GearSuggestion])? in
            guard let key = due.catalogKey,
                  let item = MaintenanceCatalog.item(key: key, kind: vehicle.kind, powertrain: vehicle.powertrain, year: Int(vehicle.year)),
                  !item.gear.isEmpty else { return nil }
            return (due, item.gear)
        }
        List {
            if groups.isEmpty {
                EmptyStateView(symbol: "wrench.and.screwdriver", title: "Nothing to shop for", message: "Jobs on the schedule with parts or tools show their shopping list here.")
                    .listRowBackground(Color.clear)
            }
            ForEach(groups, id: \.0.id) { due, gear in
                Section {
                    ForEach(Array(gear.enumerated()), id: \.offset) { _, suggestion in
                        let query = AmazonLinks.resolve(suggestion.query, vehicle: vehicle)
                        LinkRow(title: suggestion.title, detail: query, symbol: "cart", url: AmazonLinks.search(query))
                    }
                } header: {
                    HStack {
                        StatusDot(status: due.result.status)
                        Text(due.name)
                        Spacer()
                        if due.result.status <= .dueSoon {
                            Text(due.result.status.label).foregroundStyle(due.result.status.color)
                        }
                    }
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text(AmazonLinks.isAffiliate
                     ? "Opens Amazon search. \(AmazonLinks.disclosure) Check fitment for your exact vehicle before buying."
                     : "Opens Amazon search. Check fitment for your exact vehicle before buying.")
            }
        }
        .paperBackground()
        .navigationTitle("Parts and tools")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Upgrades

struct UpgradesView: View {
    let vehicle: Vehicle

    var body: some View {
        let upgrades = UpgradeCatalog.upgrades(for: vehicle)
        List {
            ForEach(Upgrade.Category.allCases, id: \.self) { category in
                let items = upgrades.filter { $0.category == category }
                if !items.isEmpty {
                    Section(category.title) {
                        ForEach(items) { upgrade in
                            let query = AmazonLinks.resolve(upgrade.query, vehicle: vehicle)
                            LinkRow(title: upgrade.title, detail: upgrade.why, symbol: upgrade.symbol, url: AmazonLinks.search(query))
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text(AmazonLinks.isAffiliate
                     ? "Picked from what owners recommend to each other. \(AmazonLinks.disclosure)"
                     : "Picked from what owners recommend to each other. Opens Amazon search.")
            }
        }
        .paperBackground()
        .navigationTitle("Upgrades")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Clubs

struct ClubsView: View {
    let vehicle: Vehicle

    var body: some View {
        let clubs = ClubDirectory.clubs(for: vehicle)
        List {
            ForEach([Club.Kind.club, .organization, .forum, .subreddit], id: \.self) { kind in
                let items = clubs.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section(kind == .club ? "Clubs" : kind == .organization ? "Organizations" : kind == .forum ? "Forums" : "Reddit") {
                        ForEach(items) { club in
                            LinkRow(title: club.name, detail: club.detail, symbol: club.kind.symbol, url: club.url)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text(vehicle.make == nil
                     ? "Add the make and model to see clubs and forums for yours."
                     : "Independent communities. Keyring isn't affiliated with any of them.")
            }
        }
        .paperBackground()
        .navigationTitle("Clubs and forums")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Recalls

/// NHTSA covers vehicles sold in the US. Elsewhere the list is still useful
/// for the same model, but it says whose list it is and points home.
enum RecallRegion {
    static var region: String? { Locale.current.region?.identifier }
    static var isUS: Bool { region == nil || region == "US" || region == "PR" }

    static var localLookup: (title: String, url: URL)? {
        switch region {
        case "CA": ("Transport Canada recalls", URL(string: "https://tc.canada.ca/en/road-transportation/defects-recalls-vehicles-tires-child-car-seats")!)
        case "GB": ("DVSA vehicle recalls", URL(string: "https://www.check-vehicle-recalls.service.gov.uk")!)
        case "AU": ("Australian recalls", URL(string: "https://www.productsafety.gov.au/recalls")!)
        default: nil
        }
    }
}

struct RecallsView: View {
    @EnvironmentObject private var garage: GarageStore
    @ObservedObject var vehicle: Vehicle
    @State var recalls: [Recall]
    @State private var loading = false
    @State private var failed = false
    @State private var dismissed: Set<String> = []
    @State private var fixing: Recall?

    var body: some View {
        List {
            if vehicle.year <= 0 || vehicle.make == nil || vehicle.model == nil {
                EmptyStateView(symbol: "exclamationmark.shield", title: "Add year, make and model", message: "Keyring checks NHTSA's recall database once it knows exactly what you drive.")
                    .listRowBackground(Color.clear)
            } else if loading && recalls.isEmpty {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if failed && recalls.isEmpty {
                EmptyStateView(symbol: "wifi.exclamationmark", title: "Couldn't reach NHTSA", message: "Check your connection and pull to try again.")
                    .listRowBackground(Color.clear)
            } else if recalls.isEmpty {
                EmptyStateView(symbol: "checkmark.shield", title: "No recalls on file", message: "NHTSA lists no safety recalls for the \(vehicle.descriptor). Keyring keeps checking and lets you know if one is issued.")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    if let vin = vehicle.vin {
                        LinkRow(title: "Check which apply to this VIN", detail: vin, symbol: "magnifyingglass", url: URL(string: "https://www.nhtsa.gov/recalls?vin=\(vin)")!)
                    } else {
                        LinkRow(title: "Check which apply to yours", detail: "Enter your VIN at nhtsa.gov", symbol: "magnifyingglass", url: URL(string: "https://www.nhtsa.gov/recalls")!)
                    }
                } footer: {
                    Text("These recalls cover every \(vehicle.descriptor). Many apply only to certain build dates, and a dealer may already have fixed yours. Your VIN shows which are open.")
                }
                Section {
                    ForEach(recalls) { recall in
                        RecallRow(
                            recall: recall,
                            fix: fixEntry(for: recall),
                            dismissed: dismissed.contains(recall.campaign),
                            logFix: { fixing = recall },
                            setDismissed: { value in
                                RecallLedger.setReviewed(recall.campaign, value, for: vehicle.id)
                                dismissed = RecallLedger.reviewed(for: vehicle.id)
                            }
                        )
                    }
                } header: {
                    Text(Format.count(recalls.count, "recall", "recalls") + " for this model")
                } footer: {
                    Text(RecallRegion.isUS
                         ? "From NHTSA. Recall repairs are free at a dealer. Logging the fix adds it to the history, so everyone in the garage and any buyer sees it was done."
                         : "From NHTSA, the US safety agency. Models sold elsewhere often share these recalls, but check your own country's list too. Logging a fix adds it to the history.")
                }
            }
            if !RecallRegion.isUS, let local = RecallRegion.localLookup {
                Section {
                    LinkRow(title: local.title, detail: "Your country's official list", symbol: "globe", url: local.url)
                }
            }
        }
        .paperBackground()
        .navigationTitle(RecallRegion.isUS ? "Safety recalls" : "US safety recalls")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
            dismissed = RecallLedger.reviewed(for: vehicle.id)
            if recalls.isEmpty { await load() }
        }
        .sheet(item: $fixing) { recall in
            LogServiceView(vehicle: vehicle, recall: recall)
        }
    }

    private func fixEntry(for recall: Recall) -> ServiceEntry? {
        _ = garage.revision
        return (vehicle.entries ?? []).first { $0.recallCampaign == recall.campaign && !$0.isDeleted }
    }

    private func load() async {
        guard vehicle.year > 0, let make = vehicle.make, let model = vehicle.model else { return }
        loading = true
        do {
            recalls = try await NHTSAClient.recalls(year: Int(vehicle.year), make: make, model: model)
            RecallWatcher.record(recalls, for: vehicle)
            failed = false
        } catch {
            failed = true
        }
        loading = false
    }
}

private struct RecallRow: View {
    let recall: Recall
    let fix: ServiceEntry?
    let dismissed: Bool
    let logFix: () -> Void
    let setDismissed: (Bool) -> Void
    @State private var expanded = false

    private var closed: Bool { fix != nil || dismissed }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.xs) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if !closed, recall.parkIt || recall.parkOutside {
                                Text(recall.parkIt ? "DO NOT DRIVE" : "PARK OUTSIDE")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.overdue, in: Capsule())
                            }
                            Text(recall.componentTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(closed ? Theme.secondaryInk : Theme.ink)
                        }
                        Text(statusLine)
                            .font(.caption)
                            .foregroundStyle(fix != nil ? Theme.good : Theme.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.footnote).foregroundStyle(Theme.faintInk)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                Group {
                    Text(recall.summary)
                    if !recall.consequence.isEmpty { Text("Risk: \(recall.consequence)").foregroundStyle(Theme.overdue) }
                    if !recall.remedy.isEmpty { Text("Fix: \(recall.remedy)") }
                }
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                Link("Read it at NHTSA", destination: recall.nhtsaURL).font(.footnote.weight(.semibold))
            }
            if fix == nil {
                HStack(spacing: Theme.md) {
                    if dismissed {
                        Button("Undo") { setDismissed(false) }
                    } else {
                        Button("Log the fix", action: logFix)
                        Button("Doesn't apply") { setDismissed(true) }
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusLine: String {
        if let fix {
            let date = fix.date.map(Format.shortDate) ?? ""
            return ["Fixed \(date)", fix.shop].compactMap { $0 }.joined(separator: " · ")
        }
        let base = [recall.campaign, recall.reported.map(Format.shortDate)].compactMap { $0 }.joined(separator: " · ")
        return dismissed ? "Doesn't apply · \(base)" : base
    }
}

// MARK: - Photos

/// Others like it: owner photos shared through Keyring and freely licensed
/// reference shots, plus this vehicle's own photo album from its history.
struct GalleryView: View {
    @EnvironmentObject private var community: CommunityPhotos
    @EnvironmentObject private var garage: GarageStore
    @ObservedObject var vehicle: Vehicle

    @State private var photos: [CommunityPhoto] = []
    @State private var loading = true
    @State private var viewing: CommunityPhoto?
    @State private var showingTerms = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingPicker = false
    @State private var shareMessage: String?
    @State private var reporting: CommunityPhoto?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                ownSection
                VStack(alignment: .leading, spacing: Theme.sm) {
                    SectionHeader(title: vehicle.makeAndModel.isEmpty ? "Others like it" : "Other \(vehicle.makeAndModel)s")
                    if loading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    } else if photos.isEmpty {
                        Text(vehicle.makeAndModel.isEmpty
                             ? "Add the make and model to see photos of others like yours."
                             : "No photos yet. Share yours and it'll be the first.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                            .card()
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.xs), GridItem(.flexible(), spacing: Theme.xs)], spacing: Theme.xs) {
                            ForEach(photos) { photo in
                                Button { viewing = photo } label: { PhotoTile(photo: photo) }
                                    .buttonStyle(PressableStyle())
                                    .contextMenu { moderationButtons(photo) }
                            }
                        }
                    }
                    Button {
                        if community.hasAcceptedTerms { showingPicker = true } else { showingTerms = true }
                    } label: {
                        Label("Share a photo of yours", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(vehicle.makeAndModel.isEmpty)
                    if let shareMessage {
                        Text(shareMessage).font(.footnote).foregroundStyle(Theme.secondaryInk)
                    }
                    Text("Owner photos are shared publicly with other Keyring users who have the same make and model. Reference photos come from Wikimedia Commons under their own licenses.")
                        .font(.caption)
                        .foregroundStyle(Theme.faintInk)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.xxl)
        }
        .paperBackground()
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: community.blockedAuthors.count + community.reportedPhotos.count) {
            photos = await community.photos(for: vehicle)
            loading = false
        }
        .sheet(item: $viewing) { photo in PhotoViewer(photo: photo, onReport: { reporting = photo; viewing = nil }, onBlock: { community.block(photo); viewing = nil }) }
        .sheet(isPresented: $showingTerms) {
            CommunityTermsSheet {
                community.acceptTerms()
                showingTerms = false
                showingPicker = true
            }
        }
        .photosPicker(isPresented: $showingPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                pickerItem = nil
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                shareMessage = "Sharing…"
                do {
                    try await community.share(data, caption: vehicle.descriptor, for: vehicle)
                    shareMessage = "Shared. Thanks for adding to the gallery."
                    photos = await community.photos(for: vehicle)
                } catch let error as CommunityPhotos.ShareError {
                    shareMessage = error.message
                } catch {
                    shareMessage = CommunityPhotos.ShareError.failed.message
                }
            }
        }
        .confirmationDialog("Report this photo?", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }), titleVisibility: .visible) {
            ForEach(["Not this vehicle", "Offensive or inappropriate", "Personal information", "Spam"], id: \.self) { reason in
                Button(reason) {
                    if let reporting { community.report(reporting, reason: reason) }
                    reporting = nil
                }
            }
        } message: {
            Text("It's hidden for you right away and reviewed within 24 hours.")
        }
    }

    @ViewBuilder
    private var ownSection: some View {
        let own = vehicle.sortedEntries.flatMap { $0.sortedAttachments.filter { !$0.isReceipt } }
        if vehicle.photo != nil || !own.isEmpty {
            VStack(alignment: .leading, spacing: Theme.sm) {
                SectionHeader(title: "Yours")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.xs) {
                        if let data = vehicle.photo, let image = ImageTools.thumbnail(data, maxDimension: 500) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 150, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        ForEach(own.prefix(20)) { attachment in
                            if let image = ImageTools.thumbnail(attachment.data, maxDimension: 500) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 150, height: 110)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func moderationButtons(_ photo: CommunityPhoto) -> some View {
        if photo.isOwnerPhoto {
            Button(role: .destructive) { reporting = photo } label: { Label("Report", systemImage: "flag") }
            Button(role: .destructive) { community.block(photo) } label: { Label("Block this person", systemImage: "hand.raised") }
        } else {
            Button(role: .destructive) { reporting = photo } label: { Label("Hide, not this vehicle", systemImage: "eye.slash") }
        }
    }
}

private struct PhotoTile: View {
    let photo: CommunityPhoto

    var body: some View {
        // The image fills a fixed box; on its own, scaledToFill widens the
        // grid cell past the screen.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .overlay {
                AsyncImage(url: photo.imageURL) { phase in
                    switch phase {
                    case let .success(image): image.resizable().scaledToFill()
                    case .failure: Theme.raised.overlay(Image(systemName: "photo").foregroundStyle(Theme.faintInk))
                    default: Theme.raised
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if photo.isOwnerPhoto {
                Image(systemName: "person.crop.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(6)
            }
        }
        .accessibilityLabel(photo.caption)
    }
}

private struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let photo: CommunityPhoto
    let onReport: () -> Void
    let onBlock: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.md) {
                AsyncImage(url: photo.imageURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(photo.caption).font(.headline).foregroundStyle(Theme.ink)
                Text(photo.credit).font(.footnote).foregroundStyle(Theme.secondaryInk)
                if case let .commons(page, _, _) = photo.source {
                    Button("View on Wikimedia Commons") { openURL(page) }.font(.footnote.weight(.semibold))
                }
                Spacer()
            }
            .padding(Theme.margin)
            .paperBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive, action: onReport) { Label(photo.isOwnerPhoto ? "Report" : "Hide, not this vehicle", systemImage: "flag") }
                        if photo.isOwnerPhoto {
                            Button(role: .destructive, action: onBlock) { Label("Block this person", systemImage: "hand.raised") }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
    }
}

/// Agreed once before the first share (App Review 1.2).
struct CommunityTermsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let accept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.md) {
                    Text("Before you share")
                        .font(Theme.title(26))
                    Text("Photos you share are public to other Keyring users who own the same make and model.")
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        Label("Only photos of the vehicle itself, that you took or have the right to share.", systemImage: "car.side")
                        Label("No people, plates you don't own, addresses or anything personal.", systemImage: "person.crop.circle.badge.xmark")
                        Label("Nothing offensive, hateful or unrelated. There's no tolerance for objectionable content or abusive users.", systemImage: "hand.raised")
                        Label("Anyone can report a photo. Reported photos are hidden and reviewed within 24 hours, and people who break these rules are removed.", systemImage: "flag")
                    }
                    .font(.subheadline)
                    Link("Read the community guidelines", destination: AppLinks.communityGuidelines).font(.subheadline.weight(.semibold))
                    Button("I agree") { accept() }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, Theme.sm)
                }
                .padding(Theme.margin)
            }
            .paperBackground()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Insights

/// Where the money goes. Keyring Pro; free owners see a teaser.
struct InsightsView: View {
    @EnvironmentObject private var garage: GarageStore
    @EnvironmentObject private var store: StoreService
    var vehicles: [Vehicle]? = nil
    @State private var showingPaywall = false

    var body: some View {
        if AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts) {
            EmptyStateView(symbol: "eye.slash", title: "Costs are hidden", message: "Costs are hidden on this iPhone. Turn them back on in Settings to see where the money goes.")
                .frame(maxHeight: .infinity)
                .paperBackground()
                .navigationTitle("Insights")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }

    private var content: some View {
        let list = vehicles ?? garage.vehicles
        let insights = CostInsights.compute(vehicles: list)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Last 12 months")
                    Text(Format.money(insights.lastTwelveMonths)).font(Theme.figure(40, weight: .bold)).foregroundStyle(Theme.ink)
                    Text("\(Format.money(insights.allTime)) all time\(insights.costPerDistance.map { " · \(Format.money($0, code: Locale.current.currency?.identifier ?? "USD")) per \(insights.distanceUnit)" } ?? "")")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
                .padding(.top, Theme.sm)

                VStack(alignment: .leading, spacing: Theme.sm) {
                    Eyebrow(text: "By month")
                    Chart(insights.months) { month in
                        BarMark(x: .value("Month", month.start, unit: .month), y: .value("Spent", month.total))
                            .foregroundStyle(Theme.brass)
                            .cornerRadius(3)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.narrow)) } }
                    .frame(height: 160)
                }
                .card()

                if insights.byVehicle.count > 1 {
                    breakdown("By vehicle", insights.byVehicle, total: insights.lastTwelveMonths)
                }
                if !insights.byJob.isEmpty {
                    breakdown("Biggest jobs", insights.byJob, total: insights.lastTwelveMonths)
                }
                if insights.lastTwelveMonths > 0 {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Eyebrow(text: "Maintenance vs. repairs")
                            Text("\(Format.money(insights.lastTwelveMonths - insights.repairs)) planned · \(Format.money(insights.repairs)) unplanned")
                                .font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                        Image(systemName: EntryKind.repair.symbol).foregroundStyle(Theme.brass)
                    }
                    .card()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Eyebrow(text: "Done yourself")
                            Text("\(Int((insights.diyShare * 100).rounded()))% of the last 12 months' spending")
                                .font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                        Image(systemName: "wrench.and.screwdriver.fill").foregroundStyle(Theme.brass)
                    }
                    .card()
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.xxl)
            .blur(radius: store.isPro ? 0 : 7)
            .allowsHitTesting(store.isPro)
            .overlay {
                if !store.isPro {
                    VStack(spacing: Theme.sm) {
                        Image(systemName: "lock.fill").font(.title2).foregroundStyle(Theme.brass)
                        Text("See where the money goes").font(Theme.title(22))
                        Text("Spending by month, by vehicle and by job, and your real cost per mile.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                            .multilineTextAlignment(.center)
                        Button("Unlock with Keyring Pro") { showingPaywall = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(Theme.xl)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 8)
                    .padding(Theme.margin)
                }
            }
        }
        .paperBackground()
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywall) { PaywallView(focus: .insights) }
    }

    private func breakdown(_ title: String, _ slices: [CostInsights.Slice], total: Double) -> some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Eyebrow(text: title)
            ForEach(slices) { slice in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(slice.name).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(Format.money(slice.total)).font(Theme.figure(15, weight: .medium))
                    }
                    GeometryReader { geometry in
                        Capsule().fill(Theme.brass.opacity(0.8))
                            .frame(width: max(4, geometry.size.width * (total > 0 ? slice.total / total : 0)))
                    }
                    .frame(height: 5)
                }
            }
        }
        .card()
    }
}

/// The garage's spending line, which opens Insights.
struct InsightsTeaser: View {
    @EnvironmentObject private var garage: GarageStore
    @EnvironmentObject private var store: StoreService

    var body: some View {
        let hideCosts = AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts)
        if !hideCosts, garage.vehicles.contains(where: { !($0.entries ?? []).isEmpty }) {
            let insights = CostInsights.compute(vehicles: garage.vehicles)
            NavigationLink {
                InsightsView()
            } label: {
                HStack(spacing: Theme.sm) {
                    Image(systemName: "chart.bar.fill").font(.title3).foregroundStyle(Theme.brass)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spent in the last 12 months").font(.footnote).foregroundStyle(Theme.secondaryInk)
                        Text(store.isPro ? Format.money(insights.lastTwelveMonths) : "See where the money goes")
                            .font(store.isPro ? Theme.figure(20) : .subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    if !store.isPro { Image(systemName: "lock.fill").font(.footnote).foregroundStyle(Theme.faintInk) }
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.faintInk)
                }
                .card()
            }
            .buttonStyle(PressableStyle())
        }
    }
}
