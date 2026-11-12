import UIKit

/// "iPhone" or "iPad", for the copy that names the device the app is on.
enum DeviceName {
    static var current: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "\(DeviceName.current)"
    }
}
