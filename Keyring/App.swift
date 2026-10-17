import CloudKit
import StoreKit
import SwiftUI
import UIKit

@main
struct KeyringApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var garage = GarageStore.shared
    @StateObject private var store = StoreService.shared
    @StateObject private var sharing = SharingService.shared
    @StateObject private var community = CommunityPhotos.shared
    @AppStorage(AppGroup.Key.appearance, store: AppGroup.defaults) private var appearance = Appearance.system.rawValue

    init() {
        let ink = UIColor(Theme.ink)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .foregroundColor: ink,
            .font: UIFont(descriptor: UIFont.systemFont(ofSize: 34, weight: .bold).fontDescriptor.withDesign(.serif)!, size: 34),
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .foregroundColor: ink,
            .font: UIFont(descriptor: UIFont.systemFont(ofSize: 17, weight: .semibold).fontDescriptor.withDesign(.serif)!, size: 17),
        ]
        ConversionDiagnostics.recordAppOpen()
        ReviewPrompter.recordLaunch()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(garage)
                .environmentObject(store)
                .environmentObject(sharing)
                .environmentObject(community)
                .tint(Theme.brass)
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
                .alert("Couldn't join this garage", isPresented: Binding(
                    get: { sharing.invitationError != nil },
                    set: { if !$0 { sharing.invitationError = nil } }
                )) {
                    Button("OK", role: .cancel) { sharing.invitationError = nil }
                } message: {
                    Text(sharing.invitationError ?? "")
                }
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-InitializeCloudKitSchema") {
                        do {
                            try garage.persistence.container.initializeCloudKitSchema(options: [.printSchema])
                            print("KEYRING_SCHEMA_INITIALIZATION_SUCCEEDED")
                        } catch {
                            print("KEYRING_SCHEMA_INITIALIZATION_FAILED: \(error)")
                        }
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("-SeedDemo") {
                        AppGroup.defaults.set(true, forKey: AppGroup.Key.hasCompletedSetup)
                        DemoSeed.seed(into: garage)
                    }
                    #endif
                    store.start()
                    await sharing.refresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    garage.reload()
                    Task { await sharing.refresh() }
                }
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Match iPhone"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// CloudKit delivers an accepted share to the scene delegate in a SwiftUI
/// app, so both entry points are routed to `SharingService`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in SharingService.shared.accept(cloudKitShareMetadata) }
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        Task { @MainActor in SharingService.shared.accept(metadata) }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in SharingService.shared.accept(cloudKitShareMetadata) }
    }
}

struct RootView: View {
    @EnvironmentObject private var garage: GarageStore
    @EnvironmentObject private var sharing: SharingService
    @AppStorage(AppGroup.Key.hasCompletedSetup, store: AppGroup.defaults) private var hasCompletedSetup = false

    var body: some View {
        Group {
            if let plan = ScreenshotConfig.value(after: "-PaywallSnapshot") {
                PaywallView(displayCloseButton: false, requestedPlan: plan)
            } else if sharing.isAcceptingInvitation && garage.vehicles.isEmpty {
                JoiningView()
            } else if !hasCompletedSetup && garage.vehicles.isEmpty {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .animation(.snappy, value: hasCompletedSetup)
    }
}

struct MainTabView: View {
    enum Tab: Hashable { case garage, history, settings }

    @State private var tab: Tab = MainTabView.initialTab

    var body: some View {
        TabView(selection: $tab) {
            GarageView()
                .tabItem { Label("Garage", systemImage: "key.horizontal.fill") }
                .tag(Tab.garage)
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "book.closed.fill") }
                .tag(Tab.history)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
    }

    static var initialTab: Tab {
        switch ScreenshotConfig.value(after: "-ScreenshotRoute") {
        case "history": .history
        case "settings": .settings
        default: .garage
        }
    }
}
