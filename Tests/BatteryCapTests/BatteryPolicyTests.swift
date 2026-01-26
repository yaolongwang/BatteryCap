import XCTest
@testable import BatteryCap

final class BatteryPolicyTests: XCTestCase {
    func testDesiredMode_ControlDisabled_ReturnsNormal() {
        let policy = BatteryPolicy()
        let settings = BatterySettings(isLimitControlEnabled: false, chargeLimit: 80)

        let mode = policy.desiredMode(currentCharge: 90, settings: settings)

        XCTAssertEqual(mode, .normal)
    }

    func testDesiredMode_ChargeBelowLimit_ReturnsNormal() {
        let policy = BatteryPolicy()
        let settings = BatterySettings(isLimitControlEnabled: true, chargeLimit: 80)

        let mode = policy.desiredMode(currentCharge: 60, settings: settings)

        XCTAssertEqual(mode, .normal)
    }

    func testDesiredMode_ChargeAtOrAboveLimit_ReturnsBypass() {
        let policy = BatteryPolicy()
        let settings = BatterySettings(isLimitControlEnabled: true, chargeLimit: 80)

        let modeAtLimit = policy.desiredMode(currentCharge: 80, settings: settings)
        let modeAboveLimit = policy.desiredMode(currentCharge: 95, settings: settings)

        XCTAssertEqual(modeAtLimit, .bypass)
        XCTAssertEqual(modeAboveLimit, .bypass)
    }
}
