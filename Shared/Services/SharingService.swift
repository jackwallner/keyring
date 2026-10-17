import CloudKit
import CoreData
import Foundation
import os

/// Family sharing through iCloud: one `CKShare` on the garage's record zone,
/// so every vehicle, job and entry in it follows. No accounts, no server.
///
/// The share is a read/write invite link. Whoever holds it (scanned from the
/// owner's screen or sent in Messages) joins with the same rights to add,
/// edit and log. A contact-only invite fails whenever the person's Apple ID
/// is not the address it went to, which is why a link is used.
@MainActor
final class SharingService: ObservableObject {
    static let shared = SharingService(store: .shared)

    @Published private(set) var share: CKShare?
    @Published private(set) var iCloudAvailable = false
    @Published var invitationError: String?
    @Published private(set) var isAcceptingInvitation = false
    @Published private(set) var isPreparing = false

    private let store: GarageStore
    private var persistence: Persistence { store.persistence }
    private let logger = Logger(subsystem: AppGroup.subsystem, category: "Sharing")

    init(store: GarageStore) {
        self.store = store
    }

    var ckContainer: CKContainer { CKContainer(identifier: AppGroup.cloudKitContainerID) }

    func refresh() async {
        iCloudAvailable = (try? await ckContainer.accountStatus()) == .available
        guard let garage = store.ownGarage, persistence.cloudKitEnabled else {
            share = nil
            return
        }
        do {
            share = try persistence.container.fetchShares(matching: [garage.objectID])[garage.objectID]
        } catch {
            // A transient failure must not make a shared garage look unshared.
            logger.error("fetchShares failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The owner's share with its invite link switched on.
    func inviteShare() async throws -> CKShare {
        let garage = store.ensureOwnGarage()
        isPreparing = true
        defer { isPreparing = false }
        await waitForFirstExport(of: garage)
        let opened = try await ShareInvite.prepare(
            for: [garage],
            title: garage.displayName,
            container: persistence.container,
            database: ckContainer.privateCloudDatabase
        )
        share = opened
        return opened
    }

    /// The link the QR code and "Send invite" carry.
    var inviteURL: URL? {
        guard let share, share.publicPermission == .readWrite else { return nil }
        return share.url
    }

    enum JoinError: Error, Equatable {
        case notAnInvite
        case iCloudUnavailable
        case ownInvite
        case unavailable

        var message: String {
            switch self {
            case .notAnInvite: "That isn't a Keyring invite link. Copy the whole link that was sent to you and try again."
            case .iCloudUnavailable: "Sign in to iCloud on this iPhone (Settings > your name), then try again."
            case .ownInvite: "This is your own invite. Show the code or send the link to the person joining."
            case .unavailable: "That invite couldn't be opened. Check your connection, or ask for a new link if sharing was stopped."
            }
        }
    }

    /// Joining with a pasted or scanned link. Opening the link from Messages
    /// or the Camera lands in `accept(_:)` instead.
    func join(pasted text: String) async throws {
        guard let url = ShareInvite.url(in: text) else { throw JoinError.notAnInvite }
        guard (try? await ckContainer.accountStatus()) == .available else { throw JoinError.iCloudUnavailable }
        let metadata: CKShare.Metadata
        do {
            metadata = try await ckContainer.shareMetadata(for: url)
        } catch {
            logger.error("shareMetadata failed: \(String(describing: error), privacy: .public)")
            throw JoinError.unavailable
        }
        guard metadata.participantRole != .owner else { throw JoinError.ownInvite }
        isAcceptingInvitation = true
        do {
            _ = try await persistence.container.acceptShareInvitations(from: [metadata], into: persistence.sharedStore)
        } catch {
            isAcceptingInvitation = false
            logger.error("acceptShareInvitations failed: \(String(describing: error), privacy: .public)")
            throw JoinError.unavailable
        }
        finishAccepting(error: nil)
    }

    func accept(_ metadata: CKShare.Metadata) {
        guard metadata.participantRole != .owner else {
            invitationError = JoinError.ownInvite.message
            return
        }
        invitationError = nil
        isAcceptingInvitation = true
        persistence.container.acceptShareInvitations(from: [metadata], into: persistence.sharedStore) { _, error in
            Task { @MainActor in self.finishAccepting(error: error) }
        }
    }

    private func finishAccepting(error: Error?) {
        if let error {
            isAcceptingInvitation = false
            logger.error("acceptShareInvitations failed: \(String(describing: error), privacy: .public)")
            invitationError = "Check your connection and that iCloud is signed in, then open the invite again. Your own garage is safe."
            return
        }
        invitationError = nil
        AppGroup.defaults.set(true, forKey: AppGroup.Key.hasCompletedSetup)
        // The garage arrives on a remote-change import a moment later.
        Task {
            for _ in 0..<60 where store.joinedGarages.isEmpty {
                try? await Task.sleep(for: .seconds(1))
                store.reload()
            }
            isAcceptingInvitation = false
        }
    }

    /// Sharing fails inside Core Data if it runs before the first CloudKit
    /// setup finishes; an exported record is the observable proof it has.
    private func waitForFirstExport(of garage: Garage) async {
        guard persistence.cloudKitEnabled else { return }
        let deadline = Date.now.addingTimeInterval(150)
        while Date.now < deadline, !Task.isCancelled {
            if persistence.container.recordID(for: garage.objectID) != nil { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
        logger.error("share requested before the first CloudKit export finished")
    }

    func persist(_ updated: CKShare) async throws {
        guard let garage = store.ownGarage, let persistent = garage.objectID.persistentStore else { return }
        share = try await persistence.container.persistUpdatedShare(updated, in: persistent)
    }

    func stoppedSharing() {
        share = nil
        store.reload()
    }

    /// Leaving a garage someone else shared removes the local copy only.
    func leave(_ garage: Garage) async throws {
        guard persistence.isShared(garage),
              let shares = try? persistence.container.fetchShares(matching: [garage.objectID]),
              let share = shares[garage.objectID] else { return }
        _ = try await persistence.container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: persistence.sharedStore)
        store.reload()
    }

    func share(for garage: Garage) -> CKShare? {
        try? persistence.container.fetchShares(matching: [garage.objectID])[garage.objectID]
    }

    var participantNames: [String] {
        guard let share else { return [] }
        return share.participants
            .filter { $0.role != .owner && $0.acceptanceStatus == .accepted }
            .compactMap(Self.displayName)
    }

    static func displayName(_ participant: CKShare.Participant) -> String? {
        let name = participant.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .short) } ?? ""
        if !name.isEmpty { return name }
        return participant.userIdentity.lookupInfo?.emailAddress ?? participant.userIdentity.lookupInfo?.phoneNumber
    }
}
