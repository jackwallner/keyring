import XCTest
@testable import Keyring

/// Sharing a saved photo or receipt offers Save Image. Without this key iOS ends the app the moment it is tapped.
final class PhotoSaveUsageTests: XCTestCase {
    func testTheAppSaysWhyItSavesToPhotos() {
        let text = Bundle(for: GarageStore.self).object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") as? String
        XCTAssertFalse(text?.isEmpty ?? true)
    }
}
