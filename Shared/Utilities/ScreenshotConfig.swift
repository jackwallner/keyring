import Foundation

/// App Store captures run from launch arguments; surfaces that must stay out
/// of marketing shots (the review prompt) check this. Always false in Release.
enum ScreenshotConfig {
    #if DEBUG
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-SeedDemo") || args.contains("-PaywallSnapshot") || args.contains("-ScreenshotRoute")
    }

    static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    #else
    static let isEnabled = false
    static func value(after flag: String) -> String? { nil }
    #endif
}
