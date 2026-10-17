import CoreGraphics
import Foundation

/// What a typed field expects, so a photo of the plate, the dash or a label
/// fills in just that.
enum FieldScan: Equatable, Sendable {
    case plate
    case vin
    case reading(last: Double, meter: MeterUnit)
    case amount
    case text

    var hint: String {
        switch self {
        case .plate: "Tap the plate number"
        case .vin: "Point at the VIN on the windshield or door jamb"
        case let .reading(_, meter): meter == .hours ? "Tap the hours on the meter" : "Tap the number on the dash"
        case .amount: "Tap the amount"
        case .text: "Tap the text to use"
        }
    }
}

/// Picks a field's value out of recognized text. Pure, so the rules are tested.
enum FieldReader {
    struct Line: Equatable, Sendable {
        let text: String
        /// Share of the photo's height; the plate number is the biggest text on a plate.
        let height: CGFloat
    }

    /// The one item the owner tapped in the live scanner.
    static func tapped(_ raw: String, for kind: FieldScan) -> String? {
        switch kind {
        case .plate: plateNumber(raw)
        case .vin: vin(in: [raw])
        case .reading:
            raw.filter(\.isNumber).count >= 1 ? raw.filter { $0.isNumber || $0 == "." }.trimmingCharacters(in: CharacterSet(charactersIn: ".")) : nil
        case .amount: amount(in: [raw]).map(format)
        case .text: clean(raw)
        }
    }

    /// The best guess from a whole photo, or nil to let the owner pick a line.
    static func best(in lines: [Line], for kind: FieldScan) -> String? {
        switch kind {
        case .plate: plate(in: lines)
        case .vin: vin(in: lines.map(\.text))
        case let .reading(last, meter): OdometerReader.pick(lines: lines.map(\.text), last: last, meter: meter).map(format)
        case .amount: amount(in: lines.map(\.text)).map(format)
        case .text: nil
        }
    }

    /// Plates print the state, a slogan and a web address in small type
    /// around one big number.
    static func plate(in lines: [Line]) -> String? {
        lines.compactMap { line in plateNumber(line.text).map { (value: $0, height: line.height) } }
            .max { $0.height < $1.height }?.value
    }

    static func plateNumber(_ raw: String) -> String? {
        let upper = raw.uppercased()
        guard !upper.contains("."), !upper.contains("/"), !upper.contains(":") else { return nil }
        let kept = upper.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }
            .trimmingCharacters(in: .whitespaces)
        let compact = kept.filter { $0.isLetter || $0.isNumber }
        // Real plates run 2 to 8 characters and nearly all carry a digit.
        guard (2...8).contains(compact.count), compact.contains(where: \.isNumber) else { return nil }
        guard kept.split(separator: " ").count <= 3 else { return nil }
        return kept
    }

    static func vin(in lines: [String]) -> String? {
        let tokens = lines.flatMap { $0.components(separatedBy: .whitespacesAndNewlines) } + lines
        return tokens.compactMap(NHTSAClient.normalizedVIN).first
    }

    /// The biggest money figure: a receipt's total or a valuation's headline.
    static func amount(in lines: [String]) -> Double? {
        // "$24,150", "$28,400.00" or a bare "412.37"; the comma groups thousands.
        let pattern = #"(\$\s*)?(\d{1,3}(?:,\d{3})+|\d+)(\.\d{2})?(?![\d,])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        var values: [Double] = []
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            for match in regex.matches(in: line, range: range) {
                let dollar = match.range(at: 1).location != NSNotFound
                let cents = match.range(at: 3).location != NSNotFound
                guard dollar || cents, let whole = Range(match.range(at: 2), in: line) else { continue }
                var text = line[whole].replacingOccurrences(of: ",", with: "")
                if cents, let fraction = Range(match.range(at: 3), in: line) { text += line[fraction] }
                if let value = Double(text) { values.append(value) }
            }
        }
        return values.max()
    }

    private static func clean(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
