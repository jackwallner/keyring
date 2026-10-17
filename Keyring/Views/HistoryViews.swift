import CoreData
import SwiftUI

/// Every job across the garage, newest first, with who logged it.
struct HistoryView: View {
    @EnvironmentObject private var garage: GarageStore
    @State private var filter: NSManagedObjectID?
    @State private var search = ""
    @State private var exportFile: SharedFile?

    var body: some View {
        let entries = filtered
        List {
            if garage.vehicles.count > 1 {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.xs) {
                            chip("All", selected: filter == nil) { filter = nil }
                            ForEach(garage.vehicles) { vehicle in
                                chip(vehicle.displayName, tint: vehicle.tint.color, selected: filter == vehicle.objectID) { filter = vehicle.objectID }
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
                            NavigationLink { EntryDetailView(entry: entry) } label: { EntryRow(entry: entry, showsVehicle: filter == nil) }
                                .listRowBackground(Theme.surface)
                        }
                    } header: {
                        HStack {
                            Text(group.title)
                            Spacer()
                            if group.total > 0, !hideCosts {
                                Text(Format.money(group.total)).monospacedDigit()
                            }
                        }
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
                        let vehicles = filter.flatMap { id in garage.vehicles.filter { $0.objectID == id } } ?? (garage.vehicles + garage.retiredVehicles)
                        if let url = try? CSVExport.url(for: vehicles) { exportFile = SharedFile(url: url) }
                    } label: {
                        Label("Export spreadsheet (CSV)", systemImage: "tablecells")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export")
            }
        }
        .sheet(item: $exportFile) { file in ShareSheet(items: [file.url]) }
    }

    private var hideCosts: Bool { AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts) }

    private var filtered: [ServiceEntry] {
        _ = garage.revision
        var entries = garage.allEntries()
        if let filter { entries = entries.filter { $0.vehicle?.objectID == filter } }
        let query = search.trimmed.lowercased()
        if !query.isEmpty {
            entries = entries.filter { entry in
                [entry.title, entry.shop, entry.notes, entry.loggedBy, entry.vehicle?.displayName]
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

    private func chip(_ title: String, tint: Color? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
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
            .foregroundStyle(selected ? Theme.onAction : Theme.ink)
            .background(selected ? Theme.action : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: selected ? 0 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One vehicle's full history.
struct VehicleHistoryView: View {
    @EnvironmentObject private var garage: GarageStore
    @ObservedObject var vehicle: Vehicle

    var body: some View {
        List {
            ForEach(vehicle.sortedEntries) { entry in
                NavigationLink { EntryDetailView(entry: entry) } label: { EntryRow(entry: entry, showsVehicle: false) }
                    .listRowBackground(Theme.surface)
            }
        }
        .paperBackground()
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A logged job in a list.
struct EntryRow: View {
    @ObservedObject var entry: ServiceEntry
    let showsVehicle: Bool

    private var hideCosts: Bool { AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts) }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            VStack(spacing: 0) {
                Text(entry.date?.formatted(.dateTime.day()) ?? "")
                    .font(Theme.figure(18))
                    .foregroundStyle(Theme.ink)
                Text(entry.date?.formatted(.dateTime.month(.abbreviated)).uppercased() ?? "")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.secondaryInk)
            }
            .frame(width: 38)
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
        if showsVehicle, let vehicle = entry.vehicle { parts.append(vehicle.displayName) }
        if entry.hasReading, let meter = entry.vehicle?.meter, meter.hasReading { parts.append(Format.reading(entry.reading, meter)) }
        if entry.isDIY { parts.append("DIY") } else if let shop = entry.shop { parts.append(shop) }
        if let by = entry.loggedBy { parts.append(by) }
        let attachments = entry.attachments?.count ?? 0
        if attachments > 0 { parts.append("\(attachments) \(attachments == 1 ? "photo" : "photos")") }
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
                        Eyebrow(text: vehicle.displayName, color: Theme.brass)
                        Text(entry.title ?? "Service")
                            .font(Theme.title(28))
                            .foregroundStyle(Theme.ink)
                        Text(entry.date?.formatted(date: .complete, time: .omitted) ?? "")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    .padding(.top, Theme.sm)

                    facts(vehicle)

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
                                                Text("Receipt")
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
            if let vehicle = entry.vehicle { LogServiceView(vehicle: vehicle, editing: entry) }
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

    private func facts(_ vehicle: Vehicle) -> some View {
        let hideCosts = AppGroup.defaults.bool(forKey: AppGroup.Key.hideCosts)
        var items: [(String, String)] = []
        if entry.hasReading, vehicle.meter.hasReading { items.append((vehicle.meter.meterName, Format.reading(entry.reading, vehicle.meter))) }
        if entry.cost > 0, !hideCosts { items.append(("Cost", Format.money(entry.cost))) }
        items.append(("Done by", entry.isDIY ? "Owner" : (entry.shop ?? "A shop")))
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
                        garage.delete(attachment)
                        close()
                    } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Delete")
                }
            }
            .toolbarBackground(.black, for: .navigationBar, .bottomBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
            .sheet(isPresented: $sharing) {
                if let data = attachment.data, let image = UIImage(data: data) { ShareSheet(items: [image]) }
            }
        }
    }
}
