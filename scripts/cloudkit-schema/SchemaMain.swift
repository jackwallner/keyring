import AppKit
import CloudKit
import CoreData
import Foundation

/// A setup tool, never part of the iPhone app. It uses the real model and an
/// isolated temporary store, so the app's own data is never opened.
///
/// - no argument: Apple's schema dry run against the model.
/// - `--initialize-development`: creates the private-database record types.
/// - `--verify-share`: shares a temporary garage with the app's own
///   `ShareInvite`, which is what creates the `cloudkit.share` type, checks the
///   link, then purges the zone.
/// - `--public-types`: saves and deletes one `OwnerPhoto` and one
///   `PhotoReport` in the public database so both types and their fields exist.
@main
@MainActor
struct SchemaMain {
    static let containerID = "iCloud.com.jackwallner.keyring"

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { await run() }
        app.run()
    }

    private static func report(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private static func run() async {
        do {
            let environment = Bundle.main.object(forInfoDictionaryKey: "SchemaCloudKitEnvironment") as? String ?? "Unknown"
            report("KEYRING_CLOUD_ENVIRONMENT: \(environment)")
            let writesSchema = CommandLine.arguments.contains("--initialize-development") || CommandLine.arguments.contains("--public-types")
            if writesSchema, environment != "Development" { throw SchemaError.wrongEnvironment }
            let cloud = CKContainer(identifier: containerID)
            guard try await cloud.accountStatus() == .available else { throw SchemaError.noAccount }
            if CommandLine.arguments.contains("--public-types") {
                try await createPublicTypes(in: cloud)
                report("KEYRING_PUBLIC_TYPES_CREATED")
                exit(EXIT_SUCCESS)
            }
            let container = try await makeContainer()
            if CommandLine.arguments.contains("--verify-share") {
                try await verifyShare(using: container, cloud: cloud)
                report("KEYRING_SHARE_VERIFIED_AND_FIXTURE_REMOVED")
                exit(EXIT_SUCCESS)
            }
            let dryRun = !CommandLine.arguments.contains("--initialize-development")
            let options: NSPersistentCloudKitContainerSchemaInitializationOptions = dryRun ? [.dryRun, .printSchema] : [.printSchema]
            try container.initializeCloudKitSchema(options: options)
            report(dryRun ? "KEYRING_SCHEMA_VALIDATION_SUCCEEDED" : "KEYRING_SCHEMA_INITIALIZATION_SUCCEEDED")
            exit(EXIT_SUCCESS)
        } catch {
            report("KEYRING_SCHEMA_FAILED: \(error)")
            exit(EXIT_FAILURE)
        }
    }

    private static func verifyShare(using source: NSPersistentCloudKitContainer, cloud: CKContainer) async throws {
        let garage = Garage.make(in: source.viewContext, name: "Temporary share verification")
        try source.viewContext.save()
        // Sharing before the first CloudKit setup finishes fails inside Core
        // Data; an exported record is the observable proof it has.
        try await waitUntil(timeout: 600) { source.recordID(for: garage.objectID) != nil }
        report("KEYRING_SHARE_STORE_READY")
        guard let store = garage.objectID.persistentStore else { throw SchemaError.shareHasNoStore }
        let share = try await ShareInvite.prepare(for: [garage], title: garage.displayName, container: source, database: cloud.privateCloudDatabase)
        let zoneID = share.recordID.zoneID
        defer { Task { _ = try? await source.purgeObjectsAndRecordsInZone(with: zoneID, in: store) } }
        guard let url = share.url else { throw SchemaError.shareHasNoURL }
        report("KEYRING_SHARE_URL_HOST: \(url.host ?? "none")")
        let record = try await cloud.privateCloudDatabase.record(for: share.recordID)
        guard let cloudShare = record as? CKShare, cloudShare.publicPermission == .readWrite else { throw SchemaError.inviteNotOpen }
        report("KEYRING_SHARE_IS_READ_WRITE_LINK")
        let metadata = try await cloud.shareMetadata(for: url)
        guard metadata.share.recordID == share.recordID, metadata.participantRole == .owner else { throw SchemaError.inviteNotOpen }
        report("KEYRING_SHARE_LINK_RESOLVES")
        _ = try await source.purgeObjectsAndRecordsInZone(with: zoneID, in: store)
        report("KEYRING_SHARE_ZONE_PURGED")
    }

    private static func createPublicTypes(in cloud: CKContainer) async throws {
        let database = cloud.publicCloudDatabase
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("keyring-schema-\(UUID().uuidString).jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let photo = CKRecord(recordType: "OwnerPhoto")
        photo["modelKey"] = "schema|fixture|car"
        photo["kind"] = "car"
        photo["year"] = Int64(2020)
        photo["caption"] = "Schema fixture"
        photo["image"] = CKAsset(fileURL: file)
        let savedPhoto = try await database.save(photo)
        report("KEYRING_PUBLIC_OWNER_PHOTO_SAVED")

        let flag = CKRecord(recordType: "PhotoReport")
        flag["photo"] = savedPhoto.recordID.recordName
        flag["author"] = "schema-fixture"
        flag["reason"] = "Schema fixture"
        let savedFlag = try await database.save(flag)
        report("KEYRING_PUBLIC_PHOTO_REPORT_SAVED")

        _ = try await database.deleteRecord(withID: savedFlag.recordID)
        _ = try await database.deleteRecord(withID: savedPhoto.recordID)
        report("KEYRING_PUBLIC_FIXTURES_DELETED")
    }

    private static func makeContainer() async throws -> NSPersistentCloudKitContainer {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeyringSchema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = NSPersistentCloudKitContainer(name: "Keyring", managedObjectModel: KeyringModel.model)
        let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("schema.sqlite"))
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions = [description]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }

    private static func waitUntil(timeout: TimeInterval = 120, _ condition: () async throws -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .seconds(2))
        }
        throw SchemaError.timedOut
    }

    enum SchemaError: Error {
        case noAccount, timedOut, wrongEnvironment, shareHasNoStore, shareHasNoURL, inviteNotOpen
    }
}
