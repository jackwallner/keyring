import SafariServices
import SwiftUI
import UIKit

// MARK: - Buttons

/// Ink on paper. One per screen, for the thing the screen is for.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.onAction)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.action.opacity(isEnabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(configuration.role == .destructive ? Theme.overdue : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Cards that respond to a press without looking like buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

// MARK: - Surfaces

extension View {
    /// The standard white card on paper.
    func card(padding: CGFloat = Theme.md) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }

    /// Paper behind a whole screen, including under lists.
    func paperBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.paper.ignoresSafeArea())
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?
    var action: (() -> Void)?

    var body: some View {
        // The action drops under the title when both won't fit on one line.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                heading.lineLimit(1)
                Spacer()
                button.lineLimit(1)
            }
            VStack(alignment: .leading, spacing: Theme.xs) {
                heading
                button
            }
        }
        .padding(.top, Theme.xs)
    }

    private var heading: some View {
        Text(title)
            .font(Theme.title(20))
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var button: some View {
        if let trailing, let action {
            Button(trailing, action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.brass)
        }
    }
}

/// The small-caps label above a group: "ON THE ROAD".
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.secondaryInk

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(color)
    }
}

// MARK: - Status

extension DueStatus {
    var color: Color {
        switch self {
        case .overdue: Theme.overdue
        case .dueSoon: Theme.dueSoon
        case .noRecord: Theme.unknown
        case .ok: Theme.good
        }
    }

    var symbol: String {
        switch self {
        case .overdue: "exclamationmark.circle.fill"
        case .dueSoon: "clock.fill"
        case .noRecord: "questionmark.circle"
        case .ok: "checkmark.circle.fill"
        }
    }
}

extension TaskDue {
    /// "Due in 3 weeks", "Overdue by 400 mi", "Due around Mar 12", on the
    /// meter this job counts.
    func dueLine(now: Date = .now, notingPace: Bool = true) -> String {
        let meter = self.meter
        let current = currentReading
        switch result.status {
        case .noRecord:
            return "When was it last done?"
        case .overdue:
            if let reading = result.dueReading, meter.hasReading, current >= reading {
                return "Overdue by \(Format.reading(current - reading, meter))"
            }
            if let date = result.dueDate { return "Overdue since \(Format.shortDate(date))" }
            return "Overdue"
        case .dueSoon, .ok:
            guard let date = result.dueDate else {
                if let reading = result.dueReading { return "Due at \(Format.reading(reading, meter))" }
                return "Up to date"
            }
            let when = Format.relative(date, now: now)
            return result.dateIsEstimated && notingPace ? "Due \(when), by your pace" : "Due \(when)"
        }
    }
}

struct StatusDot: View {
    let status: DueStatus
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(status.color).frame(width: size, height: size)
    }
}

/// A slim bar showing how much of the interval is used.
struct DueBar: View {
    let progress: Double
    let status: DueStatus

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(status.color)
                    .frame(width: max(4, geometry.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Vehicle art

/// A vehicle's picture: its photo when there is one, otherwise its kind's
/// silhouette on its own color.
struct VehicleArt: View {
    let vehicle: Vehicle
    var cornerRadius: CGFloat = Theme.smallRadius
    var symbolScale: CGFloat = 0.42

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                vehicle.tint.color
                if let data = vehicle.photo, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Image(systemName: vehicle.kind.symbol)
                        .font(.system(size: min(geometry.size.width, geometry.size.height) * symbolScale, weight: .regular))
                        .foregroundStyle(vehicle.tint.foreground.opacity(0.85))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Empty and info states

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.sm) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Theme.brass)
                .padding(.bottom, Theme.xxs)
                .accessibilityHidden(true)
            Text(title)
                .accessibilityAddTraits(.isHeader)
                .font(Theme.title(20))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, Theme.xs)
            }
        }
        .padding(Theme.xl)
        .frame(maxWidth: .infinity)
    }
}

/// A row that opens an outside link, with the destination's domain shown so
/// nobody is surprised where they land.
struct LinkRow: View {
    let title: String
    var detail: String?
    var symbol: String?
    let url: URL

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            Haptics.tap()
            openURL(url)
        } label: {
            HStack(spacing: Theme.sm) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.body)
                        .foregroundStyle(Theme.brass)
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: Theme.xs)
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.faintInk)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(url.host() ?? "the web")")
    }
}

// MARK: - Sharing

/// The system share sheet, for a PDF, a spreadsheet or an invite link.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// A file the share sheet hands around, made identifiable for `.sheet(item:)`.
struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Haptics

@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func selected() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Number fields

/// A text field bound to a number, which keeps what the person typed until
/// they leave it, so "12," mid-typing isn't snapped back. The number pad has
/// no return key, so a focused field adds Done above the keyboard.
struct NumberField: View {
    let title: String
    @Binding var value: Double?
    var suffix: String = ""
    var allowsDecimal = false
    /// Money: the currency symbol leads and cents show as two digits.
    var isCurrency = false
    /// Off for years, which never take a thousands separator.
    var grouping = true

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(isCurrency ? Self.symbol + title : title, text: $text)
                .keyboardType(allowsDecimal || isCurrency ? .decimalPad : .numberPad)
                .focused($focused)
                .font(Theme.figure(17, weight: .regular))
                .onChange(of: text) { _, newValue in
                    value = Self.parse(newValue)
                }
            if !suffix.isEmpty {
                Text(suffix).foregroundStyle(Theme.secondaryInk)
            }
        }
        .onAppear { text = Self.display(value, allowsDecimal: allowsDecimal, isCurrency: isCurrency, grouping: grouping) }
        .onChange(of: value) { _, newValue in
            guard !focused else { return }
            text = Self.display(newValue, allowsDecimal: allowsDecimal, isCurrency: isCurrency, grouping: grouping)
        }
        .onChange(of: focused) { _, isFocused in
            guard !isFocused else { return }
            text = Self.display(value, allowsDecimal: allowsDecimal, isCurrency: isCurrency, grouping: grouping)
        }
        .toolbar {
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: Locale.current.groupingSeparator ?? ",", with: "")
            .replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
            .filter { $0.isNumber || $0 == "." }
        return Double(cleaned)
    }

    private static var symbol: String { Locale.current.currencySymbol ?? "$" }

    /// Grouped and, for money, led by the symbol; `parse` strips both back out.
    static func display(_ value: Double?, allowsDecimal: Bool, isCurrency: Bool = false, grouping: Bool = true) -> String {
        guard let value else { return "" }
        if isCurrency {
            let digits = value == value.rounded()
                ? Int(value).formatted()
                : value.formatted(.number.precision(.fractionLength(2)))
            return symbol + digits
        }
        if allowsDecimal, value != value.rounded() {
            return value.formatted(.number.precision(.fractionLength(0...2)).grouping(grouping ? .automatic : .never))
        }
        return Int(value.rounded()).formatted(.number.grouping(grouping ? .automatic : .never))
    }
}

// MARK: - Sheets sized to their form

/// A short form in a medium sheet leaves half the sheet blank, so the sheet
/// opens at the form's own height instead. Apply it to the Form inside the
/// sheet. iOS 17 can't read the form's height and falls back to medium.
struct FittedSheet: ViewModifier {
    var expandable: Bool
    @State private var fitted: CGFloat = 0
    @State private var selection: PresentationDetent = .medium
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.presentationDetents([.large])
        } else if #available(iOS 18, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                } action: { _, height in
                    fit(height)
                }
                .presentationDetents(detents, selection: $selection)
        } else {
            content.presentationDetents(expandable ? [.medium, .large] : [.medium])
        }
    }

    private var detents: Set<PresentationDetent> {
        var set: Set<PresentationDetent> = [fitted > 0 ? .height(fitted) : .medium]
        if expandable { set.insert(.large) }
        return set
    }

    private func fit(_ height: CGFloat) {
        let rounded = height.rounded(.up)
        guard rounded > 0, abs(rounded - fitted) > 1 else { return }
        let wasFitted = selection != .large
        fitted = rounded
        if wasFitted { selection = .height(rounded) }
    }
}

extension View {
    /// Opens the sheet at the height of its form. `expandable` adds a full-height detent.
    func fittedSheet(expandable: Bool = false) -> some View {
        modifier(FittedSheet(expandable: expandable))
    }
}
