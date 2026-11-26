import Foundation

/// Everything RevenueCat can change without a release, read from the current
/// offering's metadata (a running Experiment's variant included). Every
/// variant ships in the binary; a missing, non-string or unknown value is the
/// control, which is what shipped before. Keys a switch reads must be set the
/// same on every offering, or an Experiment arm would flip them as a side
/// effect.
///
/// DEBUG builds can pin any key for captures: `-keyring.rc.<key> <value>`.

/// The onboarding trial button's wording. The paywall button stays neutral
/// ("Continue with Pro", see `ConversionCopy.ctaLabel`) and is not a test
/// surface.
enum TrialCTA: String, CaseIterable, Sendable {
    static let metadataKey = "trial_cta"

    /// Control: "Start free trial", as shipped since 1.0. The trial is seven
    /// days, hence the raw value.
    case sevenDay = "seven_day"
    case my
    case your

    static func from(metadata: [String: Any]?) -> TrialCTA {
        RemoteConfig.value(metadataKey, in: metadata, default: .sevenDay)
    }

    var title: String {
        switch self {
        case .sevenDay: return "Start free trial"
        case .my: return "Start my free trial"
        case .your: return "Start your free trial"
        }
    }

    /// An Apple Account that already used its free week is charged on day
    /// one, so its button promises no trial (3.1.2).
    func title(trialEligible: Bool) -> String {
        trialEligible ? title : "Continue with Pro"
    }
}

/// Remote off switches, for what is worth pausing without a release. On
/// unless the metadata says "off".
enum RemoteSwitch: String, CaseIterable, Sendable {
    /// The automatic star prompt after a good moment. "off" pauses it; the
    /// Rate row in Settings is unaffected.
    case ratingPrompt = "rating_prompt"
}

enum RemoteConfig {
    /// The value for `key`, or `fallback` when it is missing, not a string,
    /// or not one of the shipped variants.
    static func value<T: RawRepresentable>(_ key: String, in metadata: [String: Any]?, default fallback: T) -> T
    where T.RawValue == String {
        #if DEBUG
        if let pinned = launchOverride(key).flatMap(T.init(rawValue:)) { return pinned }
        #endif
        guard let raw = metadata?[key] as? String else { return fallback }
        return T(rawValue: raw) ?? fallback
    }

    static func isOn(_ remoteSwitch: RemoteSwitch, in metadata: [String: Any]?) -> Bool {
        #if DEBUG
        if let pinned = launchOverride(remoteSwitch.rawValue) { return pinned != "off" }
        #endif
        return (metadata?[remoteSwitch.rawValue] as? String) != "off"
    }

    #if DEBUG
    private static func launchOverride(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-keyring.rc.\(key)"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    #endif
}

extension StoreService {
    var trialCTAArm: TrialCTA { TrialCTA.from(metadata: remoteMetadata) }

    func isOn(_ remoteSwitch: RemoteSwitch) -> Bool { RemoteConfig.isOn(remoteSwitch, in: remoteMetadata) }
}
