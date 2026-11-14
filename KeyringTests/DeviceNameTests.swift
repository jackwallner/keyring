import XCTest
@testable import Keyring

/// The copy names the device. A self-referencing getter once crashed onboarding on launch.
final class DeviceNameTests: XCTestCase {
    func testCurrentIsADeviceName() {
        XCTAssertTrue(["iPhone", "iPad"].contains(DeviceName.current))
    }
}
