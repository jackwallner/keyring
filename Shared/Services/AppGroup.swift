import Foundation

/// Identifiers and keys every process shares: the app and the widget.
enum AppGroup {
    static let id = "group.com.jackwallner.keyring"
    static let cloudKitContainerID = "iCloud.com.jackwallner.keyring"
    static let bundleID = "com.jackwallner.keyring"
    static let subsystem = "com.jackwallner.keyring"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }

    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    enum Key {
        static let cachedPro = "isPro"
        static let hasCompletedSetup = "hasCompletedSetup"
        static let ownerName = "ownerName"
        static let widgetSnapshot = "widgetSnapshot"
        static let appearance = "appearance"
        static let mutedVehicles = "mutedVehicles"
        static let reminderHour = "reminderHour"
        static let acceptedCommunityTerms = "acceptedCommunityTerms"
        static let reviewedRecalls = "reviewedRecalls"
        static let launchCount = "launchCount"
        static let lastReviewRequest = "lastReviewRequest"
        static let wroteReview = "wroteReview"
        static let pendingReviewMoment = "pendingReviewMoment"
        static let funnelSteps = "funnelSteps"
        static let hideCosts = "hideCosts"
        static let lastOpenedVehicle = "lastOpenedVehicle"
        static let pendingFirstVehicle = "pendingFirstVehicle"
        static let plannedVehicles = "plannedVehicles"
        static let recallCache = "recallCache"
        static let lastRecallCheck = "lastRecallCheck"
        static let vinRecallChecks = "vinRecallChecks"
        static let vehicleSectionOrder = "vehicleSectionOrder"
    }
}
