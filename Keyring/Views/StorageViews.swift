import SwiftUI

/// Puts a vehicle away for the season, or brings it back out. While it's
/// stored, reminders pause and its pace stops counting, so a boat on blocks
/// isn't "due" for an oil change it can't have driven toward.
struct StorageSheet: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vehicle: Vehicle

    @State private var remind: Bool
    @State private var until: Date
    @State private var value: Double?
    @State private var auxValue: Double?

    private static let storageKeys: Set<String> = ["winterize", "storage", "storageCharge", "boatBattery"]

    init(vehicle: Vehicle) {
        self.vehicle = vehicle
        _remind = State(initialValue: vehicle.storedUntil != nil || vehicle.storedSince == nil)
        _until = State(initialValue: vehicle.storedUntil ?? Self.defaultReturn())
    }

    private var returning: Bool { vehicle.storedSince != nil }

    var body: some View {
        NavigationStack {
            Form {
                if returning { returnSections } else { storeSections }
            }
            .paperBackground()
            .fittedSheet(expandable: true)
            .navigationTitle(returning ? "Back on the road" : "Put in storage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(returning ? "Done" : "Put away", action: save)
                        .accessibilityIdentifier("storage.save")
                }
            }
        }
    }

    // MARK: - Putting it away

    @ViewBuilder private var storeSections: some View {
        Section {
            Toggle("Remind me to take it out", isOn: $remind.animation())
            if remind {
                DatePicker("On", selection: $until, in: Date.now..., displayedComponents: .date)
            }
        } footer: {
            Text("Reminders for \(vehicle.displayName) pause and the app stops assuming the \(vehicle.meter.meterName.lowercased()) is moving. Jobs that go by the calendar still count the months.")
        }
        let prep = (vehicle.enabledTasks).filter { Self.storageKeys.contains($0.catalogKey ?? "") }
        if !prep.isEmpty {
            Section("Before you put it away") {
                ForEach(prep, id: \.objectID) { task in
                    Label(task.displayName, systemImage: task.displaySymbol)
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    // MARK: - Bringing it back

    @ViewBuilder private var returnSections: some View {
        if vehicle.meter.hasReading {
            Section {
                HStack {
                    NumberField(
                        title: NumberField.display(vehicle.reading, allowsDecimal: vehicle.meter == .hours),
                        value: $value, suffix: vehicle.meter.short, allowsDecimal: vehicle.meter == .hours
                    )
                    ScanFieldButton(kind: .reading(last: vehicle.reading, meter: vehicle.meter)) { value = Double($0) }
                }
            } header: {
                Text(vehicle.meter.meterName)
            } footer: {
                Text(storedSinceText)
            }
        }
        if vehicle.hasAuxMeter {
            Section(vehicle.auxMeterName ?? "Second meter") {
                HStack {
                    NumberField(title: NumberField.display(vehicle.auxReading, allowsDecimal: true), value: $auxValue, suffix: "hrs", allowsDecimal: true)
                    ScanFieldButton(kind: .reading(last: vehicle.auxReading, meter: .hours)) { auxValue = Double($0) }
                }
            }
        }
        Section("Before its first trip") {
            let due = garage.dues(for: vehicle).filter { $0.result.status <= .dueSoon }
            if due.isEmpty {
                Text("Nothing is due. Enjoy the season.")
                    .foregroundStyle(Theme.secondaryInk)
            }
            ForEach(due, id: \.taskID) { item in
                HStack(spacing: Theme.sm) {
                    Image(systemName: item.symbol)
                        .foregroundStyle(item.result.status.color)
                        .frame(width: 24)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).foregroundStyle(Theme.ink)
                        Text(item.dueLine()).font(.footnote).foregroundStyle(Theme.secondaryInk)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        if !vehicle.meter.hasReading {
            Section { EmptyView() } footer: { Text(storedSinceText) }
        }
    }

    private var storedSinceText: String {
        guard let since = vehicle.storedSince else { return "" }
        return "In storage since \(Format.shortDate(since)). A new reading picks the due dates back up from here."
    }

    // MARK: -

    private func save() {
        if returning {
            garage.returnFromStorage(vehicle, reading: value, auxReading: auxValue)
            Haptics.success()
        } else {
            garage.store(vehicle, until: remind ? until : nil)
        }
        dismiss()
    }

    /// Mid-April for something put away in the fall, otherwise three months out.
    static func defaultReturn(from now: Date = .now, calendar: Calendar = .current) -> Date {
        let month = calendar.component(.month, from: now)
        if month >= 9 || month <= 2 {
            let year = calendar.component(.year, from: now) + (month >= 9 ? 1 : 0)
            if let april = calendar.date(from: DateComponents(year: year, month: 4, day: 15)) { return april }
        }
        return calendar.date(byAdding: .month, value: 3, to: now) ?? now
    }
}
