import Foundation

#if DEBUG
/// A believable family garage for App Store screenshots and previews: a
/// truck, a hybrid, a motorcycle, a boat and a plane, each with a couple of
/// years of history. Runs only into the in-memory store (`-SeedDemo`).
@MainActor
enum DemoSeed {
    static func seed(into store: GarageStore, now: Date = .now) {
        guard store.vehicles.isEmpty else { return }
        store.setOwnerName("Jack")
        let garage = store.ensureOwnGarage()
        garage.name = "The Wallner garage"
        let day: TimeInterval = 86_400

        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * day) }

        // Truck
        var draft = NewVehicle(kind: .truck, powertrain: .gasoline, meter: .miles, year: 2019, make: "Toyota", model: "Tacoma", trim: "TRD Off-Road", nickname: "The Tacoma", vin: "3TMCZ5AN2KM198431", plate: "CHX4120", reading: 48_210, tint: .racingGreen)
        draft.lastDone = [:]
        let truck = store.addVehicle(draft, to: garage, now: ago(700))
        history(truck, store: store, now: now, pace: 34, start: 24_400, entries: [
            (680, ["oil", "rotate"], "Oil change and rotation", 89.95, "Lithia Toyota", false, "Jack"),
            (520, ["oil"], "Oil change", 0, "", true, "Jack"),
            (430, ["brakes"], "Front brake pads", 312.40, "Les Schwab", false, "Jack"),
            (340, ["oil", "rotate", "cabinFilter"], "", 74.10, "", true, "Jack"),
            (250, ["airFilter"], "", 28.99, "", true, "Sam"),
            (160, ["oil", "rotate"], "", 94.50, "Lithia Toyota", false, "Jack"),
            (45, ["battery"], "Battery test", 0, "Les Schwab", false, "Sam"),
        ])
        truck.facts = [
            VehicleFact(label: "Oil", value: "0W-20 synthetic, 6.2 qt"),
            VehicleFact(label: "Tire size", value: "265/70R16"),
            VehicleFact(label: "Wiper sizes", value: "26\" / 18\""),
            VehicleFact(label: "Paint code", value: "6X3 Army Green"),
        ]
        var profile = truck.profile
        profile.roadside = RoadsideInfo(insurer: "Cascade Mutual", policyNumber: "CM-4471-0928", claimsPhone: "1-800-555-0142",
                                        roadsideName: "Cascade Roadside", roadsidePhone: "1-800-555-0199", memberNumber: "429 118 776")
        truck.profile = profile
        store.addValuation(31_850, source: "Kelley Blue Book, private party", to: truck, at: ago(20))
        // The build: what went on the truck, with part numbers.
        let build: [(Double, Double, String, String, String, Double, String, Bool)] = [
            (610, 25_900, "Bilstein", "5100 shocks, front and rear", "24-285964", 520, "", true),
            (600, 26_100, "BFGoodrich", "All-Terrain T/A KO2 265/70R16", "KO2-2657016", 1_236, "Les Schwab", false),
            (480, 29_800, "RCI", "Full skid plate set", "RCI-TAC16-SKID", 1_150, "", true),
            (390, 33_050, "Rigid Industries", "D-Series ditch lights", "RIG-202113", 389.95, "", true),
            (300, 36_200, "Old Man Emu", "BP-51 lift, 2.5 in", "OME-BP51-TAC", 3_480, "Sierra Overland", false),
            (210, 39_900, "Method", "701 wheels, 16x8", "MR70168060500", 1_040, "Les Schwab", false),
            (120, 43_600, "Rago Fabrication", "Molle panel set", "RAGO-TAC-MOLLE", 179.99, "", true),
        ]
        for (daysAgo, reading, brand, name, number, price, shop, diy) in build {
            var mod = GarageStore.ServiceDraft()
            mod.kind = .mod
            mod.date = ago(daysAgo)
            mod.reading = reading
            mod.title = "\(brand) \(name)"
            mod.cost = price
            mod.shop = shop
            mod.isDIY = diy
            mod.details.parts = [EntryPart(name: name, brand: brand, number: number, quantity: 1, price: price)]
            let entry = store.log(mod, for: truck)
            entry.loggedBy = "Jack"
            // The BP-51s replaced the Bilsteins.
            if brand == "Bilstein" { store.setRemoved(entry, on: ago(300)) }
        }
        // Fill-ups about every nine days, one of them a top-up.
        let fills: [(Double, Double, Double, Double, String, Bool)] = [
            (66, 46_000, 15.902, 3.599, "Costco", false),
            (57, 46_310, 16.204, 3.629, "Costco", false),
            (48, 46_605, 15.418, 3.659, "Shell", false),
            (41, 46_830, 6.112, 3.699, "Chevron", true),
            (33, 47_120, 9.874, 3.579, "Costco", false),
            (24, 47_430, 16.031, 3.549, "Costco", false),
            (14, 47_760, 17.226, 3.589, "Shell", false),
            (4, 48_090, 16.583, 3.659, "Costco", false),
        ]
        for (daysAgo, reading, gallons, price, station, partial) in fills {
            var fill = GarageStore.FuelDraft()
            fill.unit = .gallons
            fill.date = ago(daysAgo)
            fill.reading = reading
            fill.volume = gallons
            fill.unitPrice = price
            fill.grade = .regular
            fill.station = station
            fill.partial = partial
            let entry = store.logFuel(fill, for: truck)
            entry.loggedBy = daysAgo == 24 || daysAgo == 41 ? "Sam" : "Jack"
        }
        truck.reading = 48_210

        // Hybrid
        draft = NewVehicle(kind: .suv, powertrain: .hybrid, meter: .miles, year: 2021, make: "Toyota", model: "RAV4", trim: "XLE Hybrid", nickname: "Sam's RAV4", vin: "2T3RWRFV4MW118204", plate: "CDK7781", reading: 31_402, tint: .sky)
        let rav = store.addVehicle(draft, to: garage, now: ago(600))
        history(rav, store: store, now: now, pace: 38, start: 9_200, entries: [
            (560, ["oil", "rotate"], "", 0, "Lithia Toyota", false, "Sam"),
            (380, ["oil", "rotate"], "", 68.20, "Lithia Toyota", false, "Sam"),
            (130, ["oil", "rotate", "cabinFilter"], "", 112.85, "Lithia Toyota", false, "Sam"),
            (12, ["wipers"], "New wiper blades", 41.98, "", true, "Jack"),
        ])
        rav.facts = [VehicleFact(label: "Oil", value: "0W-16 synthetic"), VehicleFact(label: "Tire pressure", value: "35 psi")]

        // Motorcycle
        draft = NewVehicle(kind: .motorcycle, powertrain: .gasoline, meter: .miles, year: 2020, make: "Honda", model: "Rebel 500", nickname: "Rebel", reading: 6_118, tint: .oxblood)
        let bike = store.addVehicle(draft, to: garage, now: ago(500))
        history(bike, store: store, now: now, pace: 6, start: 3_100, entries: [
            (200, ["oil"], "Spring oil change", 0, "", true, "Jack"),
            (90, ["chain"], "", 0, "", true, "Jack"),
            (20, ["chain", "tires"], "", 18.99, "", true, "Jack"),
        ])

        // Boat
        draft = NewVehicle(kind: .boat, powertrain: .sterndrive, meter: .hours, year: 2016, make: "Sea Ray", model: "SPX 190", nickname: "Lake boat", plate: "WN 4471 RS", reading: 212, tint: .marine)
        let boat = store.addVehicle(draft, to: garage, now: ago(420))
        history(boat, store: store, now: now, pace: 0.18, start: 151, entries: [
            (345, ["winterize"], "Winterized", 389.00, "Clackamas Marine", false, "Jack"),
            (230, ["impeller", "oil"], "Spring commissioning", 612.75, "Clackamas Marine", false, "Jack"),
        ])

        // Aircraft
        draft = NewVehicle(kind: .aircraft, powertrain: .piston, meter: .hours, year: 1978, make: "Cessna", model: "172N", nickname: "N734CP", plate: "N734CP", reading: 3_874.6, tint: .cream)
        let plane = store.addVehicle(draft, to: garage, now: ago(400))
        history(plane, store: store, now: now, pace: 0.22, start: 3_790, entries: [
            (330, ["annual", "elt"], "Annual inspection", 2_840.00, "Pearson Field Aviation", false, "Jack"),
            (70, ["oil"], "", 164.20, "", true, "Jack"),
        ])
        // The garage leads with one of each kind, so the first screen shows the range.
        for (index, vehicle) in [truck, bike, boat, plane, rav].enumerated() { vehicle.sortIndex = Int16(index) }
        store.save()
    }

    private static func history(
        _ vehicle: Vehicle,
        store: GarageStore,
        now: Date,
        pace: Double,
        start: Double,
        entries: [(Double, [String], String, Double, String, Bool, String)]
    ) {
        let current = vehicle.reading
        // The reading saved when the vehicle was added is the one it had then.
        for reading in vehicle.readings ?? [] { reading.value = start }
        let tasks = vehicle.tasks ?? []
        for (daysAgo, keys, title, cost, shop, isDIY, by) in entries {
            let date = now.addingTimeInterval(-daysAgo * 86_400)
            let reading = vehicle.meter.hasReading ? min(current, start + (current - start) * (1 - daysAgo / max(entries.map(\.0).max() ?? 1, 1))) : nil
            var ids: [UUID] = []
            for key in keys {
                if let task = tasks.first(where: { $0.catalogKey == key }), let id = task.id {
                    task.isEnabled = true
                    ids.append(id)
                } else if let item = vehicle.catalogItem(key: key) {
                    let task = store.makeTask(from: item, for: vehicle)
                    if let id = task.id { ids.append(id) }
                }
            }
            var draft = GarageStore.ServiceDraft()
            draft.date = date
            draft.reading = reading.map { ($0 / 10).rounded() * 10 }
            draft.taskIDs = ids
            draft.title = title
            draft.cost = cost
            draft.shop = shop
            draft.isDIY = isDIY
            let entry = store.log(draft, for: vehicle)
            entry.loggedBy = by
        }
        vehicle.reading = current
        vehicle.readingDate = now.addingTimeInterval(-3 * 86_400)
        store.updateReading(vehicle, to: current, at: now.addingTimeInterval(-3 * 86_400))
        _ = pace
    }
}
#endif
