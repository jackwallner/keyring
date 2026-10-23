import SwiftUI

/// Insurance and roadside numbers for one vehicle, a tap from the shoulder.
struct RoadsideView: View {
    @ObservedObject var vehicle: Vehicle
    @State private var editing = false

    private var info: RoadsideInfo { vehicle.profile.roadside ?? RoadsideInfo() }

    var body: some View {
        List {
            if info.isEmpty {
                EmptyStateView(symbol: "shield.lefthalf.filled", title: "Insurance and roadside",
                               message: "Your policy and who to call, ready when you need them.",
                               actionTitle: "Add") { editing = true }
                    .listRowBackground(Color.clear)
            }
            if info.hasInsurance {
                Section("Insurance") {
                    if !info.claimsPhone.isEmpty { CallRow(title: "Call \(info.insurer.isEmpty ? "insurance" : info.insurer)", number: info.claimsPhone) }
                    if !info.insurer.isEmpty { InfoRow(label: "Company", value: info.insurer) }
                    if !info.policyNumber.isEmpty { InfoRow(label: "Policy", value: info.policyNumber) }
                }
            }
            if info.hasRoadside {
                Section("Roadside assistance") {
                    if !info.roadsidePhone.isEmpty { CallRow(title: "Call \(info.roadsideName.isEmpty ? "roadside" : info.roadsideName)", number: info.roadsidePhone) }
                    if !info.roadsideName.isEmpty { InfoRow(label: "Provider", value: info.roadsideName) }
                    if !info.memberNumber.isEmpty { InfoRow(label: "Member", value: info.memberNumber) }
                }
            }
            Section {
                NavigationLink { HowToView(vehicle: vehicle) } label: {
                    Label("How-to guides", systemImage: "play.rectangle.fill")
                }
                NavigationLink { DocumentsView(vehicle: vehicle) } label: {
                    Label("Documents", systemImage: "doc.text")
                }
            }
        }
        .paperBackground()
        .navigationTitle("Roadside")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !info.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editing = true } }
            }
        }
        .sheet(isPresented: $editing) { RoadsideEditor(vehicle: vehicle) }
    }
}

private struct CallRow: View {
    let title: String
    let number: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            Haptics.tap()
            if let url = PhoneLink.url(number) { openURL(url) }
        } label: {
            HStack(spacing: Theme.sm) {
                Image(systemName: "phone.fill")
                    .foregroundStyle(Theme.brass)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(number).font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(PhoneLink.url(number) == nil)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.secondaryInk)
            Spacer(minLength: Theme.md)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .contextMenu {
            Button { UIPasteboard.general.string = value } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
    }
}

struct RoadsideEditor: View {
    @EnvironmentObject private var garage: GarageStore
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @State private var info = RoadsideInfo()
    @State private var confirmingDiscard = false

    private var saved: RoadsideInfo { vehicle.profile.roadside ?? RoadsideInfo() }
    private var isDirty: Bool { info.cleaned != saved }
    private var offersAAA: Bool {
        RecallRegion.isUS && [.car, .truck, .suv, .van, .motorcycle, .rv, .camper, .trailer].contains(vehicle.kind)
            && info.roadsideName.trimmed.isEmpty && info.roadsidePhone.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Insurance") {
                    TextField("Company", text: $info.insurer)
                        .textContentType(.organizationName)
                    HStack {
                        TextField("Policy number", text: $info.policyNumber)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        ScanFieldButton(kind: .text) { info.policyNumber = $0 }
                    }
                    phoneField("Claims phone", text: $info.claimsPhone)
                }
                Section("Roadside assistance") {
                    TextField("Provider", text: $info.roadsideName)
                    phoneField("Phone", text: $info.roadsidePhone)
                    HStack {
                        TextField("Member number", text: $info.memberNumber)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        ScanFieldButton(kind: .text) { info.memberNumber = $0 }
                    }
                    if offersAAA {
                        Button {
                            info.roadsideName = RoadsideInfo.aaa.name
                            info.roadsidePhone = RoadsideInfo.aaa.phone
                        } label: {
                            Label("Use AAA", systemImage: "plus.circle")
                        }
                    }
                }
            }
            .paperBackground()
            .navigationTitle("Roadside")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if isDirty { confirmingDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        garage.setRoadside(info, on: vehicle)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(!isDirty)
                }
            }
            .discardGuard(isDirty: isDirty, confirming: $confirmingDiscard) { dismiss() }
            .onAppear { info = saved }
        }
    }

    private func phoneField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            TextField(title, text: text)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
            ScanFieldButton(kind: .text) { text.wrappedValue = $0 }
        }
    }
}

/// Curbside jobs for this vehicle, each a video search for its year, make and model.
struct HowToView: View {
    let vehicle: Vehicle

    var body: some View {
        List {
            ForEach(HowToCatalog.guides(for: vehicle)) { guide in
                LinkRow(title: guide.title, symbol: guide.symbol,
                        url: HowToCatalog.url(for: guide, vehicle: vehicle.descriptor, kind: vehicle.kind))
                    .padding(.vertical, 2)
            }
        }
        .paperBackground()
        .navigationTitle("How-to")
        .navigationBarTitleDisplayMode(.inline)
    }
}
