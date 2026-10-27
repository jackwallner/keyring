import Foundation

/// App Store captures run from launch arguments; surfaces that must stay out
/// of marketing shots (the review prompt) check this. Always false in Release.
enum ScreenshotConfig {
    #if DEBUG
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-SeedDemo") || args.contains("-PaywallSnapshot") || args.contains("-ScreenshotRoute")
            || args.contains("-DuoScreen")
    }

    /// The `-ScreenshotRoute` a capture asked for, directly or through `-DuoScreen`.
    static var route: String? {
        value(after: "-ScreenshotRoute") ?? DuoScreen.current?.route
    }

    static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    #else
    static let isEnabled = false
    static func value(after flag: String) -> String? { nil }
    static let route: String? = nil
    #endif
}

#if DEBUG
/// `-DuoScreen <surface>`: one App Store surface for the iPhone Duo set, so
/// each gh-sim `--screen` launch captures it folded and unfolded. Unfolded,
/// the tab sits in the leading pane and the vehicle and its route fill the
/// trailing one; folded, the vehicle is pushed as a tap would.
enum DuoScreen: String, CaseIterable {
    case garage, schedule, explore, history, build

    static var current: DuoScreen? {
        ScreenshotConfig.value(after: "-DuoScreen").flatMap { DuoScreen(rawValue: $0.lowercased()) }
    }

    /// The tab the leading pane opens on.
    var tab: MainTabView.Tab { self == .history ? .history : .garage }

    /// The seeded vehicle the surface opens, by its place in the garage
    /// (`DemoSeed`: Tacoma, Rebel, Lake boat, Cessna, RAV4).
    var vehicleIndex: Int {
        switch self {
        case .garage, .build: 0
        case .schedule: 1
        case .history: 2
        case .explore: 4
        }
    }

    /// The vehicle screen's existing `-ScreenshotRoute` behaviour. Garage and
    /// History show the vehicle only in the unfolded pane, so folded they
    /// stay on their own screen.
    var route: String? {
        switch self {
        case .garage, .history: nil
        case .schedule: "pace"
        case .explore: "explore"
        case .build: "build"
        }
    }
}
#endif
