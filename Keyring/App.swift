import BackgroundTasks
import CloudKit
import StoreKit
import SwiftUI
import UIKit
import UserNotifications

@main
struct KeyringApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var garage = GarageStore.shared
    @StateObject private var store = StoreService.shared
    @StateObject private var sharing = SharingService.shared
    @AppStorage(AppGroup.Key.appearance, store: AppGroup.defaults) private var appearance = Appearance.system.rawValue

    init() {
        let ink = UIColor(Theme.ink)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .foregroundColor: ink,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold),
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .foregroundColor: ink,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        ]
        ConversionDiagnostics.recordAppOpen()
        ReviewPrompter.recordLaunch()
        #if DEBUG
        // A first install: onboarding, then the garage it plans.
        if ProcessInfo.processInfo.arguments.contains("-Onboarding") {
            AppGroup.defaults.set(false, forKey: AppGroup.Key.hasCompletedSetup)
            AppGroup.defaults.removeObject(forKey: AppGroup.Key.plannedVehicles)
            // A `-DemoPro` run caches Pro; a first install has none.
            AppGroup.defaults.set(false, forKey: AppGroup.Key.cachedPro)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(garage)
                .environmentObject(store)
                .environmentObject(sharing)
                .tint(Theme.brass)
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
                .onOpenURL { NotificationRouter.shared.open($0) }
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
                    await RecallWatcher.checkIfDue(store: garage)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { KeyringApp.scheduleRecallRefresh() }
                    guard phase == .active else { return }
                    garage.reload()
                    Task {
                        await sharing.refresh()
                        await RecallWatcher.checkIfDue(store: garage)
                    }
                }
        }
        .backgroundTask(.appRefresh(RecallWatcher.refreshTaskID)) {
            await KeyringApp.refreshRecallsInBackground()
        }
    }

    /// iOS picks the moment; asking for twice a day keeps a new recall within a day or so.
    static func scheduleRecallRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: RecallWatcher.refreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(RecallWatcher.minimumGap)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func refreshRecallsInBackground() async {
        scheduleRecallRefresh()
        await RecallWatcher.check(store: GarageStore.shared)
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
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        return true
    }

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
        // Someone who joined a garage on a fresh install never saw
        // onboarding; leaving it later shouldn't send them there.
        .onChange(of: garage.vehicles.isEmpty) { _, empty in
            if !empty, !hasCompletedSetup { hasCompletedSetup = true }
        }
    }
}

struct MainTabView: View {
    enum Tab: Hashable, CaseIterable {
        case garage, history, settings

        var title: LocalizedStringKey {
            switch self {
            case .garage: "Garage"
            case .history: "History"
            case .settings: "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .garage: "car.fill"
            case .history: "book.closed.fill"
            case .settings: "gearshape.fill"
            }
        }
    }

    @EnvironmentObject private var garage: GarageStore
    @State private var tab: Tab = MainTabView.initialTab
    @ObservedObject private var router = NotificationRouter.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var paneGeometry = PaneGeometry(width: 0, fold: nil)
    @State private var vehiclePane = VehiclePane()

    /// Unfolded, the selected vehicle gets its own pane beside the tabs.
    private var split: UnfoldedSplit? {
        UnfoldedSplit.make(
            width: paneGeometry.width,
            isRegularWidth: horizontalSizeClass == .regular,
            fold: paneGeometry.fold
        )
    }

    /// Each unfolded pane is phone-width, so its screen lays out as on a phone.
    private var paneSizeClass: UserInterfaceSizeClass? {
        split == nil ? horizontalSizeClass : .compact
    }

    var body: some View {
        // One tree for both poses: folding only changes frames, so the tabs keep
        // their navigation and scroll position.
        ZStack(alignment: .topLeading) {
            tabs
                .environment(\.horizontalSizeClass, paneSizeClass)
                .environment(split == nil ? nil : vehiclePane)
                .frame(maxWidth: split?.primaryWidth ?? .infinity, maxHeight: .infinity)

            if let split {
                VehicleDetailPane(pane: vehiclePane)
                    .environment(\.horizontalSizeClass, .compact)
                    .frame(width: split.secondaryWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, split.secondaryX)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .onGeometryChange(for: PaneGeometry.self) { proxy in
            PaneGeometry(width: proxy.size.width, fold: proxy.verticalFold())
        } action: { paneGeometry = $0 }
        .onReceive(router.$destination.compactMap { $0 }) { _ in tab = .garage }
        .sheet(item: Binding(
            get: { router.importFile.map(SharedFile.init(url:)) },
            set: { if $0 == nil { router.importFile = nil } }
        )) { file in ImportView(fileURL: file.url) }
        #if DEBUG
        .task(id: garage.vehicles.count) {
            guard vehiclePane.selectedID == nil, let screen = DuoScreen.current,
                  garage.vehicles.indices.contains(screen.vehicleIndex) else { return }
            vehiclePane.selectedID = garage.vehicles[screen.vehicleIndex].objectID
        }
        #endif
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            page(.garage) { GarageView() }
            page(.history) { NavigationStack { HistoryView() } }
            page(.settings) { NavigationStack { SettingsView() } }
        }
    }

    /// One tab's screen. Unfolded, the system's floating glass bar would let
    /// rows show through it, so the leading pane hides it for an opaque bar of
    /// the same tabs. That bar is a safe-area inset, so every list scrolls its
    /// last row clear of it.
    private func page<Content: View>(_ tab: Tab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .toolbar(split == nil ? .automatic : .hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if split != nil { paneTabBar }
            }
            .tabItem { Label(tab.title, systemImage: tab.systemImage) }
            .tag(tab)
    }

    /// Topped by a short fade, so a card scrolling toward the bar dissolves
    /// into the page instead of being sliced at its edge. The fade is part of
    /// the inset, so the last row still scrolls clear of it.
    private var paneTabBar: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Theme.paper.opacity(0), Theme.paper], startPoint: .top, endPoint: .bottom)
                .frame(height: Theme.lg)
                .allowsHitTesting(false)
            paneTabButtons
        }
    }

    private var paneTabButtons: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { item in
                let isSelected = tab == item
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 3) {
                        // A fixed icon box keeps every label on one baseline.
                        Image(systemName: item.systemImage)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(height: 24)
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? Theme.brass : Theme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, Theme.xs)
        .padding(.top, Theme.xs)
        .padding(.bottom, Theme.xxs)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    static var initialTab: Tab {
        #if DEBUG
        if let screen = DuoScreen.current { return screen.tab }
        #endif
        switch ScreenshotConfig.value(after: "-ScreenshotRoute") {
        case "history": return .history
        case "settings": return .settings
        default: return .garage
        }
    }
}

/// The trailing pane on the unfolded Duo: the vehicle picked in Garage, or the
/// first one until a tag is tapped.
private struct VehicleDetailPane: View {
    let pane: VehiclePane
    @EnvironmentObject private var garage: GarageStore

    var body: some View {
        NavigationStack {
            if let vehicle = pane.vehicle(in: garage.vehicles) {
                VehicleDetailView(vehicle: vehicle)
                    .id(vehicle.objectID)
            } else {
                Color.clear.paperBackground()
            }
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.hairline).frame(width: 1).ignoresSafeArea()
        }
    }
}
