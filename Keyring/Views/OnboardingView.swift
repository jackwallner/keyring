import RevenueCat
import SwiftUI

/// Four pages: what Keyring is, how it knows what's due, logging together,
/// and the Pro trial. The bottom bar keeps one geometry on every page, so
/// the main button never moves under a thumb.
struct OnboardingView: View {
    @EnvironmentObject private var garage: GarageStore
    @EnvironmentObject private var store: StoreService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(AppGroup.Key.hasCompletedSetup, store: AppGroup.defaults) private var hasCompletedSetup = false

    @State private var page = 0
    @State private var name = ""
    @State private var purchasing = false
    @State private var restoring = false
    @State private var errorText: String?
    @State private var joining = false
    @State private var showingPaywall = false
    @FocusState private var nameFocused: Bool

    private let lastPage = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                schedule.tag(1)
                family.tag(2)
                trial.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)
            .animation(.snappy, value: nameFocused)
            // The tall footer would squeeze the name field under the keyboard.
            if !nameFocused { footer }
        }
        .background(Theme.paper.ignoresSafeArea())
        .sheet(isPresented: $joining) { JoinGarageView() }
        .sheet(isPresented: $showingPaywall, onDismiss: { if store.isPro { finish() } }) { PaywallView(focus: .unlimitedVehicles) }
        .task {
            store.trackPaywallImpression(id: "keyring_onboarding", oncePerSession: true)
            if store.packages.isEmpty { store.start() }
        }
    }

    // MARK: - Pages

    private func pageLayout<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                content()
            }
            .padding(.horizontal, Theme.xl)
            .padding(.top, Theme.xxl)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var welcome: some View {
        pageLayout {
            KeyringStack()
                .frame(height: 230)
                .frame(maxWidth: .infinity)
            Text("Every vehicle,\none keyring")
                .font(Theme.title(36))
                .foregroundStyle(Theme.ink)
            Text("Cars, trucks, boats, bikes, RVs, planes and the mower. What's due, what was done, and every receipt, for the whole family.")
                .font(.body)
                .foregroundStyle(Theme.secondaryInk)
            Button("Joining someone's garage?") { joining = true }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("onboarding.join")
        }
    }

    private var schedule: some View {
        pageLayout {
            VStack(spacing: 0) {
                sampleRow("drop.fill", "Oil and filter", "Due in 3 weeks, by your pace", .dueSoon)
                Divider().overlay(Theme.hairline)
                sampleRow("arrow.triangle.2.circlepath", "Tire rotation", "Due in 3 weeks, by your pace", .dueSoon)
                Divider().overlay(Theme.hairline)
                sampleRow("gearshape.2.fill", "Impeller", "Due at 250 hrs", .ok)
                Divider().overlay(Theme.hairline)
                sampleRow("airplane", "Annual inspection", "Due in 5 months", .ok)
            }
            .card(padding: Theme.xs)
            Text("It knows\nwhat's due")
                .font(Theme.title(36))
                .foregroundStyle(Theme.ink)
            Text("Pick the kind of vehicle and Keyring builds its schedule: miles for the truck, engine hours for the boat. It learns how much you drive and reminds you a week ahead.")
                .font(.body)
                .foregroundStyle(Theme.secondaryInk)
        }
    }

    private var family: some View {
        pageLayout {
            if !nameFocused, !dynamicTypeSize.isAccessibilitySize {
            HStack(spacing: -12) {
                ForEach(Array(["J", "S", "M"].enumerated()), id: \.offset) { index, initial in
                    Text(initial)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background([VehicleTint.racingGreen, .sky, .oxblood][index].color, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.paper, lineWidth: 3))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.lg)
            }
            Text("Log it together")
                .font(Theme.title(36))
                .foregroundStyle(Theme.ink)
            Text("Share the garage with one code. Whoever takes the car in logs it from their own iPhone, and everyone sees who did what.")
                .font(.body)
                .foregroundStyle(Theme.secondaryInk)
            VStack(alignment: .leading, spacing: Theme.xs) {
                Eyebrow(text: "Your name on entries")
                TextField("First name", text: $name)
                    .focused($nameFocused)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .padding(Theme.sm)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
                    .accessibilityIdentifier("onboarding.name")
            }
        }
    }

    private var trial: some View {
        pageLayout {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.brass)
                .frame(width: 84, height: 84)
                .background(Theme.brassSoft, in: Circle())
                .frame(maxWidth: .infinity)
            Text(store.isPro ? "Keyring Pro is on your account" : trialTitle)
                .font(Theme.title(32))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: Theme.sm) {
                benefit("Your first two vehicles are free, forever")
                benefit("Pro adds every vehicle you own")
                benefit("Service Record PDF for buyers and shops")
                benefit("Receipts fill in the total, date and shop")
                benefit("Spending by vehicle, job and month")
            }
            if dynamicTypeSize.isAccessibilitySize, !store.isPro {
                Text(disclosure)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                softExit.frame(maxWidth: .infinity)
                legalRow
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(Theme.overdue)
            }
        }
    }

    private var trialCTA: String {
        if store.isPro { return "Continue" }
        if let package = onboardingPackage, store.isEligibleForIntroOffer(package) { return "Start free trial" }
        return "Continue with Keyring Pro"
    }

    private var trialTitle: String {
        if let package = onboardingPackage, store.isEligibleForIntroOffer(package) { return "Try Keyring Pro free for a week" }
        return "Keyring Pro"
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
            Text(text).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sampleRow(_ symbol: String, _ title: String, _ detail: String, _ status: DueStatus) -> some View {
        HStack(spacing: Theme.sm) {
            Image(systemName: symbol)
                .foregroundStyle(status.color)
                .frame(width: 32, height: 32)
                .background(status.color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(detail).font(.footnote).foregroundStyle(Theme.secondaryInk)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Theme.xs)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer (same geometry on every page)

    private var onTrialPage: Bool { page == lastPage }

    private var footer: some View {
        let reserves = !dynamicTypeSize.isAccessibilitySize
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0...lastPage, id: \.self) { dot in
                    Capsule()
                        .fill(dot == page ? Theme.ink : Theme.ink.opacity(0.18))
                        .frame(width: dot == page ? 20 : 7, height: 7)
                }
            }
            .animation(.snappy(duration: 0.22), value: page)
            .padding(.bottom, 2)
            .accessibilityHidden(true)
            if reserves {
                softExit
                    .opacity(onTrialPage && !store.isPro ? 1 : 0)
                    .accessibilityHidden(!onTrialPage || store.isPro)
                priceSlot
                    .opacity(onTrialPage ? 1 : 0)
                    .accessibilityHidden(!onTrialPage || store.isPro)
            } else if onTrialPage, !store.isPro {
                // The billed amount stays beside the button at every text size.
                billedAmount
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            }
            Button(action: primary) {
                Group {
                    if purchasing || restoring {
                        ProgressView().tint(Theme.onAction)
                    } else {
                        Text(onTrialPage ? trialCTA : "Continue")
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(purchasing || restoring)
            .accessibilityIdentifier("onboarding.continue")
            if reserves {
                legalRow
                    .opacity(onTrialPage && !store.isPro ? 1 : 0)
                    .accessibilityHidden(!onTrialPage || store.isPro)
            }
        }
        .padding(.horizontal, Theme.lg)
        .padding(.bottom, 10)
    }

    /// The free way in, worded as a start rather than an escape.
    private var softExit: some View {
        Button("Get Started", action: finish)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.secondaryInk)
            .frame(height: 30)
            .disabled(!onTrialPage || store.isPro || purchasing || restoring)
            .accessibilityIdentifier("onboarding.getStarted")
    }

    /// The billed amount leads every other pricing element (App Review
    /// 3.1.2(c)); the terms under it stay small.
    private var priceSlot: some View {
        VStack(spacing: 2) {
            billedAmount
            Text(store.isPro ? "" : disclosure)
                .font(.caption2)
                .foregroundStyle(Theme.faintInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 48)
    }

    private var billedAmount: some View {
        Text(store.isPro ? "" : onboardingPackage.map { ConversionCopy.billedAmount(priceLabel: $0.priceLabel) } ?? "")
            .font(Theme.figure(22, weight: .bold))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("onboarding.billedAmount")
    }

    private var disclosure: String {
        guard let package = onboardingPackage else { return "" }
        if store.isEligibleForIntroOffer(package), let trial = package.introOfferLabel {
            return "\(trial.capitalizedFirst), then \(package.priceLabel). Renews until cancelled; cancel anytime in Settings at least 24 hours before it renews."
        }
        return "\(package.priceLabel). Renews until cancelled; cancel anytime in Settings at least 24 hours before it renews."
    }

    private var legalRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.sm))
            : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            Link("Terms", destination: AppLinks.standardEULA)
            Link("Privacy", destination: AppLinks.privacyPolicy)
            Button("Restore", action: restore)
        }
        .frame(maxWidth: .infinity)
        .font(.caption2)
        .foregroundStyle(Theme.faintInk)
        .frame(minHeight: 20)
        .disabled(!onTrialPage || store.isPro || purchasing || restoring)
    }

    /// Monthly: someone who hasn't used the app yet reacts to the number on
    /// Apple's sheet, and the smaller one starts more trials (Mahj's proven
    /// page). The paywall later leads with yearly.
    private var onboardingPackage: Package? {
        store.packages.first { $0.planKind == .monthly } ?? store.yearlyPackage
    }

    // MARK: - Actions

    private func primary() {
        if page == 2 { garage.setOwnerName(name) }
        guard onTrialPage else {
            withAnimation(.snappy) { page += 1 }
            return
        }
        guard !store.isPro else { finish(); return }
        guard let package = onboardingPackage else {
            showingPaywall = true
            return
        }
        purchasing = true
        errorText = nil
        Task {
            defer { purchasing = false }
            let outcome = await store.purchase(package)
            switch outcome {
            case .purchased: finish()
            case .pending: errorText = ConversionCopy.purchasePendingMessage
            case .cancelled: break
            case nil:
                // RevenueCat isn't running (a simulator) or the purchase
                // failed; the full paywall shows plans and the reason.
                if store.errorMessage == nil { showingPaywall = true }
            }
        }
    }

    private func restore() {
        restoring = true
        Task {
            await store.restore()
            restoring = false
            if store.isPro { finish() } else { errorText = store.errorMessage }
        }
    }

    private func finish() {
        if !name.trimmed.isEmpty { garage.setOwnerName(name) }
        garage.ensureOwnGarage()
        // The garage opens straight into adding the first vehicle.
        AppGroup.defaults.set(true, forKey: AppGroup.Key.pendingFirstVehicle)
        hasCompletedSetup = true
    }
}

/// Three key tags fanned on a ring: the welcome picture.
struct KeyringStack: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.brass, lineWidth: 5)
                .frame(width: 70, height: 70)
                .offset(y: -78)
            ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                tagView(tag)
                    .rotationEffect(.degrees(Double(index - 1) * 16), anchor: .top)
                    .offset(y: 10)
            }
        }
        // Artwork, sized like a picture rather than text.
        .dynamicTypeSize(.large)
        .accessibilityHidden(true)
    }

    private let tags: [(VehicleTint, String, String)] = [
        (.marine, "ferry.fill", "Lake boat"),
        (.racingGreen, "truck.pickup.side.fill", "Tacoma"),
        (.oxblood, "motorcycle.fill", "Rebel"),
    ]

    private func tagView(_ tag: (VehicleTint, String, String)) -> some View {
        VStack(spacing: 8) {
            Circle().fill(Theme.paper).frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(tag.0.foreground.opacity(0.4), lineWidth: 1.5).padding(-4))
            Image(systemName: tag.1).font(.system(size: 30)).foregroundStyle(tag.0.foreground.opacity(0.9))
            Text(tag.2).font(Theme.title(15)).foregroundStyle(tag.0.foreground)
        }
        .frame(width: 104, height: 150)
        .background(tag.0.color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
