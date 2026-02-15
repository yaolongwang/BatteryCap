import XCTest

@testable import BatteryCap

final class BatteryConstantsTests: XCTestCase {
  func testClampChargeLimit_BelowMinimum_ReturnsMinimum() {
    XCTAssertEqual(BatteryConstants.clampChargeLimit(-1), BatteryConstants.minChargeLimit)
  }

  func testClampChargeLimit_AboveMaximum_ReturnsMaximum() {
    XCTAssertEqual(BatteryConstants.clampChargeLimit(999), BatteryConstants.maxChargeLimit)
  }

  func testChargeLimitSliderRange_UsesConfiguredBounds() {
    XCTAssertEqual(BatteryConstants.chargeLimitSliderRange.lowerBound, Double(BatteryConstants.minChargeLimit))
    XCTAssertEqual(BatteryConstants.chargeLimitSliderRange.upperBound, Double(BatteryConstants.maxChargeLimit))
  }
}
