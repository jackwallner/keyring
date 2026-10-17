import Foundation
import StoreKit

/// Every URL the app opens. Outside links always open in Safari or the
/// destination's own app, never an in-app web view (Amazon requires it, and
/// it keeps people signed in where they already are).
enum AppLinks {
    /// App Store Connect record `Vehicle Maintenance Log`.
    static let appStoreID = "6823808045"

    static let privacyPolicy = URL(string: "https://jackwallner.github.io/keyring/privacy-policy.html")!
    static let terms = URL(string: "https://jackwallner.github.io/keyring/terms.html")!
    static let support = URL(string: "https://jackwallner.github.io/keyring/support.html")!
    static let communityGuidelines = URL(string: "https://jackwallner.github.io/keyring/community.html")!
    static let standardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
    static let supportEmail = "jackwallner@gmail.com"

    static var feedback: URL {
        URL(string: "mailto:\(supportEmail)?subject=Vehicle%20Maintenance%20Log%20feedback")!
    }

    static func reportPhoto(id: String) -> URL {
        URL(string: "mailto:\(supportEmail)?subject=Vehicle%20Maintenance%20Log%20photo%20report&body=Photo%20\(id)")!
    }

    static var writeReview: URL {
        if let country = Locale.current.region?.identifier.lowercased(), country.count == 2 {
            return URL(string: "https://apps.apple.com/\(country)/app/id\(appStoreID)?action=write-review")!
        }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    }

    static var shareApp: URL { URL(string: "https://apps.apple.com/app/id\(appStoreID)")! }
}

/// Amazon search links for parts, tools and upgrades.
///
/// `associateTag` is empty until the Amazon Associates account is approved.
/// With a tag, links carry it and the app shows Amazon's required disclosure;
/// without one they are plain searches. Affiliate links never go into the
/// printed Service Record (Amazon's offline-use rule).
enum AmazonLinks {
    static let associateTag = ""

    static var isAffiliate: Bool { !associateTag.isEmpty }

    static let disclosure = "As an Amazon Associate, Vehicle Maintenance Log earns from qualifying purchases."

    /// The reader's own Amazon store, so prices and shipping are local.
    static func host(region: String? = Locale.current.region?.identifier) -> String {
        switch region {
        case "CA": "www.amazon.ca"
        case "GB", "IE": "www.amazon.co.uk"
        case "AU", "NZ": "www.amazon.com.au"
        case "DE", "AT", "CH": "www.amazon.de"
        case "FR", "BE": "www.amazon.fr"
        case "IT": "www.amazon.it"
        case "ES": "www.amazon.es"
        case "NL": "www.amazon.nl"
        case "MX": "www.amazon.com.mx"
        case "JP": "www.amazon.co.jp"
        case "IN": "www.amazon.in"
        default: "www.amazon.com"
        }
    }

    static func search(_ query: String, region: String? = Locale.current.region?.identifier) -> URL {
        var components = URLComponents(string: "https://\(host(region: region))/s")!
        var items = [URLQueryItem(name: "k", value: query)]
        if isAffiliate { items.append(URLQueryItem(name: "tag", value: associateTag)) }
        components.queryItems = items
        return components.url!
    }

    /// Fills `{vehicle}` and `{make}` in a catalog query. A vehicle with no
    /// make or model falls back to its kind, so a search still lands somewhere
    /// useful.
    static func resolve(_ template: String, vehicle: Vehicle) -> String {
        let full = vehicle.descriptor.isEmpty ? vehicle.kind.title.lowercased() : vehicle.descriptor
        let make = (vehicle.make?.isEmpty == false ? vehicle.make! : vehicle.kind.title.lowercased())
        return template
            .replacingOccurrences(of: "{vehicle}", with: full)
            .replacingOccurrences(of: "{make}", with: make)
    }
}

/// Where to check what a vehicle is worth. Keyring never shows a third-party
/// value as its own; it opens the source and lets the owner note the figure.
struct ValueSource: Identifiable, Hashable {
    let name: String
    let detail: String
    let url: URL
    var id: String { name }

    static func sources(for vehicle: Vehicle, region: String? = Locale.current.region?.identifier) -> [ValueSource] {
        let isRoad = [.car, .suv, .truck, .van].contains(vehicle.kind)
        if isRoad, let local = localCarSources(for: vehicle, region: region) {
            return local + [ebaySold(for: vehicle, region: region)].compactMap { $0 }
        }
        return usSources(for: vehicle) + [ebaySold(for: vehicle, region: region)].compactMap { $0 }
    }

    /// Price guides people outside the US actually use.
    private static func localCarSources(for vehicle: Vehicle, region: String?) -> [ValueSource]? {
        let query = vehicle.makeAndModel
        switch region {
        case "CA":
            var trader = URLComponents(string: "https://www.autotrader.ca/cars/")!
            if !query.isEmpty { trader.queryItems = [URLQueryItem(name: "kwd", value: query)] }
            return [
                ValueSource(name: "Canadian Black Book", detail: "Trade-in and retail values", url: URL(string: "https://www.canadianblackbook.com/")!),
                ValueSource(name: "AutoTrader.ca", detail: "Asking prices for similar cars", url: trader.url!),
            ]
        case "GB", "IE":
            return [
                ValueSource(name: "Auto Trader", detail: "Free car valuation", url: URL(string: "https://www.autotrader.co.uk/car-valuation")!),
                ValueSource(name: "Parkers", detail: "Price guide", url: URL(string: "https://www.parkers.co.uk/car-valuation/")!),
            ]
        case "AU", "NZ":
            return [
                ValueSource(name: "RedBook", detail: "Car values", url: URL(string: "https://www.redbook.com.au/")!),
                ValueSource(name: "carsales", detail: "Asking prices for similar cars", url: URL(string: "https://www.carsales.com.au/")!),
            ]
        default:
            return nil
        }
    }

    private static func ebaySold(for vehicle: Vehicle, region: String?) -> ValueSource? {
        let year = vehicle.year > 0 ? String(vehicle.year) : nil
        let query = [year, vehicle.make, vehicle.model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        guard !query.isEmpty else { return nil }
        let host = switch region {
        case "CA": "www.ebay.ca"
        case "GB", "IE": "www.ebay.co.uk"
        case "AU", "NZ": "www.ebay.com.au"
        case "DE", "AT", "CH": "www.ebay.de"
        default: "www.ebay.com"
        }
        var ebay = URLComponents(string: "https://\(host)/sch/i.html")!
        ebay.queryItems = [
            URLQueryItem(name: "_nkw", value: query),
            URLQueryItem(name: "LH_Sold", value: "1"),
            URLQueryItem(name: "LH_Complete", value: "1"),
        ]
        return ValueSource(name: "eBay sold listings", detail: "What similar ones actually sold for", url: ebay.url!)
    }

    private static func usSources(for vehicle: Vehicle) -> [ValueSource] {
        let make = slug(vehicle.make)
        let model = slug(vehicle.model)
        let year = vehicle.year > 0 ? String(vehicle.year) : nil
        let mileage = vehicle.meter == .miles && vehicle.reading > 0 ? Int(vehicle.reading) : nil
        var list: [ValueSource] = []

        switch vehicle.kind {
        case .car, .suv, .truck, .van:
            var kbb = "https://www.kbb.com/"
            if let make { kbb += "\(make)/" }
            if make != nil, let model { kbb += "\(model)/" }
            if make != nil, model != nil, let year { kbb += "\(year)/" }
            var components = URLComponents(string: kbb)!
            var items = [URLQueryItem(name: "intent", value: "trade-in-sell")]
            if let mileage { items.append(URLQueryItem(name: "mileage", value: String(mileage))) }
            components.queryItems = items
            list.append(ValueSource(name: "Kelley Blue Book", detail: "Trade-in and private party values", url: components.url!))
            var edmunds = "https://www.edmunds.com/"
            if let make, let model, let year { edmunds += "\(make)/\(model)/\(year)/appraisal.html" } else { edmunds += "appraisal/" }
            list.append(ValueSource(name: "Edmunds", detail: "True Market Value appraisal", url: URL(string: edmunds)!))
        case .motorcycle, .scooter:
            list.append(ValueSource(name: "Kelley Blue Book", detail: "Motorcycle values", url: URL(string: "https://www.kbb.com/motorcycles/")!))
            list.append(ValueSource(name: "J.D. Power", detail: "Motorcycle values", url: URL(string: "https://www.jdpower.com/motorcycles")!))
        case .rv, .camper:
            list.append(ValueSource(name: "J.D. Power", detail: "RV and camper values", url: URL(string: "https://www.jdpower.com/rvs")!))
        case .boat, .sailboat, .personalWatercraft:
            list.append(ValueSource(name: "J.D. Power", detail: "Boat and engine values", url: URL(string: "https://www.jdpower.com/boats")!))
        case .aircraft:
            list.append(ValueSource(name: "Aircraft Bluebook", detail: "The aircraft industry's price guide", url: URL(string: "https://www.aircraftbluebook.com/")!))
            let query = vehicle.makeAndModel.isEmpty ? "" : vehicle.makeAndModel
            var controller = URLComponents(string: "https://www.controller.com/listings/search")!
            controller.queryItems = [URLQueryItem(name: "keywords", value: query)]
            list.append(ValueSource(name: "Controller", detail: "Listings for similar aircraft", url: controller.url!))
        case .atv, .snowmobile:
            list.append(ValueSource(name: "J.D. Power", detail: "Powersports values", url: URL(string: "https://www.jdpower.com/motorcycles")!))
        default:
            break
        }
        // Sold listings (added by the caller) are an honest value for
        // anything with a resale market.
        return list
    }

    static func slug(_ text: String?) -> String? {
        guard let text = text?.trimmed, !text.isEmpty else { return nil }
        let lowered = text.lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return lowered.isEmpty ? nil : lowered
    }
}
