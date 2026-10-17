import Foundation
import UIKit

extension Recall {
    /// The maker's own numbers ("Toyota's numbers for this recall are J16/J06"),
    /// which is what a dealer's repair order prints.
    var makerCodes: [String] {
        guard let regex = try? NSRegularExpression(pattern: #"numbers? for this recall (?:is|are) ([^.]+)"#, options: .caseInsensitive) else { return [] }
        var codes: [String] = []
        let range = NSRange(remedy.startIndex..., in: remedy)
        for match in regex.matches(in: remedy, range: range) {
            guard let list = Range(match.range(at: 1), in: remedy) else { continue }
            for token in remedy[list].uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let code = String(token)
                guard (3...10).contains(code.count), code.contains(where: \.isNumber), code.contains(where: \.isLetter) || code.count >= 5 else { continue }
                if !codes.contains(code) { codes.append(code) }
            }
        }
        return codes
    }

    /// NHTSA's number as people write it: 20V682000, 20V-682, 20V682.
    var nhtsaForms: [String] {
        let upper = campaign.uppercased()
        guard upper.count >= 6 else { return [upper] }
        let head = upper.prefix(3), body = upper.dropFirst(3).prefix(3)
        return [upper, "\(head)-\(body)", "\(head)\(body)"]
    }
}

/// Finds recalls the log already shows were done: a fix logged against the
/// recall, or an entry whose title, notes or receipt names its number.
enum RecallMatcher {
    static func mentions(_ recall: Recall, in text: String) -> Bool {
        let upper = text.uppercased()
        // A short maker code like J16 could be a part number, so it only
        // counts beside the word recall or campaign.
        let context = ["RECALL", "CAMPAIGN", "SSC", "SAFETY"].contains(where: upper.contains)
        let terms = recall.nhtsaForms + recall.makerCodes.filter { $0.count >= 5 || context }
        return terms.contains { term in
            upper.range(of: "(?<![A-Z0-9])" + NSRegularExpression.escapedPattern(for: term) + "(?![A-Z0-9])", options: .regularExpression) != nil
        }
    }

    @MainActor
    static func fix(for recall: Recall, on vehicle: Vehicle) -> ServiceEntry? {
        let entries = (vehicle.entries ?? []).filter { !$0.isDeleted && $0.kind != .fuel }
        if let logged = entries.first(where: { $0.recallCampaign == recall.campaign }) { return logged }
        return entries.first { entry in
            let typed = [entry.title, entry.notes].compactMap { $0 }.joined(separator: "\n")
            if mentions(recall, in: typed) { return true }
            return (entry.attachments ?? []).contains { attachment in
                guard attachment.isReceipt, let id = attachment.id, let text = ReceiptText.cached(id) else { return false }
                return mentions(recall, in: text)
            }
        }
    }

    /// Reads receipts saved before this check existed, so old dealer
    /// paperwork counts. True when anything new was read.
    @MainActor
    static func readReceipts(on vehicle: Vehicle) async -> Bool {
        let unread = (vehicle.entries ?? []).filter { !$0.isDeleted && $0.kind != .fuel }
            .flatMap { $0.attachments ?? [] }
            .filter { $0.isReceipt && $0.id.map { ReceiptText.cached($0) == nil } == true }
        for attachment in unread {
            guard let id = attachment.id, let data = attachment.data, let image = UIImage(data: data)?.cgImage else { continue }
            let lines = await ReceiptReader.recognizeLines(in: image)
            ReceiptText.store(lines.joined(separator: "\n"), for: id)
        }
        return !unread.isEmpty
    }
}

/// What each saved receipt says, read once and kept on the device.
@MainActor
enum ReceiptText {
    private static var memory: [String: String]?
    private static var file: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("receipt-text.json")
    }

    static func cached(_ id: UUID) -> String? {
        load()[id.uuidString]
    }

    static func store(_ text: String, for id: UUID) {
        var all = load()
        all[id.uuidString] = String(text.prefix(4_000))
        memory = all
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: file, options: .atomic) }
    }

    private static func load() -> [String: String] {
        if let memory { return memory }
        let loaded = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        memory = loaded
        return loaded
    }
}
