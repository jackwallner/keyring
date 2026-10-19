import RevenueCat
import StoreKit
import SwiftUI

/// What Keyring Pro adds. One enum drives the paywall bullets and every
/// locked surface, so they can't drift. Nothing here may be something that
/// ships free: logging, reminders, recalls, sharing and CSV export stay free.
enum ProFeature: String, CaseIterable, Identifiable {
    case unlimitedVehicles, serviceRecord, receiptScan, insights

    static let freeVehicleLimit = 2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlimitedVehicles: "Every vehicle you own"
        case .serviceRecord: "Service Record PDF"
        case .receiptScan: "Receipts fill themselves in"
        case .insights: "Where the money goes"
        }
    }

    var detail: String {
        switch self {
        case .unlimitedVehicles: "Your first two are free forever. Pro adds the boat, the bikes, the RV and the mower."
        case .serviceRecord: "Every job, receipt and reading on clean pages. Print it for the glovebox or send it to a buyer."
        case .receiptScan: "Snap a receipt or the pump and the total, date, shop and gallons are read on your iPhone."
        case .insights: "Spending by month, by vehicle and by job, and your real cost per mile."
        }
    }

    var symbol: String {
        switch self {
        case .unlimitedVehicles: "car.2.fill"
        case .serviceRecord: "doc.richtext.fill"
        case .receiptScan: "doc.viewfinder.fill"
        case .insights: "chart.bar.fill"
        }
    }

    var headline: String {
        switch self {
        case .unlimitedVehicles: "Room for the\nwhole garage"
        case .serviceRecord: "A service record\nthat sells the car"
        case .receiptScan: "Snap the receipt,\nskip the typing"
        case .insights: "See where the\nmoney goes"
        }
    }
}

/// The Keyring Pro purchase surface. Apple 3.1.2 needs the price, period,
/// renewal terms, restore, and the Privacy Policy and EULA at the point of
/// purchase, so the footer renders in every state.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreService

    var displayCloseButton = true
    var focus: ProFeature?
    var requestedPlan: String?

    @State private var selected: Package?
    @State private var restoring = false
    @State private var message: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if store.isPro {
                    subscriber
                } else if store.packages.isEmpty && store.isLoadingProducts {
                    VStack(spacing: Theme.md) {
                        Spacer()
                        ProgressView()
                        Text("Loading plans").font(.subheadline).foregroundStyle(Theme.secondaryInk)
                        Spacer()
                        legalFooter
                    }
                    .padding(Theme.margin)
                } else if store.packages.isEmpty {
                    VStack(spacing: Theme.md) {
                        Spacer()
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(Theme.secondaryInk)
                        Text("Couldn't load plans").font(.headline)
                        Text(store.errorMessage ?? "Check your connection and try again.")
                            .font(.subheadline).foregroundStyle(Theme.secondaryInk).multilineTextAlignment(.center)
                        Button("Try again") { store.start(forceRefresh: true) }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        Spacer()
                        legalFooter
                    }
                    .padding(Theme.margin)
                } else {
                    content
                }
            }
            if displayCloseButton {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .padding(Theme.xs)
                .accessibilityLabel("Close")
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .task {
            store.trackPaywallImpression(id: "keyring_paywall_\(focus?.rawValue ?? "settings")")
            if store.packages.isEmpty { store.start() }
            selectDefault()
        }
        .onChange(of: store.packages.count) { _, _ in selectDefault() }
        .onChange(of: store.isPro) { _, isPro in if isPro && displayCloseButton { dismiss() } }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: Theme.lg) {
                VStack(spacing: Theme.xs) {
                    Eyebrow(text: "Vehicle Maintenance Log Pro", color: Theme.brass)
                    Text(focus?.headline ?? "Keep every vehicle\nin one place")
                        .font(Theme.title(30))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, displayCloseButton ? 44 : Theme.lg)

                VStack(alignment: .leading, spacing: Theme.md) {
                    ForEach(orderedFeatures) { feature in
                        HStack(alignment: .top, spacing: Theme.sm) {
                            Image(systemName: feature.symbol)
                                .font(.body)
                                .foregroundStyle(Theme.brass)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                Text(feature.detail).font(.footnote).foregroundStyle(Theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .card()

                VStack(spacing: Theme.stackGap) {
                    ForEach(store.packages, id: \.identifier) { package in
                        PlanCard(
                            package: package,
                            isSelected: selected?.identifier == package.identifier,
                            trialLabel: store.eligibleIntroLabel(for: package),
                            perMonth: perMonth(package),
                            savings: savings(package)
                        ) {
                            Haptics.selected()
                            selected = package
                        }
                    }
                }

                checkout
                legalFooter
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.md)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var orderedFeatures: [ProFeature] {
        guard let focus else { return ProFeature.allCases }
        return [focus] + ProFeature.allCases.filter { $0 != focus }
    }

    private var checkout: some View {
        VStack(spacing: Theme.xs) {
            if let selected {
                Text(ConversionCopy.billedAmount(priceLabel: selected.priceLabel))
                    .font(Theme.figure(22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("paywall.billedAmount")
                Text(selected.planKind == .lifetime
                     ? "One payment · Never renews"
                     : ConversionCopy.billedNote(trialLabel: selected.introOfferLabel, eligibleForTrial: store.isEligibleForIntroOffer(selected)))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            Button {
                guard let selected else { return }
                message = nil
                Task {
                    if await store.purchase(selected) == .pending { message = ConversionCopy.purchasePendingMessage }
                }
            } label: {
                if store.isLoading {
                    ProgressView().tint(Theme.onAction)
                } else {
                    Text(ConversionCopy.ctaLabel(trialLabel: nil, priceLabel: "", eligibleForTrial: false))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selected == nil || store.isLoading)
            .accessibilityIdentifier("paywall.purchase")
            Text(disclosure)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(Theme.overdue).multilineTextAlignment(.center)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(Theme.secondaryInk).multilineTextAlignment(.center)
            }
        }
    }

    private var disclosure: String {
        guard let selected else { return "Subscriptions renew automatically until cancelled." }
        if selected.planKind == .lifetime {
            return "\(selected.priceLabel). One-time purchase. Nothing renews."
        }
        return ConversionCopy.disclosure(
            trialLabel: selected.introOfferLabel,
            priceLabel: selected.priceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(selected)
        )
    }

    private var legalFooter: some View {
        VStack(spacing: 2) {
            Button {
                restoring = true
                message = nil
                Task {
                    await store.restore()
                    restoring = false
                    if !store.isPro { message = store.errorMessage }
                }
            } label: {
                Text(restoring ? "Restoring…" : "Restore purchases")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(minHeight: 44)
            }
            .disabled(restoring || store.isLoading)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.sm) {
                    Link("Terms of Use", destination: AppLinks.standardEULA)
                    Text("·").accessibilityHidden(true)
                    Link("Privacy Policy", destination: AppLinks.privacyPolicy)
                }
                VStack(spacing: Theme.sm) {
                    Link("Terms of Use", destination: AppLinks.standardEULA)
                    Link("Privacy Policy", destination: AppLinks.privacyPolicy)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.secondaryInk)
        }
    }

    private var subscriber: some View {
        ScrollView {
            VStack(spacing: Theme.lg) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(Theme.brass)
                    .padding(.top, 60)
                Text("Pro is on").font(Theme.title(30))
                Text("Unlimited vehicles, the Service Record, receipt reading and insights, on every device signed in to this Apple Account.")
                    .font(.subheadline).foregroundStyle(Theme.secondaryInk).multilineTextAlignment(.center)
                Link(destination: AppLinks.manageSubscriptions) {
                    Text("Manage subscription").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                legalFooter
            }
            .padding(.horizontal, Theme.margin)
        }
    }

    private func selectDefault() {
        guard selected == nil, !store.packages.isEmpty else { return }
        let requested: PlanKind? = switch requestedPlan {
        case "monthly": .monthly
        case "lifetime": .lifetime
        case "yearly": .yearly
        default: nil
        }
        if let requested, let match = store.packages.first(where: { $0.planKind == requested }) {
            selected = match
        } else {
            selected = store.yearlyPackage ?? store.packages.first
        }
    }

    private func perMonth(_ package: Package) -> String? {
        guard package.planKind == .yearly else { return nil }
        let monthly = (package.storeProduct.price as NSDecimalNumber).dividing(by: 12, withBehavior: NSDecimalNumberHandler(roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false))
        let formatter = package.storeProduct.priceFormatter ?? {
            let value = NumberFormatter()
            value.numberStyle = .currency
            return value
        }()
        return formatter.string(from: monthly).map { "\($0) / mo" }
    }

    private func savings(_ package: Package) -> Int? {
        guard package.planKind == .yearly, let monthly = store.packages.first(where: { $0.planKind == .monthly }) else { return nil }
        let yearly = (package.storeProduct.price as NSDecimalNumber).doubleValue
        let atMonthly = (monthly.storeProduct.price as NSDecimalNumber).doubleValue * 12
        guard atMonthly > yearly, yearly > 0 else { return nil }
        return Int(((atMonthly - yearly) / atMonthly * 100).rounded(.down))
    }
}

private struct PlanCard: View {
    let package: Package
    let isSelected: Bool
    let trialLabel: String?
    let perMonth: String?
    let savings: Int?
    let tap: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: tap) {
            HStack(spacing: Theme.sm) {
                ZStack {
                    Circle().strokeBorder(isSelected ? Theme.ink : Theme.faintInk, lineWidth: 2).frame(width: 22, height: 22)
                    if isSelected { Circle().fill(Theme.ink).frame(width: 12, height: 12) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.xs) { nameAndBadge }
                        VStack(alignment: .leading, spacing: 2) { nameAndBadge }
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(package.priceLabel).font(Theme.figure(15)).foregroundStyle(Theme.ink)
                    }
                    if !secondaryParts.isEmpty {
                        // One line with a dot when it fits; stacked, without the dot, when it doesn't.
                        ViewThatFits(in: .horizontal) {
                            Text(secondaryParts.joined(separator: " · ")).lineLimit(1)
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(secondaryParts, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                    }
                }
                Spacer(minLength: Theme.xs)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(package.priceLabel).font(Theme.figure(15)).foregroundStyle(Theme.ink)
                }
            }
            .padding(.horizontal, Theme.md)
            .padding(.vertical, Theme.sm)
            .frame(minHeight: 60)
            .background(isSelected ? Theme.brassSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isSelected ? Theme.brass : Theme.hairline, lineWidth: isSelected ? 1.5 : 0.5))
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder private var nameAndBadge: some View {
        Text(package.planName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
        if let savings {
            badge("SAVE \(savings)%")
        } else if package.planKind == .lifetime {
            badge("PAY ONCE")
        }
    }

    private var secondaryParts: [String] {
        let parts = [trialLabel, perMonth].compactMap { $0 }
        if parts.isEmpty, package.planKind == .lifetime { return ["One-time purchase"] }
        return parts
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.onAction)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.brass, in: Capsule())
    }
}
