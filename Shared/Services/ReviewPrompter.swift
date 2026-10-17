import Foundation

/// When to ask for an App Store rating: at a good moment (a job just logged,
/// a first vehicle set up), from the second launch on, at most once a month.
/// No "enjoying it?" gate; App Review rejects that (5.6.1).
enum ReviewPrompter {
    static let cooldown: TimeInterval = 30 * 86_400

    static func recordLaunch() {
        let defaults = AppGroup.defaults
        defaults.set(defaults.integer(forKey: AppGroup.Key.launchCount) + 1, forKey: AppGroup.Key.launchCount)
    }

    static func shouldAsk(now: Date = .now) -> Bool {
        guard !ScreenshotConfig.isEnabled else { return false }
        let defaults = AppGroup.defaults
        guard defaults.integer(forKey: AppGroup.Key.launchCount) >= 2 else { return false }
        if let last = defaults.object(forKey: AppGroup.Key.lastReviewRequest) as? Date, now.timeIntervalSince(last) < cooldown {
            return false
        }
        return true
    }

    static func markAsked(now: Date = .now) {
        AppGroup.defaults.set(now, forKey: AppGroup.Key.lastReviewRequest)
    }
}
