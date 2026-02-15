import XCTest

@testable import BatteryCap

final class BatteryPolicyTests: XCTestCase {
  func testDesiredMode_ControlDisabled_ReturnsNormal() {
    let policy = BatteryPolicy()
    let mode = policy.desiredMode(currentCharge: 90, settings: settings(enabled: false, limit: 80), lastAppliedMode: nil)
    XCTAssertEqual(mode, .normal)
  }

  func testDesiredMode_ControlEnabledBelowUpperThreshold_ReturnsChargeLimit() {
    let policy = BatteryPolicy(hysteresisPercent: 1)
    let mode = policy.desiredMode(currentCharge: 80, settings: settings(enabled: true, limit: 80), lastAppliedMode: nil)
    XCTAssertEqual(mode, .chargeLimit(80))
  }

  func testDesiredMode_ControlEnabledAtUpperThreshold_ReturnsHold() {
    let policy = BatteryPolicy(hysteresisPercent: 1)
    let mode = policy.desiredMode(currentCharge: 81, settings: settings(enabled: true, limit: 80), lastAppliedMode: nil)
    XCTAssertEqual(mode, .hold(81))
  }

  func testDesiredMode_LastModeHoldAboveLowerThreshold_RemainsHold() {
    let policy = BatteryPolicy(hysteresisPercent: 1)
    let mode = policy.desiredMode(currentCharge: 80, settings: settings(enabled: true, limit: 80), lastAppliedMode: .hold(90))
    XCTAssertEqual(mode, .hold(80))
  }

  func testDesiredMode_LastModeHoldAtLowerThreshold_SwitchesToChargeLimit() {
    let policy = BatteryPolicy(hysteresisPercent: 1)
    let mode = policy.desiredMode(currentCharge: 79, settings: settings(enabled: true, limit: 80), lastAppliedMode: .hold(90))
    XCTAssertEqual(mode, .chargeLimit(80))
  }

  func testDesiredMode_ChargeLimitBelowMinimum_ClampsToMinLimit() {
    let policy = BatteryPolicy(hysteresisPercent: 1)
    let mode = policy.desiredMode(currentCharge: 40, settings: settings(enabled: true, limit: 20), lastAppliedMode: nil)
    XCTAssertEqual(mode, .chargeLimit(BatteryConstants.minChargeLimit))
  }

  func testDesiredMode_ChargeLimitAboveMaximum_ClampsToMaxLimit() {
    let policy = BatteryPolicy(hysteresisPercent: 1)
    let mode = policy.desiredMode(currentCharge: 99, settings: settings(enabled: true, limit: 120), lastAppliedMode: nil)
    XCTAssertEqual(mode, .chargeLimit(BatteryConstants.maxChargeLimit))
  }

  private func settings(enabled: Bool, limit: Int) -> BatterySettings {
    BatterySettings(
      isLimitControlEnabled: enabled,
      chargeLimit: limit,
      keepStateOnQuit: false,
      launchAtLoginEnabled: false
    )
  }
}
