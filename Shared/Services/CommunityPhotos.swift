import CloudKit
import Foundation
import os
import UIKit

/// Photos of the same make and model: ones other Keyring owners chose to
/// share, plus freely licensed reference photos from Wikimedia Commons so
/// the page is never empty.
///
/// Owner photos live in the app's CloudKit public database. App Review 1.2
/// asks for four things with user content, and each is here: owners agree to
/// the community terms before their first post, any photo can be reported,
/// any author can be blocked (their photos vanish at once on this device),
/// and the developer reviews reports in the CloudKit console within a day.
struct CommunityPhoto: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case owner(recordName: String, author: String)
        case commons(page: URL, artist: String, license: String)
    }

    let id: String
    let imageURL: URL?
    let caption: String
    let source: Source
    let date: Date?

    var isOwnerPhoto: Bool {
        if case .owner = source { return true }
        return false
    }

    var credit: String {
        switch source {
        case .owner: "Shared by a Keyring owner"
        case let .commons(_, artist, license): [artist.isEmpty ? nil : "Photo: \(artist)", license].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

@MainActor
final class CommunityPhotos: ObservableObject {
    static let shared = CommunityPhotos()

    static let recordType = "OwnerPhoto"
    static let reportType = "PhotoReport"

    @Published private(set) var blockedAuthors: Set<String>
    @Published private(set) var reportedPhotos: Set<String>

    private let logger = Logger(subsystem: AppGroup.subsystem, category: "Community")
    private var database: CKDatabase { CKContainer(identifier: AppGroup.cloudKitContainerID).publicCloudDatabase }

    init() {
        blockedAuthors = Set(AppGroup.defaults.stringArray(forKey: AppGroup.Key.blockedAuthors) ?? [])
        reportedPhotos = Set(AppGroup.defaults.stringArray(forKey: AppGroup.Key.reportedPhotos) ?? [])
    }

    var hasAcceptedTerms: Bool {
        AppGroup.defaults.bool(forKey: AppGroup.Key.acceptedCommunityTerms)
    }

    func acceptTerms() {
        AppGroup.defaults.set(true, forKey: AppGroup.Key.acceptedCommunityTerms)
        objectWillChange.send()
    }

    /// "toyota tacoma": what owner photos are filed under. Year is left out on
    /// purpose; a 2019 owner wants to see the 2021 one too.
    static func modelKey(make: String?, model: String?, kind: VehicleKind) -> String {
        let parts = [make, model].compactMap { $0?.lowercased().trimmed }.filter { !$0.isEmpty }
        return parts.isEmpty ? "kind:\(kind.rawValue)" : parts.joined(separator: " ")
    }

    // MARK: - Loading

    func photos(for vehicle: Vehicle) async -> [CommunityPhoto] {
        let key = Self.modelKey(make: vehicle.make, model: vehicle.model, kind: vehicle.kind)
        async let owners = ownerPhotos(modelKey: key)
        let make = vehicle.make
        let model = vehicle.model
        async let commons = Self.commonsPhotos(make: make, model: model)
        let all = await owners + commons
        return all.filter { photo in
            if reportedPhotos.contains(photo.id) { return false }
            if case let .owner(_, author) = photo.source, blockedAuthors.contains(author) { return false }
            return true
        }
    }

    private func ownerPhotos(modelKey: String) async -> [CommunityPhoto] {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(format: "modelKey == %@", modelKey))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        do {
            let (results, _) = try await database.records(matching: query, desiredKeys: ["image", "caption", "modelKey"], resultsLimit: 30)
            return results.compactMap { _, result in
                guard let record = try? result.get(),
                      let asset = record["image"] as? CKAsset, let url = asset.fileURL else { return nil }
                return CommunityPhoto(
                    id: record.recordID.recordName,
                    imageURL: url,
                    caption: (record["caption"] as? String) ?? "",
                    source: .owner(recordName: record.recordID.recordName, author: record.creatorUserRecordID?.recordName ?? ""),
                    date: record.creationDate
                )
            }
        } catch {
            // The record type doesn't exist until the first share in each
            // environment, and reading needs no account; quiet failure is
            // right here, the reference photos still load.
            logger.notice("owner photos unavailable: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    // MARK: - Sharing

    enum ShareError: Error {
        case noAccount
        case failed

        var message: String {
            switch self {
            case .noAccount: "Sign in to iCloud on this iPhone to share photos."
            case .failed: "Couldn't share the photo. Check your connection and try again."
            }
        }
    }

    func share(_ image: Data, caption: String, for vehicle: Vehicle) async throws {
        let container = CKContainer(identifier: AppGroup.cloudKitContainerID)
        guard (try? await container.accountStatus()) == .available else { throw ShareError.noAccount }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        let resized = ImageTools.jpeg(image, maxDimension: 1600, quality: 0.8) ?? image
        try resized.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let record = CKRecord(recordType: Self.recordType)
        record["modelKey"] = Self.modelKey(make: vehicle.make, model: vehicle.model, kind: vehicle.kind)
        record["kind"] = vehicle.kind.rawValue
        record["year"] = Int64(vehicle.year)
        record["caption"] = String(caption.trimmed.prefix(140))
        record["image"] = CKAsset(fileURL: file)
        do {
            _ = try await database.save(record)
        } catch {
            logger.error("share failed: \(String(describing: error), privacy: .public)")
            throw ShareError.failed
        }
    }

    // MARK: - Moderation

    /// Hides the photo here at once and files a report for review.
    func report(_ photo: CommunityPhoto, reason: String) {
        reportedPhotos.insert(photo.id)
        AppGroup.defaults.set(Array(reportedPhotos), forKey: AppGroup.Key.reportedPhotos)
        guard case let .owner(recordName, author) = photo.source else { return }
        let record = CKRecord(recordType: Self.reportType)
        record["photo"] = recordName
        record["author"] = author
        record["reason"] = reason
        Task {
            do {
                _ = try await database.save(record)
            } catch {
                logger.error("report failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func block(_ photo: CommunityPhoto) {
        guard case let .owner(_, author) = photo.source, !author.isEmpty else { return }
        blockedAuthors.insert(author)
        AppGroup.defaults.set(Array(blockedAuthors), forKey: AppGroup.Key.blockedAuthors)
    }

    func unblockAll() {
        blockedAuthors = []
        AppGroup.defaults.removeObject(forKey: AppGroup.Key.blockedAuthors)
    }

    // MARK: - Wikimedia Commons

    nonisolated static func commonsPhotos(make: String?, model: String?) async -> [CommunityPhoto] {
        let words = [make, model].compactMap { $0?.trimmed }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        let phrase = words.joined(separator: " ")
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: "filetype:bitmap \"\(phrase)\""),
            URLQueryItem(name: "gsrnamespace", value: "6"),
            URLQueryItem(name: "gsrlimit", value: "16"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|extmetadata"),
            URLQueryItem(name: "iiurlwidth", value: "800"),
            URLQueryItem(name: "iiextmetadatafilter", value: "Artist|LicenseShortName"),
            URLQueryItem(name: "format", value: "json"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Keyring/1.0 (https://jackwallner.github.io/keyring/)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await NHTSAClient.session.data(for: request) else { return [] }
        return parseCommons(data, mustMention: words)
    }

    nonisolated static func parseCommons(_ data: Data, mustMention words: [String]) -> [CommunityPhoto] {
        struct Envelope: Decodable {
            struct Query: Decodable { let pages: [String: Page] }
            struct Page: Decodable {
                let title: String
                let index: Int?
                let imageinfo: [Info]?
            }
            struct Info: Decodable {
                let thumburl: String?
                let descriptionurl: String?
                let extmetadata: [String: Meta]?
            }
            struct Meta: Decodable { let value: String? }
            let query: Query?
        }
        guard let pages = (try? JSONDecoder().decode(Envelope.self, from: data))?.query?.pages.values else { return [] }
        let needles = words.map { $0.lowercased() }
        return pages
            .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
            .compactMap { page -> CommunityPhoto? in
                let title = page.title.replacingOccurrences(of: "File:", with: "")
                let lowered = title.lowercased()
                // Search matches descriptions too; the file name naming the
                // vehicle is what keeps sunsets and dashboards out.
                guard needles.allSatisfy({ lowered.contains($0) }),
                      let info = page.imageinfo?.first,
                      let thumb = info.thumburl.flatMap(URL.init(string:)),
                      let pageURL = info.descriptionurl.flatMap(URL.init(string:)) else { return nil }
                let artist = stripHTML(info.extmetadata?["Artist"]?.value ?? "")
                let license = info.extmetadata?["LicenseShortName"]?.value ?? ""
                let caption = (title as NSString).deletingPathExtension
                return CommunityPhoto(
                    id: pageURL.absoluteString,
                    imageURL: thumb,
                    caption: caption,
                    source: .commons(page: pageURL, artist: artist, license: license),
                    date: nil
                )
            }
    }

    nonisolated static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmed
    }
}
