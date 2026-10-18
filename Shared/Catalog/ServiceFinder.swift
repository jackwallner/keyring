import Foundation

/// Where to get the work done: shops, mechanics who come to you, and
/// detailers. Searches open Apple Maps around wherever the owner is, worded
/// for the kind of vehicle. National booking sites (checked 2026-10-17) are
/// US only and road vehicles only.
struct LocalService: Identifiable, Hashable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case shops, mobile, detailing

        var title: String {
            switch self {
            case .shops: "Shops near you"
            case .mobile: "Comes to you"
            case .detailing: "Detailing"
            }
        }
    }

    let title: String
    let detail: String
    let symbol: String
    let group: Group
    let url: URL

    var id: String { title }

    static func maps(_ query: String) -> URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url!
    }
}

enum ServiceFinder {
    /// Map search words per kind: (shop, mobile mechanic, detailer). A nil
    /// mobile term means nobody really offers that service on the go.
    static func terms(for kind: VehicleKind) -> (shop: String, mobile: String?, detail: String?) {
        switch kind {
        case .car, .suv, .van, .truck: ("auto repair", "mobile mechanic", "mobile car detailing")
        case .motorcycle, .scooter: ("motorcycle repair", "mobile motorcycle mechanic", "motorcycle detailing")
        case .rv, .camper: ("RV repair", "mobile RV repair", "mobile RV detailing")
        case .trailer: ("trailer repair", "mobile trailer repair", nil)
        case .boat, .personalWatercraft, .sailboat: ("marine mechanic", "mobile marine mechanic", "mobile boat detailing")
        case .aircraft: ("aircraft maintenance", nil, "aircraft detailing")
        case .atv, .snowmobile: ("powersports repair", "mobile powersports repair", nil)
        case .tractor: ("small engine repair", "mobile small engine repair", nil)
        case .ebike: ("ebike repair", "mobile bike repair", nil)
        case .golfCart: ("golf cart repair", "mobile golf cart repair", nil)
        case .other: ("repair shop", nil, nil)
        }
    }

    static func services(for vehicle: Vehicle, us: Bool) -> [LocalService] {
        services(kind: vehicle.kind, make: vehicle.make, us: us)
    }

    static func services(kind: VehicleKind, make: String?, us: Bool) -> [LocalService] {
        let terms = terms(for: kind)
        let road = [.car, .suv, .van, .truck].contains(kind)
        var list = [LocalService(title: "Repair shops", detail: "Independent shops nearby in Maps, with hours and reviews.", symbol: "wrench.and.screwdriver.fill", group: .shops, url: LocalService.maps(terms.shop))]
        if let make = make?.trimmingCharacters(in: .whitespaces), !make.isEmpty, road || kind == .motorcycle || kind == .boat {
            list.append(LocalService(title: "\(make) dealer service", detail: "Factory-trained techs and recall work, which is free at a dealer.", symbol: "building.2.fill", group: .shops, url: LocalService.maps("\(make) dealer service")))
        }
        if road, us {
            list.append(LocalService(title: "RepairPal", detail: "Certified shops that honor RepairPal's fair price estimate.", symbol: "checkmark.seal.fill", group: .shops, url: URL(string: "https://repairpal.com/auto-repair-near-me")!))
        }
        if let mobile = terms.mobile {
            list.append(LocalService(title: road ? "Mobile mechanics" : "Mobile repair", detail: "Local mechanics who do the job in your driveway or at work.", symbol: "car.side.fill", group: .mobile, url: LocalService.maps(mobile)))
        }
        if road, us {
            list.append(LocalService(title: "YourMechanic", detail: "Book a mobile mechanic online with an upfront quote.", symbol: "calendar.badge.clock", group: .mobile, url: URL(string: "https://www.yourmechanic.com/")!))
            list.append(LocalService(title: "Wrench", detail: "Mobile repair, diagnostics and brakes in many US cities.", symbol: "calendar.badge.clock", group: .mobile, url: URL(string: "https://wrench.com/")!))
        }
        if let detail = terms.detail {
            list.append(LocalService(title: road ? "Mobile car detailing" : "Detailing", detail: "Detailers who wash, polish and clean the interior wherever it's parked.", symbol: "sparkles", group: .detailing, url: LocalService.maps(detail)))
        }
        if road {
            list.append(LocalService(title: "Detail shops", detail: "Shops for paint correction, ceramic coating and tint.", symbol: "drop.fill", group: .detailing, url: LocalService.maps("auto detailing")))
        }
        return list
    }
}
