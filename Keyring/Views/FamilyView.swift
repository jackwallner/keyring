import CloudKit
import SwiftUI

/// The family garage. The owner shows a code or sends a link; whoever joins
/// logs into the same vehicles from their own iPhone. No accounts beyond
/// the iCloud everyone already has.
struct FamilyView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var garage: GarageStore
    @EnvironmentObject private var sharing: SharingService

    @State private var share: CKShare?
    @State private var preparing = false
    @State private var errorMessage: String?
    @State private var managing: ManagedShare?
    @State private var joining = false
    @State private var leaving: Garage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                VStack(alignment: .leading, spacing: Theme.xs) {
                    Text("Share the garage")
                        .font(Theme.title(30))
                        .foregroundStyle(Theme.ink)
                    Text("Your partner, a teen driver, whoever takes the truck in. Everyone logs from their own iPhone, and every phone shows the same history. Reminders stay personal.")
                        .font(.body)
                        .foregroundStyle(Theme.secondaryInk)
                }
                .padding(.top, Theme.sm)

                if let url = inviteURL {
                    inviteCard(url)
                    joinedCard
                } else if preparing {
                    HStack(spacing: Theme.sm) {
                        ProgressView()
                        Text("Making your invite. The first time takes a few seconds.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    .card()
                } else {
                    steps
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(Theme.overdue)
                    }
                    Button {
                        Task { await prepare() }
                    } label: {
                        Label("Create invite", systemImage: "qrcode")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("family.invite")
                }

                if !garage.joinedGarages.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.sm) {
                        SectionHeader(title: "Shared with you")
                        ForEach(garage.joinedGarages) { joined in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(joined.displayName).font(.subheadline.weight(.semibold))
                                    Text(Format.count(joined.activeVehicles.count, "vehicle", "vehicles"))
                                        .font(.footnote).foregroundStyle(Theme.secondaryInk)
                                }
                                Spacer()
                                Button("Leave") { leaving = joined }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.overdue)
                            }
                            .card()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.sm) {
                    SectionHeader(title: "Joining someone else's?")
                    Button { joining = true } label: {
                        Label("Join with a code or link", systemImage: "qrcode.viewfinder")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                Label {
                    Text("Anyone with your code or link can join and edit, so share it only with people you trust. Each person needs iCloud; a phone that's offline catches up when it reconnects. Joined garages don't count toward your free vehicles.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                } icon: {
                    Image(systemName: "lock.fill").font(.footnote).foregroundStyle(Theme.secondaryInk)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.xl)
        }
        .paperBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .task {
            await sharing.refresh()
            share = sharing.share
        }
        .sheet(item: $managing) { current in
            CloudSharingController(share: current.share, container: sharing.ckContainer, title: garage.ownGarage?.displayName ?? "Garage") { outcome in
                managing = nil
                Task {
                    switch outcome {
                    case let .saved(updated):
                        try? await sharing.persist(updated)
                        share = updated
                    case .stopped:
                        sharing.stoppedSharing()
                        share = nil
                    case .failed:
                        errorMessage = "Apple couldn't save that change. Check your connection and try again."
                    }
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $joining) { JoinGarageView() }
        .confirmationDialog("Leave \(leaving?.displayName ?? "this garage")?", isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }), titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                if let leaving { Task { try? await sharing.leave(leaving) } }
                leaving = nil
            }
        } message: {
            Text("Its vehicles disappear from this iPhone. Nothing is deleted for the owner, and they can invite you again.")
        }
    }

    private var inviteURL: URL? {
        #if DEBUG
        if ScreenshotConfig.value(after: "-ScreenshotRoute") == "family" {
            return URL(string: "https://www.icloud.com/share/0KeyringPreviewInvite#The_Wallner_garage")
        }
        #endif
        guard let share, share.publicPermission == .readWrite else { return nil }
        return share.url
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: Theme.md) {
            step(1, "They install Keyring", "Free on the App Store.")
            step(2, "They scan your code", "In Keyring: Garage, the people button, then Join. Or the Camera app, or a link you text.")
            step(3, "You log together", "Every vehicle, job and receipt, signed with who logged it.")
        }
        .card()
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.sm) {
            Text("\(number)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.onAction)
                .frame(width: 26, height: 26)
                .background(Theme.action, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(detail).font(.subheadline).foregroundStyle(Theme.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func inviteCard(_ url: URL) -> some View {
        VStack(spacing: Theme.md) {
            if let image = ShareInvite.qrCode(for: url) {
                Image(image, scale: 1, label: Text("Invite code"))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(Theme.md)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("family.code")
            }
            Text("Have them scan this in Keyring or with their Camera")
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            ShareLink(
                item: url,
                subject: Text("Join our garage in Keyring"),
                message: Text("Join our garage in Keyring so we can both log maintenance on our vehicles.")
            ) {
                Label("Send invite link", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle())
            if let share {
                Button("Manage people") { managing = ManagedShare(share: share) }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var joinedCard: some View {
        VStack(alignment: .leading, spacing: Theme.sm) {
            Eyebrow(text: "In this garage")
            let names = ScreenshotConfig.isEnabled ? ["Sam"] : sharing.participantNames
            Label("You (\(garage.ownerName ?? "owner"))", systemImage: "person.fill")
            if names.isEmpty {
                Text("No one has joined yet. Their name shows up here once they do.")
                    .font(.subheadline).foregroundStyle(Theme.secondaryInk)
            } else {
                ForEach(names, id: \.self) { Label($0, systemImage: "person.fill.checkmark") }
            }
        }
        .font(.subheadline)
        .card()
    }

    private func prepare() async {
        preparing = true
        errorMessage = nil
        defer { preparing = false }
        guard (try? await sharing.ckContainer.accountStatus()) == .available else {
            errorMessage = "Sign in to iCloud on this iPhone (Settings > your name) to invite anyone."
            return
        }
        do {
            share = try await sharing.inviteShare()
        } catch {
            errorMessage = "iCloud didn't finish setting up the invite. Wait a moment and try again; your garage is safe."
        }
    }
}

/// Joining a garage someone else shared: scan their code or paste the link.
struct JoinGarageView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sharing: SharingService

    @State private var link = ""
    @State private var scanning = false
    @State private var status: String?
    @State private var joining = false

    var body: some View {
        NavigationStack {
            Form {
                if LiveTextScanner.isAvailable {
                    Section {
                        Button { scanning = true } label: { Label("Scan their code", systemImage: "qrcode.viewfinder") }
                    } footer: {
                        Text("On their iPhone: Garage, the people button, then Create invite.")
                    }
                }
                Section {
                    TextField("icloud.com/share/…", text: $link, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { link = first }
                    }
                } header: {
                    Text("Or paste the link they sent")
                }
                if let status {
                    Section { Text(status).font(.footnote) }
                }
            }
            .paperBackground()
            .navigationTitle("Join a garage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") { Task { await join() } }
                        .disabled(link.trimmed.isEmpty || joining)
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                NavigationStack {
                    LiveTextScanner(mode: .invite) { payload in
                        scanning = false
                        link = payload
                        Task { await join() }
                    }
                    .ignoresSafeArea()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } } }
                }
            }
        }
    }

    private func join() async {
        joining = true
        status = "Joining…"
        defer { joining = false }
        do {
            try await sharing.join(pasted: link)
            Haptics.success()
            status = "Joined. The vehicles appear in your garage in a moment."
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        } catch let error as SharingService.JoinError {
            status = error.message
            Haptics.warning()
        } catch {
            status = SharingService.JoinError.unavailable.message
        }
    }
}

/// Waiting for a shared garage to arrive after opening an invite on a fresh
/// install, so onboarding doesn't create a duplicate.
struct JoiningView: View {
    var body: some View {
        VStack(spacing: Theme.md) {
            ProgressView()
            Text("Joining the garage")
                .font(Theme.title(24))
            Text("The vehicles and their history are on their way from iCloud.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
    }
}

enum SharingOutcome {
    case saved(CKShare)
    case stopped
    case failed
}

struct CloudSharingController: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let title: String
    let finished: (SharingOutcome) -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPublic, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished, title: title) }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let finished: (SharingOutcome) -> Void
        let title: String

        init(finished: @escaping (SharingOutcome) -> Void, title: String) {
            self.finished = finished
            self.title = title
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) { finished(.failed) }
        func itemTitle(for csc: UICloudSharingController) -> String? { title }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { if let share = csc.share { finished(.saved(share)) } }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { finished(.stopped) }
    }
}

/// `.sheet(item:)` needs an identity; CKShare's own `id` property clashes.
struct ManagedShare: Identifiable {
    let share: CKShare
    var id: String { share.recordID.recordName }
}
