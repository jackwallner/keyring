import Foundation
#if targetEnvironment(simulator)
import MachO
#endif

/// Whether this build may open the iCloud container. Device builds always
/// carry the entitlement. A simulator build made without signing (gh-sim's
/// GitHub runs) has none, and CloudKit traps the moment it is touched, so the
/// app runs local-only there instead of crashing at launch.
enum CloudKitEntitlement {
    static let isPresent: Bool = {
        #if targetEnvironment(simulator)
        // Signed simulator builds embed their entitlements in the executable.
        guard let header = _dyld_get_image_header(0) else { return false }
        var size: UInt = 0
        let image = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
        guard let bytes = getsectiondata(image, "__TEXT", "__entitlements", &size), size > 0 else { return false }
        let plist = String(decoding: UnsafeBufferPointer(start: bytes, count: Int(size)), as: UTF8.self)
        return plist.contains(AppGroup.cloudKitContainerID)
        #else
        return true
        #endif
    }()
}
