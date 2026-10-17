import SwiftUI

/// Every color, spacing and radius in the app. Views never type their own.
///
/// The look is a well-kept logbook: warm paper, deep ink, brass for the
/// things that matter, and each vehicle wearing its own color like a key tag.
enum Theme {
    // MARK: Spacing (4-point scale) and shape

    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 40
    static let margin: CGFloat = 20
    static let radius: CGFloat = 20
    static let smallRadius: CGFloat = 12
    static let cardHeight: CGFloat = 212

    // MARK: Color

    static let paper = Color(light: 0xF4F1EA, dark: 0x12110F)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1D1C19)
    static let raised = Color(light: 0xEDE8DD, dark: 0x282622)
    static let ink = Color(light: 0x1C1B19, dark: 0xF3EFE6)
    static let secondaryInk = Color(light: 0x69655C, dark: 0xA8A397)
    static let faintInk = Color(light: 0x9A958A, dark: 0x6F6B62)
    static let hairline = Color(light: 0xDED8CB, dark: 0x34312C)
    static let brass = Color(light: 0xA9771F, dark: 0xD8A84A)
    static let brassSoft = Color(light: 0xF3E6C8, dark: 0x3A2F1A)

    static let overdue = Color(light: 0xB9381A, dark: 0xF07A55)
    static let dueSoon = Color(light: 0xA86A0C, dark: 0xE8B04B)
    static let good = Color(light: 0x2E6E50, dark: 0x6CC69A)
    static let unknown = Color(light: 0x8A857A, dark: 0x8F8A7F)

    /// The primary button: ink on paper, so a vehicle's color never competes.
    static let action = ink
    static let onAction = Color(light: 0xF8F5EE, dark: 0x16150F)

    // MARK: Type

    /// Serif for names and headlines: the logbook voice.
    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    /// Rounded, fixed-width digits for every meter and money figure.
    static func figure(_ size: CGFloat = 17, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
    static let caption = Font.system(size: 12, weight: .semibold).smallCaps()
}

/// A vehicle's own color. Dark tints carry light text; the two light ones
/// carry ink.
enum VehicleTint: String, CaseIterable, Identifiable, Sendable {
    case racingGreen, navy, oxblood, graphite, marine, sky, plum, olive, orange, sand, silver, cream

    var id: String { rawValue }

    var hex: UInt32 {
        switch self {
        case .racingGreen: 0x1F4D3A
        case .navy: 0x1E3A5F
        case .oxblood: 0x6B1E24
        case .graphite: 0x2E3136
        case .marine: 0x0F5E66
        case .sky: 0x3B76A8
        case .plum: 0x4A2C4F
        case .olive: 0x565D31
        case .orange: 0xC2551A
        case .sand: 0xB69E76
        case .silver: 0x8C939A
        case .cream: 0xE6DCC4
        }
    }

    var color: Color { Color(hex: hex) }

    var isLight: Bool { self == .cream || self == .sand }

    var foreground: Color { isLight ? Color(hex: 0x1C1B19) : Color(hex: 0xF8F5EE) }

    var title: String {
        switch self {
        case .racingGreen: "Racing green"
        case .navy: "Navy"
        case .oxblood: "Oxblood"
        case .graphite: "Graphite"
        case .marine: "Marine"
        case .sky: "Sky"
        case .plum: "Plum"
        case .olive: "Olive"
        case .orange: "Safety orange"
        case .sand: "Sand"
        case .silver: "Silver"
        case .cream: "Cream"
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
        #else
        self.init(hex: light)
        #endif
    }
}
