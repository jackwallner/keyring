import Foundation
import UIKit
import Vision

/// What a photo of the pump display (or the pump's receipt) says. Every field
/// is shown in the form for the owner to check, never saved silently.
struct PumpFields: Equatable, Sendable {
    /// In the unit the pump shows.
    var volume: Double?
    /// Per that unit.
    var unitPrice: Double?
    var total: Double?
    var grade: FuelGrade?
    var station: String?
    var date: Date?

    var filledCount: Int { [volume != nil, unitPrice != nil, total != nil].filter { $0 }.count }
}

enum PumpReader {
    static func read(_ data: Data, unit: FuelVolumeUnit) async -> PumpFields {
        guard let image = UIImage(data: data)?.cgImage else { return PumpFields() }
        let lines = await recognizeLines(in: image)
        return parse(lines: lines, unit: unit)
    }

    /// Pump displays are digits, so language correction (which "fixes"
    /// 12.345 into words) stays off.
    static func recognizeLines(in image: CGImage) async -> [String] {
        await recognize(in: image).map(\.text)
    }

    /// Top to bottom, with each line's height for picking the biggest type.
    static func recognize(in image: CGImage) async -> [FieldReader.Line] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations
                    .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                    .compactMap { observation in
                        observation.topCandidates(1).first.map { FieldReader.Line(text: $0.string, height: observation.boundingBox.height) }
                    }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    struct Number: Equatable {
        let value: Double
        let decimals: Int
        let line: Int
        let dollar: Bool
    }

    static func numbers(in lines: [String]) -> [Number] {
        guard let regex = try? NSRegularExpression(pattern: #"(\$)?\s*(\d{1,4})(?:([.,])(\d{1,3}))?(?!\d)"#) else { return [] }
        var result: [Number] = []
        for (index, line) in lines.enumerated() {
            // Times, dates and phone numbers aren't pump figures.
            let cleaned = line.replacingOccurrences(of: #"\d{1,2}:\d{2}(:\d{2})?|\d{1,2}/\d{1,2}/\d{2,4}|\(?\d{3}\)?[ -.]\d{3}[ -.]\d{4}"#, with: " ", options: .regularExpression)
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            for match in regex.matches(in: cleaned, range: range) {
                guard let whole = Range(match.range(at: 2), in: cleaned) else { continue }
                var text = String(cleaned[whole])
                var decimals = 0
                if let fraction = Range(match.range(at: 4), in: cleaned) {
                    text += "." + cleaned[fraction]
                    decimals = cleaned[fraction].count
                }
                guard let value = Double(text) else { continue }
                result.append(Number(value: value, decimals: decimals, line: index, dollar: match.range(at: 1).location != NSNotFound))
            }
        }
        return result
    }

    private enum Role { case volume, price, total }

    private static func labels(for number: Number, in lines: [String]) -> Set<Role> {
        let own = lines[number.line].lowercased()
        let nearby = [number.line - 1, number.line + 1].filter(lines.indices.contains).map { lines[$0].lowercased() }
        var roles = Set<Role>()
        func check(_ text: String) {
            let perUnit = text.contains("/") || text.contains("per ") || text.contains("price") || text.contains("ppg") || text.contains("¢")
            if perUnit { roles.insert(.price) }
            if !perUnit, ["gallon", "gal", "litre", "liter", "ltr", "volume", "vol"].contains(where: text.contains) { roles.insert(.volume) }
            if ["sale", "total", "amount", "due", "purchase", "fuel $", "dollars"].contains(where: text.contains) { roles.insert(.total) }
        }
        check(own)
        // A label on its own line names the figure under or beside it.
        if roles.isEmpty { nearby.filter { $0.filter(\.isNumber).isEmpty }.forEach(check) }
        if number.dollar, !roles.contains(.price) { roles.insert(.total) }
        return roles
    }

    static func parse(lines: [String], unit: FuelVolumeUnit, now: Date = .now) -> PumpFields {
        var fields = PumpFields()
        let all = numbers(in: lines)
        var candidates = all.filter { $0.value > 0 && $0.value < 5_000 }
        // Canadian pumps quote cents a liter: 159.9 is $1.599.
        if unit == .liters {
            candidates += candidates.filter { (40...400).contains($0.value) && $0.decimals <= 1 }
                .map { Number(value: $0.value / 100, decimals: 3, line: $0.line, dollar: false) }
        }
        let roles = candidates.map { labels(for: $0, in: lines) }
        let priceRange: ClosedRange<Double> = unit == .gallons ? 0.5...15 : 0.15...5
        let typicalPrice: ClosedRange<Double> = unit == .gallons ? 2...7 : 0.8...2.6
        let volumeRange: ClosedRange<Double> = unit == .gallons ? 0.1...300 : 0.3...1_200

        var best: (score: Double, v: Int, p: Int, t: Int)?
        for v in candidates.indices where volumeRange.contains(candidates[v].value) {
            for p in candidates.indices where p != v && priceRange.contains(candidates[p].value) {
                for t in candidates.indices where t != v && t != p {
                    let volume = candidates[v].value, price = candidates[p].value, total = candidates[t].value
                    guard total >= 0.5, abs(volume * price - total) <= max(0.02, total * 0.006) else { continue }
                    var score = 0.0
                    if roles[v].contains(.volume) { score += 3 }
                    if roles[p].contains(.price) { score += 3 }
                    if roles[t].contains(.total) { score += 3 }
                    if candidates[v].decimals == 3 { score += 1 }
                    if candidates[p].decimals >= 2 { score += 0.5 }
                    if candidates[p].decimals == 3 { score += 0.5 }
                    if candidates[t].decimals == 2 { score += 1 }
                    if typicalPrice.contains(price) { score += 1 }
                    if candidates[t].dollar { score += 1 }
                    if score > (best?.score ?? -1) { best = (score, v, p, t) }
                }
            }
        }
        if let best {
            fields.volume = candidates[best.v].value
            fields.unitPrice = candidates[best.p].value
            fields.total = candidates[best.t].value
        } else {
            // Nothing multiplies out, so go by the labels and work out the third.
            func labeled(_ role: Role, in range: ClosedRange<Double>) -> Double? {
                candidates.indices.first { roles[$0].contains(role) && range.contains(candidates[$0].value) }.map { candidates[$0].value }
            }
            fields.volume = labeled(.volume, in: volumeRange)
            fields.unitPrice = labeled(.price, in: priceRange)
            fields.total = labeled(.total, in: 0.5...5_000)
            fields = completed(fields)
        }
        fields.grade = grade(in: lines)
        fields.station = station(in: lines)
        fields.date = lines.count >= 6 ? ReceiptReader.date(in: lines, now: now) : nil
        return fields
    }

    /// Any two of volume, price and total give the third.
    static func completed(_ fields: PumpFields) -> PumpFields {
        var fields = fields
        switch (fields.volume, fields.unitPrice, fields.total) {
        case let (v?, p?, nil): fields.total = (v * p * 100).rounded() / 100
        case let (v?, nil, t?) where v > 0: fields.unitPrice = (t / v * 1_000).rounded() / 1_000
        case let (nil, p?, t?) where p > 0: fields.volume = (t / p * 1_000).rounded() / 1_000
        default: break
        }
        return fields
    }

    /// The grade, only when the photo names exactly one: a display often sits
    /// beside all three grade buttons.
    static func grade(in lines: [String]) -> FuelGrade? {
        let text = " " + lines.joined(separator: " ").lowercased() + " "
        let words: [(FuelGrade, [String])] = [
            (.jetA, ["jet a", "jet-a", "jeta"]),
            (.avgas, ["100ll", "avgas"]),
            (.ethanolFree, ["ethanol free", "ethanol-free", "non-ethanol", "rec 90", "rec90", "recreational"]),
            (.e85, ["e85", "flex fuel"]),
            (.diesel, ["diesel"]),
            (.premium, ["premium", "supreme", "super", "v-power", "ultimate", "92 octane", "93 octane", "91 octane"]),
            (.midgrade, ["midgrade", "mid-grade", "plus", "special", "89 octane"]),
            (.regular, ["regular", "unleaded", " reg ", " unl ", "87 octane"]),
        ]
        var found: [FuelGrade] = []
        for (grade, keys) in words where keys.contains(where: text.contains) {
            // "Super unleaded" and "plus unleaded" name one grade, not two.
            if grade == .regular, found.contains(where: { [.premium, .midgrade, .ethanolFree, .e85].contains($0) }) { continue }
            found.append(grade)
        }
        return found.count == 1 ? found[0] : nil
    }

    private static let brands = [
        "Shell", "Chevron", "Costco", "Arco", "76", "BP", "Exxon", "Mobil", "ExxonMobil", "Speedway", "Circle K",
        "Safeway", "Fred Meyer", "Sam's Club", "Texaco", "Sunoco", "Valero", "Marathon", "Sinclair", "Conoco",
        "Phillips 66", "Holiday", "Wawa", "Sheetz", "QuikTrip", "Casey's", "Kroger", "Pilot", "Flying J",
        "Love's", "Maverik", "Esso", "Petro-Canada", "Husky", "Ultramar", "Pioneer", "Irving", "Gulf", "Citgo",
        "Cenex", "Murphy USA", "Buc-ee's", "RaceTrac", "Kwik Trip", "Meijer", "H-E-B", "Walmart",
    ]

    static func station(in lines: [String]) -> String? {
        for line in lines {
            for brand in brands {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: brand) + "\\b"
                if line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return brand }
            }
        }
        return nil
    }
}

/// The odometer (or hour meter) in a photo of the dash. A dash shows the trip,
/// the range, the clock and the temperature too, so the pick leans on the last
/// reading: the closest figure at or just above it.
enum OdometerReader {
    static func read(_ data: Data, last: Double, meter: MeterUnit) async -> Double? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        let lines = await PumpReader.recognizeLines(in: image)
        return pick(lines: lines, last: last, meter: meter)
    }

    static func pick(lines: [String], last: Double, meter: MeterUnit) -> Double? {
        var candidates: [(value: Double, labeled: Bool)] = []
        // Lookarounds, not word boundaries: the dash font often glues "mi" or
        // "km" to the figure ("48562mi").
        let figure = meter == .hours ? #"\d{1,3}(?:,\d{3})+(?:\.\d)?|\d{2,6}(?:\.\d)?"# : #"\d{1,3}(?:,\d{3})+|\d{3,7}"#
        let pattern = #"(?<![\d.,])(?:"# + figure + #")(?![\d,]|\.\d)"#
        for line in lines {
            let lowered = line.lowercased()
            if lowered.contains(":") || lowered.contains("°") || lowered.contains("%") { continue }
            if ["trip", "range", "mpg", "km/l", "l/100", "avg", "mph", "km/h", "dte"].contains(where: lowered.contains) { continue }
            let labeled = ["odo", "total"].contains(where: lowered.contains)
            var rest = Substring(line)
            while let range = rest.range(of: pattern, options: .regularExpression) {
                if let value = Double(rest[range].replacingOccurrences(of: ",", with: "")) {
                    candidates.append((value, labeled))
                    // "48562mi" often comes back as "485620i": the m reads as a 0.
                    if rest[range.upperBound...].first?.isLetter == true, value >= 1_000, value == value.rounded() {
                        candidates.append(((value / 10).rounded(.down), labeled))
                    }
                }
                rest = rest[range.upperBound...]
            }
        }
        if let labeled = candidates.first(where: \.labeled), last <= 0 || labeled.value >= last - 1 { return labeled.value }
        guard last > 0 else { return candidates.map(\.value).filter { $0 >= 100 }.max() }
        let ceiling = last + max(meter == .hours ? 300 : 5_000, last * 0.3)
        return candidates.map(\.value).filter { $0 >= last - 1 && $0 <= ceiling }.min()
    }
}
