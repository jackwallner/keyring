import SwiftUI
import WidgetKit

/// What's next across the garage, from the snapshot the app writes after
/// every change.
struct UpcomingProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingEntry) -> Void) {
        let snapshot = WidgetSnapshot.read()
        completion(snapshot.vehicles.isEmpty && context.isPreview ? .sample : UpcomingEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingEntry>) -> Void) {
        let entry = UpcomingEntry(date: .now, snapshot: WidgetSnapshot.read())
        // Relative dates ("in 3 days") go stale overnight; refresh after midnight.
        let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400)).addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(tomorrow)))
    }
}

struct UpcomingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    static let sample = UpcomingEntry(date: .now, snapshot: WidgetSnapshot(vehicles: [
        .init(id: "1", name: "Tacoma", symbol: "truck.pickup.side.fill", tintHex: VehicleTint.racingGreen.hex, items: [
            .init(name: "Oil and filter", statusRaw: 1, dueDate: .now.addingTimeInterval(9 * 86_400), estimated: true),
        ]),
        .init(id: "2", name: "Lake boat", symbol: "ferry.fill", tintHex: VehicleTint.marine.hex, items: [
            .init(name: "Impeller", statusRaw: 3, dueDate: .now.addingTimeInterval(80 * 86_400), estimated: false),
        ]),
        .init(id: "3", name: "RAV4", symbol: "suv.side.fill", tintHex: VehicleTint.sky.hex, items: [
            .init(name: "Tire rotation", statusRaw: 3, dueDate: .now.addingTimeInterval(40 * 86_400), estimated: true),
        ]),
    ], updatedAt: .now))
}

struct UpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingEntry

    var body: some View {
        let items = entry.snapshot.upcoming
        Group {
            if items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "key.horizontal.fill").foregroundStyle(Theme.brass)
                    Text(entry.snapshot.vehicles.isEmpty ? "Add a vehicle in Keyring" : "All caught up")
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if family == .systemSmall {
                small(items[0])
            } else if family == .accessoryRectangular {
                accessory(items[0])
            } else {
                list(Array(items.prefix(family == .systemLarge ? 6 : 3)))
            }
        }
        .containerBackground(for: .widget) { Theme.paper }
    }

    private func small(_ item: (vehicle: WidgetSnapshot.VehicleSummary, item: WidgetSnapshot.Item)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: item.vehicle.symbol)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color(hex: item.vehicle.tintHex), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Spacer()
                Circle().fill(color(item.item.statusRaw)).frame(width: 8, height: 8)
            }
            Spacer()
            Text(item.vehicle.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(1)
            Text(item.item.name)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text(when(item.item))
                .font(.caption.weight(.semibold))
                .foregroundStyle(color(item.item.statusRaw))
        }
    }

    private func accessory(_ item: (vehicle: WidgetSnapshot.VehicleSummary, item: WidgetSnapshot.Item)) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(item.vehicle.name, systemImage: item.vehicle.symbol).font(.caption2.weight(.semibold))
            Text(item.item.name).font(.headline).lineLimit(1)
            Text(when(item.item)).font(.caption2)
        }
    }

    private func list(_ items: [(vehicle: WidgetSnapshot.VehicleSummary, item: WidgetSnapshot.Item)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Up next")
                .font(.system(.subheadline, design: .serif, weight: .semibold))
                .foregroundStyle(Theme.ink)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Image(systemName: item.vehicle.symbol)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color(hex: item.vehicle.tintHex), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.item.name).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                        Text(item.vehicle.name).font(.caption2).foregroundStyle(Theme.secondaryInk).lineLimit(1)
                    }
                    Spacer()
                    Text(when(item.item))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color(item.item.statusRaw))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func color(_ raw: Int) -> Color {
        switch DueStatus(rawValue: raw) {
        case .overdue: Theme.overdue
        case .dueSoon: Theme.dueSoon
        default: Theme.good
        }
    }

    private func when(_ item: WidgetSnapshot.Item) -> String {
        if item.statusRaw == DueStatus.overdue.rawValue { return "Overdue" }
        guard let date = item.dueDate else { return "" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        let prefix = item.estimated ? "~" : ""
        switch days {
        case ..<1: return "Today"
        case 1: return "Tomorrow"
        case 2..<14: return "\(prefix)\(days) days"
        case 14..<60: return "\(prefix)\(days / 7) wks"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeyringUpcoming", provider: UpcomingProvider()) { entry in
            UpcomingWidgetView(entry: entry)
        }
        .configurationDisplayName("Up next")
        .description("The next maintenance due across your garage.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

@main
struct KeyringWidgetBundle: WidgetBundle {
    var body: some Widget {
        UpcomingWidget()
    }
}
