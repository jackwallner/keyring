import CoreData
import CoreGraphics
import SwiftUI

/// Pane frames for the unfolded iPhone Duo: the tabs on the leading side of the
/// fold, the selected vehicle on the trailing side, so no card straddles the
/// crease. `nil` keeps the single column (every ordinary iPhone, the folded
/// Duo, and the unfolded Duo held in portrait, where each half is too narrow).
struct UnfoldedSplit: Equatable, Sendable {
    var primaryWidth: CGFloat
    var secondaryX: CGFloat
    var secondaryWidth: CGFloat

    /// Narrowest pane that still fits the phone layouts of Garage and a vehicle.
    static let minimumPaneWidth: CGFloat = 360

    /// - Parameters:
    ///   - width: the container's width.
    ///   - fold: the vertical fold's leading and trailing edge in the same
    ///     coordinate space, or `nil` when the system reports none.
    static func make(width: CGFloat, isRegularWidth: Bool, fold: ClosedRange<CGFloat>?) -> UnfoldedSplit? {
        guard isRegularWidth, width >= minimumPaneWidth * 2 else { return nil }
        if let fold,
           fold.lowerBound >= minimumPaneWidth,
           width - fold.upperBound >= minimumPaneWidth {
            return UnfoldedSplit(
                primaryWidth: fold.lowerBound,
                secondaryX: fold.upperBound,
                secondaryWidth: width - fold.upperBound
            )
        }
        let half = (width / 2).rounded(.down)
        return UnfoldedSplit(primaryWidth: half, secondaryX: half, secondaryWidth: width - half)
    }
}

/// What the split is computed from, measured on the root view.
struct PaneGeometry: Equatable, Sendable {
    var width: CGFloat
    var fold: ClosedRange<CGFloat>?
}

extension GeometryProxy {
    /// The vertical fold's horizontal extent in this proxy's space. Inactive
    /// folds count too, so the panes don't jump while the device opens.
    func verticalFold() -> ClosedRange<CGFloat>? {
        guard #available(iOS 27.1, *) else { return nil }
        let fold = reservedRegions(kind: .division, options: .includeInactive)
            .map(\.frame)
            .first { $0.height > $0.width && $0.minX > 0 && $0.maxX < size.width }
        guard let fold else { return nil }
        return fold.minX...fold.maxX
    }
}

/// Which vehicle the unfolded Duo's trailing pane shows. In the environment
/// only while split, which is how Garage knows to select rather than push.
@MainActor @Observable
final class VehiclePane {
    var selectedID: NSManagedObjectID?

    func select(_ vehicle: Vehicle) {
        guard selectedID != vehicle.objectID else { return }
        selectedID = vehicle.objectID
        Haptics.selected()
    }

    /// The picked vehicle, else the first one in the garage.
    func vehicle(in vehicles: [Vehicle]) -> Vehicle? {
        vehicles.first { $0.objectID == selectedID } ?? vehicles.first
    }
}
