import Foundation
import UIKit
import Vision

/// Reads a shop receipt on the device: the total, the date, the mileage and
/// the shop's name. Nothing leaves the phone. Every field it fills is shown
/// for the owner to check, never saved silently.
struct ReceiptFields: Equatable, Sendable {
    var total: Double?
    var date: Date?
    var reading: Double?
    var shop: String?

    var isEmpty: Bool { total == nil && date == nil && reading == nil && shop == nil }

    var filledCount: Int { [total != nil, date != nil, reading != nil, shop != nil].filter { $0 }.count }
}

enum ReceiptReader {
    static func read(_ data: Data) async -> ReceiptFields {
        await readWithText(data).fields
    }

    /// The fields plus every line read, for spotting a recall's number.
    static func readWithText(_ data: Data) async -> (fields: ReceiptFields, text: String) {
        guard let image = UIImage(data: data)?.cgImage else { return (ReceiptFields(), "") }
        let lines = await recognizeLines(in: image)
        return (parse(lines: lines), lines.joined(separator: "\n"))
    }

    /// Recognized text, top to bottom.
    static func recognizeLines(in image: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations
                    .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    /// Pure parsing, so it is testable with plain strings.
    static func parse(lines: [String], now: Date = .now) -> ReceiptFields {
        var fields = ReceiptFields()
        fields.total = total(in: lines)
        fields.date = date(in: lines, now: now)
        fields.reading = mileage(in: lines)
        fields.shop = shop(in: lines)
        return fields
    }

    private static let moneyPattern = #"\$?\s*([0-9]{1,3}(?:,[0-9]{3})*|[0-9]+)\.([0-9]{2})\b"#

    static func amounts(in line: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: moneyPattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let whole = Range(match.range(at: 1), in: line), let cents = Range(match.range(at: 2), in: line) else { return nil }
            return Double(line[whole].replacingOccurrences(of: ",", with: "") + "." + line[cents])
        }
    }

    /// The amount on a "total" line, preferring "grand total", "amount due"
    /// and "balance" over a subtotal; failing that, the largest amount.
    static func total(in lines: [String]) -> Double? {
        let ranked = ["grand total", "amount due", "balance due", "total due", "invoice total", "total"]
        for keyword in ranked {
            for (index, line) in lines.enumerated() where line.lowercased().contains(keyword) && !line.lowercased().contains("subtotal") {
                if let value = amounts(in: line).last { return value }
                // Many receipts print the amount on the next line.
                if index + 1 < lines.count, let value = amounts(in: lines[index + 1]).first { return value }
            }
        }
        return lines.flatMap(amounts(in:)).filter { $0 < 50_000 }.max()
    }

    static func date(in lines: [String], now: Date) -> Date? {
        let formats = ["MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy", "yyyy-MM-dd", "MMM d, yyyy", "MMM dd, yyyy", "MMMM d, yyyy", "dd MMM yyyy", "MM-dd-yyyy"]
        let patterns = [
            #"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#,
            #"\b\d{4}-\d{2}-\d{2}\b"#,
            #"\b\d{1,2}-\d{1,2}-\d{4}\b"#,
            #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.? \d{1,2},? \d{4}\b"#,
            #"\b\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{4}\b"#,
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for line in lines {
            for pattern in patterns {
                guard let range = line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
                let text = String(line[range]).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "Sept", with: "Sep")
                for format in formats {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: text),
                       date <= now.addingTimeInterval(86_400),
                       date > now.addingTimeInterval(-20 * 365 * 86_400) {
                        return date
                    }
                }
            }
        }
        return nil
    }

    /// The odometer, from a line that names it: "Mileage In: 45,231",
    /// "ODO 45231", "Miles: 45,231".
    static func mileage(in lines: [String]) -> Double? {
        let keywords = ["odometer", "mileage", "odo", "miles in", "mileage in", "miles", "km", "hours"]
        for line in lines {
            let lowered = line.lowercased()
            guard keywords.contains(where: lowered.contains) else { continue }
            guard let range = line.range(of: #"\b\d{1,3}(?:,\d{3})+\b|\b\d{3,7}\b"#, options: .regularExpression) else { continue }
            if let value = Double(line[range].replacingOccurrences(of: ",", with: "")), value >= 10, value < 2_000_000 {
                return value
            }
        }
        return nil
    }

    /// The business name is nearly always the first line with real letters
    /// in it that isn't an address, phone number or a word like "receipt".
    static func shop(in lines: [String]) -> String? {
        let skip = ["receipt", "invoice", "welcome", "customer", "copy", "order", "repair order", "estimate", "thank"]
        for line in lines.prefix(6) {
            let trimmed = line.trimmed
            let letters = trimmed.filter(\.isLetter).count
            guard letters >= 3, trimmed.count <= 40 else { continue }
            let lowered = trimmed.lowercased()
            if skip.contains(where: lowered.hasPrefix) { continue }
            if trimmed.range(of: #"^\d+ "#, options: .regularExpression) != nil { continue }
            if trimmed.range(of: #"\(?\d{3}\)?[ -.]\d{3}[ -.]\d{4}"#, options: .regularExpression) != nil { continue }
            return trimmed.localizedCapitalized
        }
        return nil
    }
}
