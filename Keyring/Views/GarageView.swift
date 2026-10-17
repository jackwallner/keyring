import CoreData
import SwiftUI

/// Home: every vehicle as a key tag, the one thing each needs next, and
/// anything overdue across the whole garage up top.
struct GarageView: View {
    @EnvironmentObject private var garage: GarageStore
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var sharing: SharingService
    @ObservedObject private var router = NotificationRouter.shared

    @State private var path = NavigationPath()
    @State private var showingAdd = false
    @State private var showingPaywall = false
    @State private var showingFamily = false
    @State private var logging: LogRequest?
    @State private var showingAllAttention = false
    @State private var routedScreenshot = false

    var body: some View {
        NavigationStack(path: $path) { content }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.md) {
                if garage.vehicles.isEmpty {
                    EmptyStateView(
                        symbol: "key.horizontal",
                        title: "Your garage is empty",
                        message: "Add a car, truck, boat, bike, RV or plane. Keyring builds its maintenance schedule for you.",
                        actionTitle: "Add a vehicle",
                        action: addVehicle
                    )
                    .padding(.top, Theme.xxl)
                } else {
                    recallsCard
                    attention
                    ForEach(sections, id: \.title) { section in
                        if sections.count > 1 {
                            Eyebrow(text: section.title).padding(.top, Theme.xs)
                        }
                        ForEach(section.vehicles) { vehicle in
                            NavigationLink(value: vehicle.objectID) {
                                VehicleCard(vehicle: vehicle)
                            }
                            .buttonStyle(PressableStyle())
                            .contextMenu {
                                Button { logging = LogRequest(vehicle: vehicle) } label: { Label("Log service", systemImage: "plus.circle") }
                            }
                        }
                    }
                    addButton
                    InsightsTeaser()
                    if !garage.retiredVehicles.isEmpty {
                        NavigationLink {
                            RetiredVehiclesView()
                        } label: {
                            Text("Sold and retired (\(garage.retiredVehicles.count))")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.secondaryInk)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.sm)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.xl)
        }
        .paperBackground()
        .navigationTitle(garage.ownGarage?.displayName ?? "Garage")
        .navigationDestination(for: NSManagedObjectID.self) { id in
            if let vehicle = garage.vehicles.first(where: { $0.objectID == id }) ?? garage.retiredVehicles.first(where: { $0.objectID == id }) {
                VehicleDetailView(vehicle: vehicle)
            }
        }
        .navigationDestination(for: RecallRoute.self) { route in
            if let vehicle = garage.vehicles.first(where: { $0.objectID == route.vehicle }) {
                RecallsView(vehicle: vehicle, recalls: RecallWatcher.cached(for: vehicle) ?? [])
            }
        }
        .onReceive(router.$destination.compactMap { $0 }) { destination in
            Task { @MainActor in router.destination = nil }
            guard let vehicle = garage.vehicles.first(where: { $0.id == destination.vehicleID }) else { return }
            logging = nil
            var route = NavigationPath()
            route.append(vehicle.objectID)
            if destination.showsRecalls { route.append(RecallRoute(vehicle: vehicle.objectID)) }
            path = route
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingFamily = true } label: {
                    Label("Family", systemImage: sharing.share == nil && garage.joinedGarages.isEmpty ? "person.2" : "person.2.fill")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityLabel("Family sharing")
                .accessibilityIdentifier("garage.family")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: addVehicle) { Image(systemName: "plus") }
                    .accessibilityLabel("Add a vehicle")
                    .accessibilityIdentifier("garage.add")
            }
        }
        .sheet(isPresented: $showingAdd) { AddVehicleFlow() }
        .sheet(isPresented: $showingPaywall) { PaywallView(focus: .unlimitedVehicles) }
        .sheet(isPresented: $showingFamily) { NavigationStack { FamilyView() } }
        .sheet(item: $logging) { request in LogServiceView(vehicle: request.vehicle, preselected: request.preselected) }
        .task {
            routeScreenshot()
            if AppGroup.defaults.bool(forKey: AppGroup.Key.pendingFirstVehicle) {
                AppGroup.defaults.set(false, forKey: AppGroup.Key.pendingFirstVehicle)
                if garage.vehicles.isEmpty, !ScreenshotConfig.isEnabled { showingAdd = true }
            }
        }
    }

    private var sections: [(title: String, vehicles: [Vehicle])] {
        var result: [(String, [Vehicle])] = []
        if let own = garage.ownGarage {
            let mine = garage.vehicles.filter { $0.garage == own }
            if !mine.isEmpty { result.append((own.displayName, mine)) }
        }
        for joined in garage.joinedGarages {
            let theirs = garage.vehicles.filter { $0.garage == joined }
            if !theirs.isEmpty { result.append((joined.displayName, theirs)) }
        }
        let placed = Set(result.flatMap(\.1).map(\.objectID))
        let loose = garage.vehicles.filter { !placed.contains($0.objectID) }
        if !loose.isEmpty { result.append(("Vehicles", loose)) }
        return result
    }

    /// Open safety recalls, from the last NHTSA check, above everything else.
    @ViewBuilder
    private var recallsCard: some View {
        let items = garage.vehicles.compactMap { vehicle -> (Vehicle, [Recall])? in
            guard let cached = RecallWatcher.cached(for: vehicle) else { return nil }
            let open = garage.openRecalls(cached, for: vehicle)
            return open.isEmpty ? nil : (vehicle, open)
        }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.sm) {
                Eyebrow(text: "Safety recalls", color: Theme.overdue)
                ForEach(items, id: \.0.objectID) { vehicle, open in
                    NavigationLink(value: RecallRoute(vehicle: vehicle.objectID)) {
                        HStack(spacing: Theme.sm) {
                            Image(systemName: open.contains { $0.parkIt } ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.overdue)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(vehicle.displayName): \(open.count == 1 ? open[0].componentTitle : "\(open.count) recalls")")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(2)
                                Text(open.contains { $0.parkIt } ? "NHTSA says don't drive it until it's fixed" : "May apply. Check your VIN, then log the fix")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryInk)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.faintInk)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }

    /// Overdue and due-soon jobs across every vehicle, most urgent first.
    @ViewBuilder
    private var attention: some View {
        let items = garage.vehicles.flatMap { vehicle in
            garage.dues(for: vehicle).filter { $0.result.status <= .dueSoon }.map { (vehicle, $0) }
        }
        .sorted { TaskDue.ordering($0.1, $1.1) }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.sm) {
                HStack {
                    Eyebrow(text: items.contains { $0.1.result.status == .overdue } ? "Needs attention" : "Coming up", color: Theme.brass)
                    Spacer()
                    Text(Format.count(items.count, "job", "jobs"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryInk)
                }
                ForEach(items.prefix(showingAllAttention ? items.count : 3), id: \.1.id) { vehicle, due in
                    Button { logging = LogRequest(vehicle: vehicle, preselected: [due.taskID]) } label: {
                        HStack(spacing: Theme.sm) {
                            Circle().fill(vehicle.tint.color).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(vehicle.displayName): \(due.name)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(2)
                                Text(due.dueLine())
                                    .font(.footnote)
                                    .foregroundStyle(due.result.status.color)
                            }
                            Spacer()
                            Text("Log")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, Theme.sm)
                                .padding(.vertical, 6)
                                .background(Theme.raised, in: Capsule())
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Log this job")
                }
                if items.count > 3 {
                    Button(showingAllAttention ? "Show fewer" : "Show all \(items.count)") {
                        withAnimation(.snappy) { showingAllAttention.toggle() }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.brass)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .card()
        }
    }

    private var addButton: some View {
        Button(action: addVehicle) {
            HStack(spacing: Theme.xs) {
                Image(systemName: "plus")
                Text("Add a vehicle")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
        }
        .buttonStyle(PressableStyle())
    }

    private func addVehicle() {
        Haptics.tap()
        if !store.isPro && garage.ownedVehicleCount >= ProFeature.freeVehicleLimit {
            showingPaywall = true
        } else {
            showingAdd = true
        }
    }

    private func routeScreenshot() {
        guard !routedScreenshot, let route = ScreenshotConfig.value(after: "-ScreenshotRoute") else { return }
        routedScreenshot = true
        let first = garage.vehicles.first
        switch route {
        case "vehicle", "explore", "record":
            if let first { path.append(first.objectID) }
        case "log":
            logging = first.map { LogRequest(vehicle: $0) }
        case "family":
            showingFamily = true
        case "add":
            showingAdd = true
        default:
            break
        }
    }
}

/// A vehicle's recall list, pushed from the garage or a notification.
struct RecallRoute: Hashable {
    let vehicle: NSManagedObjectID
}

/// Opening the log sheet, with the jobs to tick already ticked.
struct LogRequest: Identifiable {
    let vehicle: Vehicle
    var preselected: [UUID] = []
    var id: NSManagedObjectID { vehicle.objectID }
}

/// One vehicle as a key tag: its color, its name, its meter and the next job.
struct VehicleCard: View {
    @EnvironmentObject private var garage: GarageStore
    let vehicle: Vehicle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let headline = garage.headline(for: vehicle)
        let tint = vehicle.tint
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(tint.color)
            if vehicle.photo != nil {
                photoLayer
            } else {
                Image(systemName: vehicle.kind.symbol)
                    .font(.system(size: 96, weight: .regular))
                    .foregroundStyle(tint.foreground.opacity(0.13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, Theme.md)
                    .padding(.bottom, 34)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    KeyTagHole(tint: tint)
                    Spacer()
                    if garage.isShared(vehicle) {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(tint.foreground.opacity(0.7))
                            .accessibilityLabel("Shared with you")
                    }
                }
                Spacer(minLength: Theme.sm)
                if !vehicle.descriptor.isEmpty && vehicle.descriptor != vehicle.displayName {
                    Text(vehicle.descriptor.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(tint.foreground.opacity(0.75))
                        .lineLimit(1)
                }
                Text(vehicle.displayName)
                    .font(Theme.title(28))
                    .foregroundStyle(tint.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if vehicle.meter.hasReading, vehicle.reading > 0 {
                    Text(Format.reading(vehicle.reading, vehicle.meter))
                        .font(Theme.figure(15, weight: .medium))
                        .foregroundStyle(tint.foreground.opacity(0.8))
                        .padding(.top, 1)
                }
                statusChip(headline)
                    .padding(.top, Theme.sm)
            }
            .padding(Theme.md)
        }
        .frame(minHeight: 196)
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(headline))
    }

    private var photoLayer: some View {
        GeometryReader { geometry in
            if let data = vehicle.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width * 0.62, height: geometry.size.height)
                    .clipped()
                    .mask(LinearGradient(colors: [.clear, .black.opacity(0.9), .black], startPoint: .leading, endPoint: .trailing))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func statusChip(_ headline: (status: DueStatus, urgentCount: Int, next: TaskDue?)) -> some View {
        let quiet = headline.status == .ok || vehicle.storedSince != nil
        return HStack(spacing: 6) {
            Circle()
                .fill(quiet ? vehicle.tint.foreground.opacity(0.7) : headline.status.color)
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: quiet ? 0 : 1))
                .frame(width: 8, height: 8)
            Text(statusText(headline))
                .font(.footnote.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
        }
        .foregroundStyle(vehicle.tint.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(vehicle.tint.isLight ? 0.08 : 0.22), in: Capsule())
    }

    private func statusText(_ headline: (status: DueStatus, urgentCount: Int, next: TaskDue?)) -> String {
        if vehicle.storedSince != nil {
            return vehicle.storedUntil.map { "In storage until \(Format.shortDate($0))" } ?? "In storage"
        }
        guard let next = headline.next else {
            return garage.dues(for: vehicle).isEmpty ? "No schedule yet" : "Add when jobs were last done"
        }
        let line = next.dueLine()
        if headline.urgentCount > 1 {
            let dues = garage.dues(for: vehicle)
            let overdue = dues.filter { $0.result.status == .overdue }.count
            let soon = dues.filter { $0.result.status == .dueSoon }.count
            if overdue > 0, soon > 0 { return "\(next.name) overdue, \(soon) more due soon" }
            let state = overdue > 0 ? "overdue" : "due soon"
            return "\(next.name) and \(headline.urgentCount - 1) more \(state)"
        }
        return "\(next.name) · \(line.lowercasedFirst)"
    }

    private func accessibilityText(_ headline: (status: DueStatus, urgentCount: Int, next: TaskDue?)) -> String {
        var parts = [vehicle.displayName]
        if !vehicle.descriptor.isEmpty { parts.append(vehicle.descriptor) }
        if vehicle.meter.hasReading, vehicle.reading > 0 { parts.append(Format.reading(vehicle.reading, vehicle.meter)) }
        parts.append(statusText(headline))
        return parts.joined(separator: ", ")
    }
}

/// The punched hole and ring that make a card read as a key tag.
struct KeyTagHole: View {
    let tint: VehicleTint

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.paper)
                .frame(width: 14, height: 14)
            Circle()
                .strokeBorder(tint.foreground.opacity(0.35), lineWidth: 1.5)
                .frame(width: 22, height: 22)
        }
        .accessibilityHidden(true)
    }
}

struct RetiredVehiclesView: View {
    @EnvironmentObject private var garage: GarageStore

    var body: some View {
        List {
            Section {
                ForEach(garage.retiredVehicles) { vehicle in
                    NavigationLink {
                        VehicleDetailView(vehicle: vehicle)
                    } label: {
                        HStack(spacing: Theme.sm) {
                            VehicleArt(vehicle: vehicle).frame(width: 44, height: 44)
                            VStack(alignment: .leading) {
                                Text(vehicle.displayName).font(.body.weight(.semibold))
                                Text(subtitle(vehicle)).font(.footnote).foregroundStyle(Theme.secondaryInk)
                            }
                        }
                    }
                }
            } footer: {
                Text("Sold or retired vehicles keep their full history and stop sending reminders. They don't count toward the free limit.")
            }
        }
        .paperBackground()
        .navigationTitle("Sold and retired")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func subtitle(_ vehicle: Vehicle) -> String {
        let status = vehicle.soldDate.map { "Sold " + $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "Retired"
        return [vehicle.descriptor.nilIfEmpty, status].compactMap { $0 }.joined(separator: " · ")
    }
}
