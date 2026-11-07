import RevenueCat
import XCTest
@testable import Keyring

/// RevenueCat throws `paymentPendingError` for Ask to Buy and bank
/// confirmation; that purchase is waiting, not failed.
final class PurchaseErrorTests: XCTestCase {
    func testAPendingPaymentIsNotAFailure() {
        XCTAssertEqual(StoreService.state(forPurchaseError: ErrorCode.paymentPendingError), .pending)
    }

    func testACancelIsACancel() {
        XCTAssertEqual(StoreService.state(forPurchaseError: ErrorCode.purchaseCancelledError), .cancelled)
    }

    func testOtherErrorsFail() {
        XCTAssertNil(StoreService.state(forPurchaseError: ErrorCode.networkError))
        XCTAssertNil(StoreService.state(forPurchaseError: ErrorCode.storeProblemError))
    }
}
