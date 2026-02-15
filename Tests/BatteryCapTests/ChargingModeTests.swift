import XCTest

@testable import BatteryCap

final class ChargingModeTests: XCTestCase {
  func testShouldEnableCharging_NormalMode_ReturnsTrue() {
    XCTAssertTrue(ChargingMode.normal.shouldEnableCharging)
  }

  func testShouldEnableCharging_ChargeLimitMode_ReturnsTrue() {
    XCTAssertTrue(ChargingMode.chargeLimit(80).shouldEnableCharging)
  }

  func testShouldEnableCharging_HoldMode_ReturnsFalse() {
    XCTAssertFalse(ChargingMode.hold(85).shouldEnableCharging)
  }
}
