import CloudKit
import CoreData
import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// The Core Data stack: one private store (the family's own iCloud data) and
/// one shared store (a garage another family member shared with this account). Both
/// use the same model, so every query runs across the pair.
///
/// Only the app opens it, with CloudKit mirroring on; the widget reads a JSON
/// snapshot instead. Tests use an in-memory pair.
///
/// A store that will not open never ends the process. A CloudKit push can
/// launch the app in the background before the phone has been unlocked since
/// a restart, and file protection keeps the store shut in that launch; the
/// stack stands a throwaway in-memory store in, refuses writes while it is
/// up, and opens the real file the moment the phone is unlocked.
final class Persistence: @unchecked Sendable {
    static let shared = Persistence(cloudKit: Persistence.processWantsCloudKit, inMemory: Persistence.startsEmpty)

    /// `-EmptyLog`, `-Onboarding` and `-SeedDemo` (DEBUG): a fresh in-memory
    /// store, for the first-install paths a reviewer sees and for screenshot fixtures.
    private static var startsEmpty: Bool {
        #if DEBUG
        ["-EmptyLog", "-Onboarding", "-SeedDemo"].contains(where: ProcessInfo.processInfo.arguments.contains)
        #else
        false
        #endif
    }

    /// Posted after a stand-in store has been replaced by the real file, so
    /// every surface refetches instead of showing the empty stand-in.
    static let storesDidReopen = Notification.Name("KeyringPersistenceStoresDidReopen")

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore
    private(set) var sharedStore: NSPersistentStore
    private(set) var cloudKitEnabled: Bool
    /// Nil in production. Tests can inject a throwing operation to exercise
    /// rollback paths without changing the persistent model or store files.
    private let saveOperation: ((NSManagedObjectContext) throws -> Void)?

    private let privateDescription: NSPersistentStoreDescription
    private let sharedDescription: NSPersistentStoreDescription
    /// The descriptions whose files are not open, each with the in-memory
    /// store standing in for it. Read from whichever thread is saving and
    /// written on the main queue when the phone unlocks, so it is locked.
    private var standIns: [(description: NSPersistentStoreDescription, store: NSPersistentStore)] = []
    private let standInLock = NSLock()
    private var unlockObserver: Any?

    /// True while a store file could not be opened. Writes are refused, so
    /// nothing anyone logs is written where it would be lost.
    var isStandingIn: Bool { standInLock.withLock { !standIns.isEmpty } }

    private static let logger = Logger(subsystem: AppGroup.subsystem, category: "Persistence")

    /// Only the app process mirrors to CloudKit. Extensions are short-lived and
    /// memory-capped, and two exporters on one zone gain nothing.
    private static var processWantsCloudKit: Bool {
        #if DEBUG
        return Bundle.main.bundleIdentifier == AppGroup.bundleID && !ProcessInfo.processInfo.arguments.contains("-NoCloudKit")
            && CloudKitEntitlement.isPresent
        #else
        return Bundle.main.bundleIdentifier == AppGroup.bundleID
        #endif
    }

    init(
        cloudKit: Bool,
        inMemory: Bool = false,
        directory: URL? = nil,
        saveOperation: ((NSManagedObjectContext) throws -> Void)? = nil
    ) {
        cloudKitEnabled = cloudKit && !inMemory
        self.saveOperation = saveOperation
        container = NSPersistentCloudKitContainer(name: "Keyring", managedObjectModel: KeyringModel.model)

        let directory = directory ?? (inMemory ? FileManager.default.temporaryDirectory : Self.defaultDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        privateDescription = NSPersistentStoreDescription(
            url: inMemory ? URL(fileURLWithPath: "/dev/null/private") : directory.appendingPathComponent(Self.storeNames[0])
        )
        sharedDescription = NSPersistentStoreDescription(
            url: inMemory ? URL(fileURLWithPath: "/dev/null/shared") : directory.appendingPathComponent(Self.storeNames[1])
        )
        for description in [privateDescription, sharedDescription] {
            description.type = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            #if os(iOS)
            if !inMemory {
                // A background launch from a CloudKit push has to be able to
                // read the log. Complete protection would shut it out.
                description.setOption(
                    FileProtectionType.completeUntilFirstUserAuthentication.rawValue as NSString,
                    forKey: NSPersistentStoreFileProtectionKey
                )
            }
            #endif
        }
        if cloudKitEnabled {
            let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: AppGroup.cloudKitContainerID)
            privateOptions.databaseScope = .private
            privateDescription.cloudKitContainerOptions = privateOptions
            let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: AppGroup.cloudKitContainerID)
            sharedOptions.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = sharedOptions
        }

        var failures = Self.load([privateDescription, sharedDescription], in: container)

        // Mirroring that will not start must not cost anyone the local log:
        // reopen that store without CloudKit and run offline for this launch.
        for (description, error) in failures where description.cloudKitContainerOptions != nil {
            Self.logger.error("\(Self.name(of: description), privacy: .public) failed with CloudKit: \(String(describing: error), privacy: .public)")
            description.cloudKitContainerOptions = nil
            cloudKitEnabled = false
            failures[description] = Self.load([description], in: container)[description]
        }

        // A file that opens for nobody is corrupt or written by a newer model.
        // Move it aside, never delete it, and open a fresh one; CloudKit
        // brings the entries back and the old file stays recoverable by hand.
        // A phone that is merely locked is not that case, so its file is left
        // exactly where it is.
        for (description, error) in failures where !inMemory && Self.isCorrupt(error) {
            Self.logger.error("\(Self.name(of: description), privacy: .public) is unopenable, moving it aside: \(String(describing: error), privacy: .public)")
            if let url = description.url { Self.moveAside(url) }
            failures[description] = Self.load([description], in: container)[description]
        }

        var opened: [NSPersistentStoreDescription: NSPersistentStore] = [:]
        for description in [privateDescription, sharedDescription] {
            if failures[description] == nil, let store = Self.store(for: description, in: container) {
                opened[description] = store
                continue
            }
            Self.logger.error("\(Self.name(of: description), privacy: .public) stays shut this launch: \(String(describing: failures[description]), privacy: .public)")
            if let standIn = Self.memoryStandIn(in: container) {
                opened[description] = standIn
                standIns.append((description, standIn))
            }
        }
        // An in-memory store cannot fail to open, so the fallbacks below are
        // unreachable; they only keep the stores non-optional.
        privateStore = opened[privateDescription] ?? Self.memoryStandIn(in: container)!
        sharedStore = opened[sharedDescription] ?? Self.memoryStandIn(in: container)!

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        container.viewContext.transactionAuthor = Bundle.main.bundleIdentifier

        #if os(iOS)
        if isStandingIn {
            unlockObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reopenStandInStores()
            }
        }
        #endif
    }

    deinit {
        if let unlockObserver { NotificationCenter.default.removeObserver(unlockObserver) }
    }

    // MARK: - Location

    static let storeNames = ["private.sqlite", "shared.sqlite"]

    /// The app's own Application Support. The stores used to sit in the App
    /// Group, but nothing else opens them, and an SQLite lock held in a shared
    /// container when the app suspends gets it killed (0xdead10cc).
    private static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = AppGroup.containerURL.appendingPathComponent("KeyringData", isDirectory: true)
        return adoptStores(from: legacy, into: support.appendingPathComponent("KeyringData", isDirectory: true))
    }

    /// Copies each store in `legacy` that `directory` lacks through the
    /// coordinator, which carries the WAL and the CloudKit sync state along,
    /// and deletes the originals only once every copy has landed. Returns
    /// where to open the stores: `legacy` when a copy failed (a locked phone,
    /// a full disk), so a half move never opens an empty log. The next launch
    /// tries again.
    static func adoptStores(from legacy: URL, into directory: URL) -> URL {
        let files = FileManager.default
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: KeyringModel.model)
        let moves = storeNames
            .map { (from: legacy.appendingPathComponent($0), to: directory.appendingPathComponent($0)) }
            .filter { files.fileExists(atPath: $0.from.path) && !files.fileExists(atPath: $0.to.path) }
        var copied: [URL] = []
        for move in moves {
            do {
                try coordinator.replacePersistentStore(at: move.to, withPersistentStoreFrom: move.from, type: .sqlite)
                copied.append(move.to)
            } catch {
                logger.error("Moving \(move.from.lastPathComponent, privacy: .public) out of the App Group failed: \(String(describing: error), privacy: .public)")
                for url in copied { try? coordinator.destroyPersistentStore(at: url, type: .sqlite) }
                return legacy
            }
        }
        for move in moves {
            try? coordinator.destroyPersistentStore(at: move.from, type: .sqlite)
            // Destroying empties the file but can leave it, and its sidecars, behind.
            let base = move.from.deletingPathExtension().lastPathComponent
            let leftovers = ["", "-wal", "-shm"].map { URL(fileURLWithPath: move.from.path + $0) }
                + [legacy.appendingPathComponent(".\(base)_SUPPORT")]
            for url in leftovers { try? files.removeItem(at: url) }
        }
        return directory
    }

    // MARK: - Opening

    /// Adds every description to the container and reports, per description,
    /// why it did not open. Retries pass only the descriptions that failed,
    /// so a store is never added twice.
    private static func load(
        _ descriptions: [NSPersistentStoreDescription],
        in container: NSPersistentCloudKitContainer
    ) -> [NSPersistentStoreDescription: Error] {
        container.persistentStoreDescriptions = descriptions
        var failures: [NSPersistentStoreDescription: Error] = [:]
        container.loadPersistentStores { description, error in
            if let error { failures[description] = error }
        }
        // A load that reported success but left no store behind is a failure
        // too: the coordinator is the only honest answer.
        for description in descriptions where failures[description] == nil {
            if store(for: description, in: container) == nil {
                failures[description] = StoreMissing()
            }
        }
        return failures
    }

    /// A load that neither opened the store nor said why. Nothing is known to
    /// be wrong with the file, so it is never moved aside on this account.
    private struct StoreMissing: Error {}

    /// Coordinator lookups by URL are the reliable way to get the store
    /// objects back; the descriptions alone do not carry them.
    private static func store(
        for description: NSPersistentStoreDescription,
        in container: NSPersistentCloudKitContainer
    ) -> NSPersistentStore? {
        guard let url = description.url else { return nil }
        let coordinator = container.persistentStoreCoordinator
        if let store = coordinator.persistentStore(for: url) { return store }
        // The same file can be spelled two ways (/var against /private/var).
        // Match on the resolved path rather than call an open store missing.
        let wanted = url.resolvingSymlinksInPath().standardizedFileURL.path
        return coordinator.persistentStores.first {
            $0.url?.resolvingSymlinksInPath().standardizedFileURL.path == wanted
        }
    }

    private static func memoryStandIn(in container: NSPersistentCloudKitContainer) -> NSPersistentStore? {
        try? container.persistentStoreCoordinator.addPersistentStore(
            ofType: NSInMemoryStoreType,
            configurationName: nil,
            at: nil,
            options: nil
        )
    }

    /// True only when the file itself is the problem. A file that data
    /// protection is keeping shut (a background launch before the first
    /// unlock) is intact and is left exactly where it is, and so is one whose
    /// load said nothing at all.
    private static func isCorrupt(_ error: Error) -> Bool {
        if error is StoreMissing { return false }
        var next: NSError? = error as NSError
        while let error = next {
            if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError { return false }
            if error.domain == NSPOSIXErrorDomain, error.code == EPERM || error.code == EACCES { return false }
            next = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return true
    }

    private static func moveAside(_ url: URL) {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            try? FileManager.default.moveItem(at: file, to: URL(fileURLWithPath: file.path + ".unopenable-\(stamp)"))
        }
    }

    private static func name(of description: NSPersistentStoreDescription) -> String {
        description.url?.lastPathComponent ?? "store"
    }

    /// Opens the real files once the phone is unlocked, and tells every
    /// surface to refetch so nobody is left looking at the empty stand-in.
    private func reopenStandInStores() {
        let shut = standInLock.withLock { standIns }
        guard !shut.isEmpty else { return }
        container.viewContext.reset()
        var stillShut: [(description: NSPersistentStoreDescription, store: NSPersistentStore)] = []
        var reopened = false
        for (description, standIn) in shut {
            try? container.persistentStoreCoordinator.remove(standIn)
            let failure = Self.load([description], in: container)[description]
            if failure == nil, let store = Self.store(for: description, in: container) {
                adopt(store, for: description)
                reopened = true
            } else {
                Self.logger.error("\(Self.name(of: description), privacy: .public) is still shut after unlock: \(String(describing: failure), privacy: .public)")
                if let replacement = Self.memoryStandIn(in: container) {
                    adopt(replacement, for: description)
                    stillShut.append((description, replacement))
                }
            }
        }
        standInLock.withLock { standIns = stillShut }
        if stillShut.isEmpty, let unlockObserver {
            NotificationCenter.default.removeObserver(unlockObserver)
            self.unlockObserver = nil
        }
        if reopened {
            NotificationCenter.default.post(name: Self.storesDidReopen, object: self)
        }
    }

    private func adopt(_ store: NSPersistentStore, for description: NSPersistentStoreDescription) {
        if description === privateDescription {
            privateStore = store
        } else {
            sharedStore = store
        }
    }

    var viewContext: NSManagedObjectContext { container.viewContext }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.transactionAuthor = Bundle.main.bundleIdentifier
        return context
    }

    /// True when this object arrived from someone else's iCloud.
    func isShared(_ object: NSManagedObject) -> Bool {
        object.objectID.persistentStore == sharedStore
    }

    /// Puts a new object next to its parent, in whichever store the parent
    /// lives in, so a family member's entry lands in the shared garage.
    func place(_ object: NSManagedObject, beside parent: NSManagedObject, in context: NSManagedObjectContext) {
        if let store = parent.objectID.persistentStore, store !== object.objectID.persistentStore {
            context.assign(object, to: store)
        }
    }

    @discardableResult
    func save(_ context: NSManagedObjectContext) -> Bool {
        guard context.hasChanges else { return true }
        // Writing into a stand-in store would look like it worked and be gone
        // a second later. Refuse instead, and let the caller reload.
        guard !isStandingIn else {
            Self.logger.error("Refused a save: the store is not open yet")
            context.rollback()
            return false
        }
        do {
            if let saveOperation {
                try saveOperation(context)
            } else {
                try context.save()
            }
            return true
        } catch {
            Self.logger.error("Save failed: \(String(describing: error), privacy: .public)")
            context.rollback()
            return false
        }
    }
}
