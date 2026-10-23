import Foundation

/// Who insures the vehicle and who tows it: the numbers to have on the
/// shoulder. Lives in the profile JSON, so it syncs and shares with the
/// garage without a schema change.
struct RoadsideInfo: Codable, Equatable, Sendable {
    var insurer = ""
    var policyNumber = ""
    var claimsPhone = ""
    var roadsideName = ""
    var roadsidePhone = ""
    var memberNumber = ""

    var hasInsurance: Bool { ![insurer, policyNumber, claimsPhone].allSatisfy(\.trimmed.isEmpty) }
    var hasRoadside: Bool { ![roadsideName, roadsidePhone, memberNumber].allSatisfy(\.trimmed.isEmpty) }
    var isEmpty: Bool { !hasInsurance && !hasRoadside }

    var cleaned: RoadsideInfo {
        RoadsideInfo(insurer: insurer.trimmed, policyNumber: policyNumber.trimmed, claimsPhone: claimsPhone.trimmed,
                     roadsideName: roadsideName.trimmed, roadsidePhone: roadsidePhone.trimmed, memberNumber: memberNumber.trimmed)
    }

    /// 1-800-AAA-HELP, the one roadside number that works for any US member.
    static let aaa = (name: "AAA", phone: "1-800-222-4357")
}

enum PhoneLink {
    /// A `tel:` link from however the number was typed, letters included
    /// ("1-800-AAA-HELP"). Nil when there aren't enough digits to dial.
    static func url(_ number: String) -> URL? {
        let dialable = number.uppercased().compactMap { char -> Character? in
            if char.isNumber || (char == "+") { return char }
            return keypad[char]
        }
        guard dialable.filter(\.isNumber).count >= 3 else { return nil }
        return URL(string: "tel:\(String(dialable))")
    }

    private static let keypad: [Character: Character] = {
        let groups = ["2": "ABC", "3": "DEF", "4": "GHI", "5": "JKL", "6": "MNO", "7": "PQRS", "8": "TUV", "9": "WXYZ"]
        var map: [Character: Character] = [:]
        for (digit, letters) in groups { for letter in letters { map[letter] = Character(digit) } }
        return map
    }()
}
