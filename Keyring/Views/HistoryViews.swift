import CoreData
import SwiftUI

/// Every job across the garage, newest first, with who logged it.
struct HistoryView: View {
    private enum Show: Hashable { case all, service, fuel }

    @EnvironmentObject private var garage: GarageStore
    @State private var filter: NSManagedObjectID?
    @State private var show: Show = .all
    @State private var search = ""
    @State private var exportFile: SharedFile?
    @State private var importing = false
    @State private var editingEntry: ServiceEntry?
    @State private var deletingEntry: ServiceEntry?

    /// Sold and retired vehicles' entries are in the list, so they get a chip too.
    private var allVehicles: [Vehicle] { garage.vehicles + garage.retiredVehicles }

    var body: some View {
        let entries = filtered
        let economy = FuelEconomy.labels(for: allVehicles)
        List {
            if hasFuel {
                Section {
                    Picker("Show", selection: $show) {
                        Text("All").tag(Show.all)
                        Text("Service").tag(Show.service)
                        Text("Fuel").tag(Show.fuel)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.margin, bottom: 0, trailing: Theme.margin))
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("history.show")
                }
            }
            if allVehicles.count > 1 {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.xs) {
                            chip("All", selected: filter == nil) { filter = nil }
                            ForEach(allVehicles) { vehicle in
                                chip(vehicle.displayName, tint: vehicle.tint.color, retired: vehicle.isRetired, selected: filter == vehicle.objectID) { filter = vehicle.objectID }
                            }
                        }
                        .padding(.horizontal, Theme.margin)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            if entries.isEmpty {
                EmptyStateView(
                    symbol: "book.closed",
                    title: search.isEmpty ? "No history yet" : "Nothing matches",
                    message: search.isEmpty ? "Every job you or your family logs shows up here, newest first." : "Try a shop name, a job or a note."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(groups(entries), id: \.title) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            NavigationLink { EntryDetailView(entry: entry) } label: { EntryRow(entry: entry, showsVehicle: filter == nil, economy: entry.id.flatMap { economy[$0] }) }
                                .listRowBackground(Theme.surface)
                                .entrySwipeActions(entry, edit: $editingEntry, delete: $deletingEntry)
                        }
                    } header: {
                        GroupHeader(title: group.title, total: hideCosts ? 0 : group.total)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .paperBackground()
        .navigationTitle("History")
        .searchable(text: $search, prompt: "Jobs, shops, notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        let vehicles = filter.flatMap { id in allVehicles.filter { $0.objectID == id } } ?? allVehicles
                        if let url = try? CSVExport.url(for: vehicles) { exportFile = SharedFile(url: url) }
                    } label: {
                        Label("Export spreadsheet (CSV)", systemImage: "tablecells")
                    }
                    Button { importing = true } label: {
                        Label("Import from another app", systemImage: "tray.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export or import")
            }
        }
        .sheet(item: $exportFile) { file in ShareSheet(items: [file.url]) }
        .sheet(isPresented: $importing) { ImportView() }
        .entrySheets(edit: $editingEntry, delete: $deletingEntry)
    }

    private var hideCosts: Bool { AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts) }

    private var hasFuel: Bool {
        _ = garage.revision
        return garage.allEntries().contains { $0.kind == .fuel }
    }

    private var filtered: [ServiceEntry] {
        _ = garage.revision
        var entries = garage.allEntries()
        if let filter { entries = entries.filter { $0.vehicle?.objectID == filter } }
        switch show {
        case .all: break
        case .service: entries = entries.filter { $0.kind != .fuel }
        case .fuel: entries = entries.filter { $0.kind == .fuel }
        }
        let query = search.trimmed.lowercased()
        if !query.isEmpty {
            entries = entries.filter { entry in
                [entry.title, entry.shop, entry.notes, entry.loggedBy, entry.vehicle?.displayName, entry.kind == .service ? nil : entry.kind.title, entry.kind == .fuel ? "fuel gas" : nil, entry.grade?.title]
                    .compactMap { $0?.lowercased() }
                    .contains { $0.contains(query) }
            }
        }
        return entries
    }

    private func groups(_ entries: [ServiceEntry]) -> [(title: String, entries: [ServiceEntry], total: Double)] {
        let calendar = Calendar.current
        var result: [(String, [ServiceEntry], Double)] = []
        for entry in entries {
            let date = entry.date ?? .distantPast
            let title = calendar.isDate(date, equalTo: .now, toGranularity: .year)
                ? date.formatted(.dateTime.month(.wide))
                : date.formatted(.dateTime.month(.wide).year())
            if let last = result.last, last.0 == title {
                result[result.count - 1].1.append(entry)
                result[result.count - 1].2 += entry.cost
            } else {
                result.append((title, [entry], entry.cost))
            }
        }
        return result.map { ($0.0, $0.1, $0.2) }
    }

    private func chip(_ title: String, tint: Color? = nil, retired: Bool = false, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selected()
            action()
        } label: {
            HStack(spacing: 6) {
                if let tint { Circle().fill(tint).frame(width: 8, height: 8) }
                Text(title).lineLimit(1)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Theme.onAction : (retired ? Theme.secondaryInk : Theme.ink))
            .background(selected ? Theme.action : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: selected ? 0 : 0.5))
            // The capsule stays small; the tap area doesn't.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(retired ? "\(title), sold or retired" : title)
    }
}

/// Edit and Delete on a swipe, shared by every list of entries.
private extension View {
    func entrySwipeActions(_ entry: ServiceEntry, edit: Binding<ServiceEntry?>, delete: Binding<ServiceEntry?>) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { delete.wrappedValue = entry } label: { Label("Delete", systemImage: "trash") }
                .tint(Theme.overdue)
            Button { edit.wrappedValue = entry } label: { Label("Edit", systemImage: "pencil") }
                .tint(Theme.brass)
        }
    }

    func entrySheets(edit: Binding<ServiceEntry?>, delete: Binding<ServiceEntry?>) -> some View {
        modifier(EntrySheets(editing: edit, deleting: delete))
    }
}

private struct EntrySheets: ViewModifier {
    @EnvironmentObject private var garage: GarageStore
    @Binding var editing: ServiceEntry?
    @Binding var deleting: ServiceEntry?

    func body(content: Content) -> some View {
        content
            .sheet(item: $editing) { entry in
                if let vehicle = entry.vehicle {
                    if entry.kind == .fuel { FuelLogView(vehicle: vehicle, editing: entry) } else { LogServiceView(vehicle: vehicle, editing: entry) }
                }
            }
            .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let deleting { garage.delete(deleting) }
                    deleting = nil
                }
            } message: {
                Text("It's removed for everyone the garage is shared with, along with its receipts and photos.")
            }
    }
}

/// One vehicle's full history.
struct VehicleHistoryView: View {
    @EnvironmentObject private var garage: GarageStore
    @ObservedObject var vehicle: Vehicle
    /// Fill-ups only, rather than the service log.
    var fuel = false

    @State private var search = ""
    @State private var adding = false
    @State private var editingEntry: ServiceEntry?
    @State private var deletingEntry: ServiceEntry?

    var body: some View {
        let economy = fuel ? FuelEconomy.labels(for: [vehicle]) : [:]
        let groups = years
        let addAction: (() -> Void)? = search.isEmpty ? { adding = true } : nil
        List {
            if groups.isEmpty {
                EmptyStateView(
                    symbol: fuel ? "fuelpump" : "book.closed",
                    title: search.isEmpty ? (fuel ? "No fill-ups yet" : "Nothing logged yet") : "Nothing matches",
                    message: search.isEmpty
                        ? (fuel ? "Each fill-up you log here works out the fuel economy from the one before." : "Every job logged on \(vehicle.displayName) shows up here, newest first.")
                        : "Try a shop name, a job or a note.",
                    actionTitle: search.isEmpty ? (fuel ? "Log a fill-up" : "Log service") : nil,
                    action: addAction
                )
                .listRowBackground(Color.clear)
            }
            ForEach(groups, id: \.year) { group in
                Section {
                    ForEach(group.entries) { entry in
                        NavigationLink { EntryDetailView(entry: entry) } label: { EntryRow(entry: entry, showsVehicle: false, economy: entry.id.flatMap { economy[$0] }) }
                            .listRowBackground(Theme.surface)
                            .entrySwipeActions(entry, edit: $editingEntry, delete: $deletingEntry)
                    }
                } header: {
                    GroupHeader(
                        title: group.year == 0 ? "Undated" : String(group.year),
                        total: AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts) ? 0 : group.total
                    )
                }
            }
        }
        .paperBackground()
        .navigationTitle(fuel ? "Fill-ups" : "History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: fuel ? "Stations, grades, notes" : "Jobs, shops, notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(fuel ? "Log a fill-up" : "Log service")
            }
        }
        .sheet(isPresented: $adding) {
            if fuel { FuelLogView(vehicle: vehicle) } else { LogServiceView(vehicle: vehicle) }
        }
        .entrySheets(edit: $editingEntry, delete: $deletingEntry)
    }

    private var entries: [ServiceEntry] {
        _ = garage.revision
        let all = fuel ? vehicle.fuelEntries : vehicle.serviceEntries
        let query = search.trimmed.lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { entry in
            [entry.title, entry.shop, entry.notes, entry.loggedBy, entry.kind == .service ? nil : entry.kind.title, entry.grade?.title]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        }
    }

    private var years: [(year: Int, entries: [ServiceEntry], total: Double)] {
        var result: [(year: Int, entries: [ServiceEntry], total: Double)] = []
        for entry in entries {
            let year = entry.date.map { Calendar.current.component(.year, from: $0) } ?? 0
            if result.last?.year == year {
                result[result.count - 1].entries.append(entry)
                result[result.count - 1].total += entry.cost
            } else {
                result.append((year, [entry], entry.cost))
            }
        }
        return result
    }
}

/// A logged job in a list.
/// A month or year with its total, which drops under the title when large text won't fit both.
struct GroupHeader: View {
    let title: String
    let total: Double

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                amount
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                amount
            }
        }
    }

    @ViewBuilder private var amount: some View {
        if total > 0 { Text(Format.money(total)).monospacedDigit().lineLimit(1) }
    }
}

struct EntryRow: View {
    @ObservedObject var entry: ServiceEntry
    let showsVehicle: Bool
    /// A fill-up's fuel economy, worked out by the list against the fill-ups around it.
    var economy: String? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hideCosts: Bool { AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts) }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize { stacked } else { columns }
    }

    /// At the largest sizes three columns leave a word per line, so everything stacks.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let date = entry.date {
                Text(Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
                     ? date.formatted(.dateTime.month(.abbreviated).day())
                     : date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryInk)
            }
            Text(entry.title ?? "Service")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            if entry.cost > 0, !hideCosts {
                Text(Format.money(entry.cost))
                    .font(Theme.figure(14, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(3)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            VStack(spacing: 0) {
                Text(entry.date?.formatted(.dateTime.day()) ?? "")
                    .font(Theme.figure(18))
                    .foregroundStyle(Theme.ink)
                Text(entry.date?.formatted(.dateTime.month(.abbreviated)).uppercased() ?? "")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryInk)
                if let date = entry.date, !Calendar.current.isDate(date, equalTo: .now, toGranularity: .year) {
                    Text(date.formatted(.dateTime.year()))
                        .font(.caption2)
                        .foregroundStyle(Theme.faintInk)
                }
            }
            .frame(minWidth: 38)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.date?.formatted(date: .long, time: .omitted) ?? "")
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title ?? "Service")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Spacer(minLength: Theme.xs)
                    if entry.cost > 0, !hideCosts {
                        Text(Format.money(entry.cost))
                            .font(Theme.figure(14, weight: .medium))
                            .foregroundStyle(Theme.ink)
                    }
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if entry.kind == .fuel { return fuelSubtitle }
        if entry.kind != .service { parts.append(entry.kind.title) }
        if showsVehicle, let vehicle = entry.vehicle { parts.append(vehicle.displayName) }
        if entry.hasReading, let meter = entry.vehicle?.meter, meter.hasReading { parts.append(Format.reading(entry.reading, meter)) }
        if entry.isDIY { parts.append("DIY") } else if let shop = entry.shop { parts.append(shop) }
        if let by = entry.loggedBy { parts.append(by) }
        let attachments = entry.attachments?.count ?? 0
        if attachments > 0 { parts.append("\(attachments) \(attachments == 1 ? "photo" : "photos")") }
        return parts.joined(separator: " · ")
    }

    private var fuelSubtitle: String {
        var parts: [String] = []
        if showsVehicle, let vehicle = entry.vehicle { parts.append(vehicle.displayName) }
        if let volume = entry.fuelVolumeText { parts.append(volume) }
        // The reading lives on the detail page; economy says more in a row.
        if let economy { parts.append(economy) } else if entry.hasReading, let meter = entry.vehicle?.meter, meter.hasReading { parts.append(Format.reading(entry.reading, meter)) }
        if let station = entry.shop { parts.append(station) }
        if let by = entry.loggedBy { parts.append(by) }
        return parts.joined(separator: " · ")
    }
}

/// A logged job in full: what, when, who, cost, receipts and photos.
struct EntryDetailView: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var entry: ServiceEntry

    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var viewing: Attachment?

    var body: some View {
        ScrollView {
            if let vehicle = entry.vehicle, !entry.isDeleted {
                VStack(alignment: .leading, spacing: Theme.lg) {
                    VStack(alignment: .leading, spacing: Theme.xs) {
                        Eyebrow(text: entry.kind == .service ? vehicle.displayName : "\(vehicle.displayName) · \(entry.kind.title)", color: [.service, .fuel].contains(entry.kind) ? Theme.brass : Theme.overdue)
                        Text(entry.title ?? "Service")
                            .font(Theme.title(28))
                            .foregroundStyle(Theme.ink)
                        Text(entry.date?.formatted(date: .complete, time: .omitted) ?? "")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    .padding(.top, Theme.sm)

                    if entry.kind == .fuel { fuelFacts(vehicle) } else { facts(vehicle) }

                    let covered = (vehicle.tasks ?? []).filter { task in task.id.map(entry.coveredTaskIDs.contains) ?? false }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
                    if !covered.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.xs) {
                            SectionHeader(title: "Jobs covered")
                            VStack(alignment: .leading, spacing: Theme.sm) {
                                ForEach(covered) { task in
                                    Label(task.displayName, systemImage: task.displaySymbol)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.ink)
                                }
                            }
                            .card()
                        }
                    }

                    if let campaign = entry.recallCampaign, let url = URL(string: "https://www.nhtsa.gov/recalls?nhtsaId=\(campaign)") {
                        Link(destination: url) {
                            HStack {
                                Label("NHTSA campaign \(campaign)", systemImage: EntryKind.recall.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.faintInk)
                            }
                            .card()
                        }
                    }

                    if let notes = entry.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.xs) {
                            SectionHeader(title: "Notes")
                            Text(notes).font(.body).foregroundStyle(Theme.ink).textSelection(.enabled).card()
                        }
                    }

                    if !entry.sortedAttachments.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.xs) {
                            SectionHeader(title: "Receipts and photos")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Theme.xs)], spacing: Theme.xs) {
                                ForEach(entry.sortedAttachments) { attachment in
                                    Button { viewing = attachment } label: {
                                        Group {
                                            if let image = ImageTools.thumbnail(attachment.data, maxDimension: 400) {
                                                Image(uiImage: image).resizable().scaledToFill()
                                            } else {
                                                Theme.raised
                                            }
                                        }
                                        .frame(height: 110)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(alignment: .bottomLeading) {
                                            if attachment.isReceipt {
                                                Text(entry.kind == .fuel ? "Pump" : "Receipt")
                                                    .font(.caption2.weight(.semibold))
                                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                                    .background(.ultraThinMaterial, in: Capsule())
                                                    .padding(6)
                                            }
                                        }
                                    }
                                    .buttonStyle(PressableStyle())
                                    .accessibilityLabel(attachment.isReceipt ? "Receipt" : "Photo")
                                }
                            }
                        }
                    }

                    Button("Delete entry", role: .destructive) { confirmingDelete = true }
                        .buttonStyle(SecondaryButtonStyle())
                        .foregroundStyle(Theme.overdue)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, Theme.xxl)
            }
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
        }
        .sheet(isPresented: $editing) {
            if let vehicle = entry.vehicle {
                if entry.kind == .fuel { FuelLogView(vehicle: vehicle, editing: entry) } else { LogServiceView(vehicle: vehicle, editing: entry) }
            }
        }
        .fullScreenCover(item: $viewing) { attachment in
            AttachmentViewer(attachment: attachment) { viewing = nil }
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                garage.delete(entry)
                dismiss()
            }
        } message: {
            Text("It's removed for everyone the garage is shared with, along with its receipts and photos.")
        }
    }

    private func fuelFacts(_ vehicle: Vehicle) -> some View {
        let hideCosts = AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts)
        let unit = FuelVolumeUnit.current
        var items: [(String, String)] = []
        if let volume = entry.fuelVolumeText { items.append((unit.plural, volume)) }
        if entry.fuelUnitPrice > 0, !hideCosts { items.append(("Price per \(unit.name)", Format.unitPrice(unit.fromPerLiter(entry.fuelUnitPrice)))) }
        if entry.cost > 0, !hideCosts { items.append(("Total", Format.money(entry.cost))) }
        if let grade = entry.grade { items.append(("Grade", grade.title)) }
        if entry.hasReading, vehicle.meter.hasReading { items.append((vehicle.meter.meterName, Format.reading(entry.reading, vehicle.meter))) }
        if let id = entry.id, let economy = FuelEconomy.labels(for: [vehicle])[id] { items.append(("Since last fill-up", economy)) }
        if entry.fuelPartial { items.append(("Tank", "Topped up")) }
        if let station = entry.shop { items.append(("Station", station)) }
        if let by = entry.loggedBy { items.append(("Logged by", by)) }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: Theme.md) {
            ForEach(items, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: label)
                    Text(value).font(Theme.figure(17)).foregroundStyle(Theme.ink).lineLimit(2)
                }
            }
        }
        .card()
    }

    private func facts(_ vehicle: Vehicle) -> some View {
        let hideCosts = AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts)
        var items: [(String, String)] = []
        if entry.hasReading, vehicle.meter.hasReading { items.append((vehicle.meter.meterName, Format.reading(entry.reading, vehicle.meter))) }
        if entry.hasAuxReading, vehicle.hasAuxMeter { items.append(("\(vehicle.auxMeterName ?? "Second meter") hours", Format.reading(entry.auxReading, .hours))) }
        if entry.cost > 0, !hideCosts { items.append(("Cost", Format.money(entry.cost))) }
        items.append(("Done by", entry.isDIY ? (entry.loggedBy.map { "\($0), DIY" } ?? "DIY") : (entry.shop ?? "A shop")))
        if let by = entry.loggedBy { items.append(("Logged by", by)) }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: Theme.md) {
            ForEach(items, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: label)
                    Text(value).font(Theme.figure(17)).foregroundStyle(Theme.ink).lineLimit(2)
                }
            }
        }
        .card()
    }
}

/// A receipt or photo, full screen, with share and delete.
struct AttachmentViewer: View {
    @EnvironmentObject private var garage: GarageStore
    let attachment: Attachment
    let close: () -> Void
    @State private var sharing = false
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let data = attachment.data, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done", action: close) }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { sharing = true } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share")
                    Spacer()
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete")
                }
            }
            .confirmationDialog(attachment.isReceipt ? "Delete this receipt?" : "Delete this photo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    garage.delete(attachment)
                    close()
                }
            } message: {
                Text("It's removed for everyone who shares this garage.")
            }
            .toolbarBackground(.black, for: .navigationBar, .bottomBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
            .sheet(isPresented: $sharing) {
                if let data = attachment.data, let image = UIImage(data: data) { ShareSheet(items: [image]) }
            }
        }
    }
}
