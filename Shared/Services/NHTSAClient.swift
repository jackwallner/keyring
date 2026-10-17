import Foundation

/// The two free U.S. government lookups: decoding a VIN and listing open
/// safety recalls. No key, no account, nothing about the owner is sent
/// beyond the VIN or the year, make and model.
struct DecodedVIN: Equatable, Sendable {
    var year: Int?
    var make: String
    var model: String
    var trim: String
    var kind: VehicleKind?
    var powertrain: Powertrain?
    var engine: String
    var drive: String
    var body: String

    /// A short line for confirmation: "3.5L V6 · 4WD · Pickup".
    var summary: String {
        [engine, drive, body].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct Recall: Identifiable, Hashable, Codable, Sendable {
    var campaign: String
    var component: String
    var summary: String
    var consequence: String
    var remedy: String
    var reported: Date?
    var parkIt: Bool
    var parkOutside: Bool

    var id: String { campaign }

    /// "Fuel system, gasoline" from "FUEL SYSTEM, GASOLINE:DELIVERY:FUEL PUMP".
    var componentTitle: String {
        let first = component.split(separator: ":").first.map(String.init) ?? component
        return first.capitalized(with: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "Abs", with: "ABS")
    }

    var nhtsaURL: URL {
        URL(string: "https://www.nhtsa.gov/recalls?nhtsaId=\(campaign)")!
    }
}

enum NHTSAClient {
    enum LookupError: Error, Equatable {
        case invalidVIN
        case notFound
        case offline

        var message: String {
            switch self {
            case .invalidVIN: "A VIN is 17 letters and numbers, with no I, O or Q. Check it against the windshield or door sticker."
            case .notFound: "NHTSA didn't recognize that VIN. You can fill in the details by hand."
            case .offline: "Couldn't reach NHTSA. Check your connection and try again."
            }
        }
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: configuration)
    }()

    /// VINs exclude I, O and Q so they can't be mistaken for 1 and 0.
    static func normalizedVIN(_ text: String) -> String? {
        let cleaned = text.uppercased().filter { $0.isLetter || $0.isNumber }
        guard cleaned.count == 17, !cleaned.contains(where: { "IOQ".contains($0) }) else { return nil }
        return cleaned
    }

    static func decode(vin text: String) async throws -> DecodedVIN {
        guard let vin = normalizedVIN(text) else { throw LookupError.invalidVIN }
        let url = URL(string: "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/\(vin)?format=json")!
        let data: Data
        do {
            (data, _) = try await session.data(from: url)
        } catch {
            throw LookupError.offline
        }
        guard let decoded = parseDecode(data) else { throw LookupError.notFound }
        return decoded
    }

    static func parseDecode(_ data: Data) -> DecodedVIN? {
        struct Envelope: Decodable { let Results: [[String: String?]] }
        guard let row = (try? JSONDecoder().decode(Envelope.self, from: data))?.Results.first else { return nil }
        func value(_ key: String) -> String { (row[key] ?? nil)?.trimmed ?? "" }
        let make = value("Make").localizedCapitalized
        let model = value("Model")
        guard !make.isEmpty || !model.isEmpty else { return nil }

        let fuel = value("FuelTypePrimary").lowercased()
        let electrification = value("ElectrificationLevel").lowercased()
        let powertrain: Powertrain? =
            electrification.contains("bev") || fuel == "electric" ? .electric
            : electrification.contains("phev") ? .plugInHybrid
            : electrification.contains("hev") ? .hybrid
            : fuel.contains("diesel") ? .diesel
            : fuel.contains("gasoline") ? .gasoline
            : nil

        let type = value("VehicleType").lowercased()
        let body = value("BodyClass")
        let lowerBody = body.lowercased()
        let kind: VehicleKind? =
            type.contains("motorcycle") ? .motorcycle
            : type.contains("trailer") ? .trailer
            : type.contains("incomplete") || lowerBody.contains("motorhome") ? .rv
            : type.contains("truck") && lowerBody.contains("pickup") ? .truck
            : lowerBody.contains("van") ? .van
            : lowerBody.contains("sport utility") || type.contains("multipurpose") ? .suv
            : type.contains("passenger car") ? .car
            : type.contains("truck") ? .truck
            : nil

        var engine = ""
        if let liters = Double(value("DisplacementL")), liters > 0 {
            engine = String(format: "%.1fL", liters)
            if let cylinders = Int(value("EngineCylinders")), cylinders > 0 {
                engine += cylinders <= 4 || cylinders == 5 ? " \(cylinders)-cyl" : " V\(cylinders)"
            }
        } else if powertrain == .electric {
            engine = "Electric"
        }
        let drive = value("DriveType").components(separatedBy: "/").first ?? ""

        return DecodedVIN(
            year: Int(value("ModelYear")),
            make: make,
            model: model,
            trim: value("Trim"),
            kind: kind,
            powertrain: powertrain,
            engine: engine,
            drive: drive,
            body: body
        )
    }

    static func recalls(year: Int, make: String, model: String) async throws -> [Recall] {
        var components = URLComponents(string: "https://api.nhtsa.gov/recalls/recallsByVehicle")!
        components.queryItems = [
            URLQueryItem(name: "make", value: make),
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "modelYear", value: String(year)),
        ]
        let data: Data
        do {
            (data, _) = try await session.data(from: components.url!)
        } catch {
            throw LookupError.offline
        }
        return parseRecalls(data)
    }

    static func parseRecalls(_ data: Data) -> [Recall] {
        struct Envelope: Decodable {
            struct Row: Decodable {
                let NHTSACampaignNumber: String?
                let Component: String?
                let Summary: String?
                let Consequence: String?
                let Remedy: String?
                let ReportReceivedDate: String?
                let parkIt: Bool?
                let parkOutSide: Bool?
            }
            let results: [Row]?
        }
        guard let rows = (try? JSONDecoder().decode(Envelope.self, from: data))?.results else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        var seen = Set<String>()
        return rows.compactMap { row -> Recall? in
            guard let campaign = row.NHTSACampaignNumber, seen.insert(campaign).inserted else { return nil }
            return Recall(
                campaign: campaign,
                component: row.Component ?? "",
                summary: row.Summary?.trimmed ?? "",
                consequence: row.Consequence?.trimmed ?? "",
                remedy: row.Remedy?.trimmed ?? "",
                reported: row.ReportReceivedDate.flatMap(formatter.date(from:)),
                parkIt: row.parkIt ?? false,
                parkOutside: row.parkOutSide ?? false
            )
        }
        .sorted { ($0.reported ?? .distantPast) > ($1.reported ?? .distantPast) }
    }

    /// Model names for a make and year, for the add-vehicle autocomplete.
    static func models(make: String, year: Int?) async -> [String] {
        let escaped = make.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? make
        let path = year.map { "GetModelsForMakeYear/make/\(escaped)/modelyear/\($0)" } ?? "GetModelsForMake/\(escaped)"
        guard let url = URL(string: "https://vpic.nhtsa.dot.gov/api/vehicles/\(path)?format=json"),
              let (data, _) = try? await session.data(from: url) else { return [] }
        struct Envelope: Decodable {
            struct Row: Decodable { let Model_Name: String? }
            let Results: [Row]
        }
        let names = (try? JSONDecoder().decode(Envelope.self, from: data))?.Results.compactMap(\.Model_Name) ?? []
        return Array(Set(names)).sorted()
    }
}

/// Recalls an owner has read and marked done or not applicable, per vehicle.
/// Kept on the device: a recall is about the car, but "I've dealt with it"
/// is easy to re-tap on a second phone, and it keeps the shared model lean.
enum RecallLedger {
    static func reviewed(for vehicleID: UUID?) -> Set<String> {
        guard let key = vehicleID?.uuidString,
              let map = AppGroup.defaults.dictionary(forKey: AppGroup.Key.reviewedRecalls) as? [String: [String]] else { return [] }
        return Set(map[key] ?? [])
    }

    static func setReviewed(_ campaign: String, _ reviewed: Bool, for vehicleID: UUID?) {
        guard let key = vehicleID?.uuidString else { return }
        var map = (AppGroup.defaults.dictionary(forKey: AppGroup.Key.reviewedRecalls) as? [String: [String]]) ?? [:]
        var set = Set(map[key] ?? [])
        if reviewed { set.insert(campaign) } else { set.remove(campaign) }
        map[key] = Array(set)
        AppGroup.defaults.set(map, forKey: AppGroup.Key.reviewedRecalls)
    }
}
