import XCTest

@testable import BatteryCap

final class BatteryPolicyTests: XCTestCase {
  func testDesiredMode_ControlDisabled_ReturnsNormal() {
    let policy = BatteryPolicy()
    let settings = BatterySettings(isLimitControlEnabled: false, chargeLimit: 80)

    let mode = policy.desiredMode(currentCharge: 90, settings: settings)

    XCTAssertEqual(mode, .normal)
  }

  func testDesiredMode_ChargeBelowLimit_ReturnsChargeLimit() {
    let policy = BatteryPolicy()
    let settings = BatterySettings(isLimitControlEnabled: true, chargeLimit: 80)

    let mode = policy.desiredMode(currentCharge: 60, settings: settings)

    XCTAssertEqual(mode, .chargeLimit(80))
  }

  func testDesiredMode_ChargeAtOrAboveLimit_ReturnsHold() {
    let policy = BatteryPolicy()
    let settings = BatterySettings(isLimitControlEnabled: true, chargeLimit: 80)

    let modeAtLimit = policy.desiredMode(currentCharge: 80, settings: settings)
    let modeAboveLimit = policy.desiredMode(currentCharge: 95, settings: settings)

    XCTAssertEqual(modeAtLimit, .hold(80))
    XCTAssertEqual(modeAboveLimit, .hold(95))
  }
}
