import Foundation

/// What NHTSA's VIN lookup said about one vehicle: which recalls are still
/// unrepaired on it. NHTSA guards that lookup with reCAPTCHA, so the app
/// shows its page in a sheet with the VIN filled in, the owner taps Search,
/// and the result is read off the page. Kept on the device, like the ledger.
struct VINRecallCheck: Codable, Equatable, Sendable {
    struct Open: Codable, Equatable, Sendable {
        var nhtsa: String
        var maker: String
        var status: String
        var summary: String
    }

    var vin: String
    var date: Date
    /// False when NHTSA has no VIN data from this maker, so nothing can be hidden.
    var covered: Bool
    var open: [Open]
    /// Campaigns on the model's list when the check ran. One listed later
    /// isn't in the VIN result yet, so it stays visible until the next check.
    var known: [String]

    func isOpen(_ recall: Recall) -> Bool {
        let key = Self.key(recall.campaign)
        return open.contains { Self.key($0.nhtsa) == key }
    }

    func knew(_ recall: Recall) -> Bool {
        let key = Self.key(recall.campaign)
        return known.contains { Self.key($0) == key }
    }

    /// Still worth showing: open on this VIN, or listed after the check.
    func shows(_ recall: Recall) -> Bool {
        !covered || isOpen(recall) || !knew(recall)
    }

    /// Open on the VIN but missing from the model's list (a maker's own data
    /// NHTSA hasn't posted yet), as rows of their own.
    func unlisted(in recalls: [Recall]) -> [Recall] {
        let listed = Set(recalls.map { Self.key($0.campaign) })
        return open.filter { !listed.contains(Self.key($0.nhtsa)) }.map { item in
            Recall(campaign: item.nhtsa, component: item.maker.isEmpty ? "Recall \(item.nhtsa)" : "Recall \(item.maker)",
                   summary: item.summary.capitalizedSentence, consequence: "", remedy: item.status,
                   reported: nil, parkIt: false, parkOutside: false)
        }
    }

    /// NHTSA writes the same campaign as 25V455000 in its data and 25V455 on the VIN page.
    static func key(_ campaign: String) -> String {
        let code = campaign.uppercased().filter { $0.isLetter || $0.isNumber }
        return code.count == 9 && code.hasSuffix("000") ? String(code.prefix(6)) : code
    }

    // MARK: - Reading the page

    struct PageResult: Decodable {
        var state: String
        var vin: String?
        var count: Int?
        var recalls: [Open]?
    }

    /// Builds a check from what the page script posted, or nil if it isn't a result for this VIN.
    static func parse(_ json: String, vin: String, known: [Recall], at date: Date = .now) -> VINRecallCheck? {
        guard let data = json.data(using: .utf8),
              let page = try? JSONDecoder().decode(PageResult.self, from: data) else { return nil }
        if let shown = page.vin, shown.uppercased() != vin.uppercased() { return nil }
        let campaigns = known.map(\.campaign)
        switch page.state {
        case "none":
            return VINRecallCheck(vin: vin, date: date, covered: false, open: [], known: campaigns)
        case "ok":
            return VINRecallCheck(vin: vin, date: date, covered: true, open: page.recalls ?? [], known: campaigns)
        default:
            return nil
        }
    }

    static let lookupURL = URL(string: "https://www.nhtsa.gov/recalls")!

    /// Fills the VIN in and watches for the result. It never presses Search:
    /// the owner does, on NHTSA's own page.
    static func pageScript(vin: String) -> String {
        """
        (function () {
          const vin = "\(vin.uppercased().filter { $0.isLetter || $0.isNumber })";
          if (window.__vinCheck) return; window.__vinCheck = true;
          function field() {
            return document.getElementById('ymm-vin-recalls-search-input')
              || [...document.querySelectorAll('input')].find(i => /VIN/i.test(i.placeholder || ''));
          }
          function fill() {
            const el = field(); if (!el) return false;
            if (el.value !== vin) {
              Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, vin);
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            }
            el.scrollIntoView({ block: 'center' });
            return true;
          }
          function read() {
            const box = document.querySelector('.active-recalls--list'); if (!box) return null;
            const text = box.innerText;
            const page = document.body.innerText;
            const shown = (page.match(/VIN:\\s*([A-HJ-NPR-Z0-9]{17})/) || [])[1];
            if (/No recall information found/i.test(text)) return { state: 'none', vin: shown };
            const count = (text.match(/(\\d+)\\s*Unrepaired Recall/) || [])[1];
            if (count === undefined) return null;
            const recalls = text.split('Manufacturer Recall Number').slice(1).map(b => ({
              maker: ((b.match(/^\\s*([A-Z0-9-]+)/) || [])[1] || ''),
              nhtsa: ((b.match(/NHTSA Recall Number\\s*([0-9]{2}[A-Z][0-9]{3,6})/) || [])[1] || ''),
              status: ((b.match(/Recall Status\\s*([^\\n]+)/) || [])[1] || '').trim(),
              summary: ((b.match(/Summary\\s*\\n+([^\\n]+)/) || [])[1] || '').trim()
            })).filter(r => r.nhtsa);
            if (recalls.length < Number(count)) return null;
            return { state: 'ok', vin: shown, count: Number(count), recalls };
          }
          let filled = false;
          const timer = setInterval(() => {
            if (!filled) filled = fill();
            const result = read();
            if (result) { clearInterval(timer); window.webkit.messageHandlers.recalls.postMessage(JSON.stringify(result)); }
          }, 400);
        })();
        """
    }
}

/// The last VIN check per vehicle.
enum VINRecallChecks {
    static func check(for vehicle: Vehicle) -> VINRecallCheck? {
        guard let key = vehicle.id?.uuidString,
              let map = AppGroup.defaults.dictionary(forKey: AppGroup.Key.vinRecallChecks) as? [String: Data],
              let data = map[key],
              let check = try? JSONDecoder().decode(VINRecallCheck.self, from: data) else { return nil }
        // A changed VIN means the old answer was about another vehicle.
        guard let vin = vehicle.vin, vin.uppercased() == check.vin.uppercased() else { return nil }
        return check
    }

    static func save(_ check: VINRecallCheck, for vehicle: Vehicle) {
        guard let key = vehicle.id?.uuidString else { return }
        var map = (AppGroup.defaults.dictionary(forKey: AppGroup.Key.vinRecallChecks) as? [String: Data]) ?? [:]
        map[key] = try? JSONEncoder().encode(check)
        AppGroup.defaults.set(map, forKey: AppGroup.Key.vinRecallChecks)
    }
}

private extension String {
    /// "IT IS POSSIBLE FOR..." from the VIN page, as "It is possible for...".
    var capitalizedSentence: String {
        let lower = lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}
