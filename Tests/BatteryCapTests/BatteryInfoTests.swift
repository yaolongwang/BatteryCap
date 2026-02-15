import XCTest

@testable import BatteryCap

final class BatteryInfoTests: XCTestCase {
  func testPowerSourceText_Battery_ReturnsExpectedText() {
    let info = BatteryInfo(chargePercentage: 50, cycleCount: nil, powerSource: .battery, chargeState: .unknown)
    XCTAssertEqual(info.powerSourceText, "电池供电")
  }

  func testPowerSourceText_Adapter_ReturnsExpectedText() {
    let info = BatteryInfo(chargePercentage: 50, cycleCount: nil, powerSource: .adapter, chargeState: .unknown)
    XCTAssertEqual(info.powerSourceText, "适配器供电")
  }

  func testChargeStateText_Charging_ReturnsExpectedText() {
    let info = BatteryInfo(chargePercentage: 50, cycleCount: nil, powerSource: .adapter, chargeState: .charging)
    XCTAssertEqual(info.chargeStateText, "充电中")
  }

  func testChargeStateText_Paused_ReturnsExpectedText() {
    let info = BatteryInfo(chargePercentage: 50, cycleCount: nil, powerSource: .adapter, chargeState: .paused)
    XCTAssertEqual(info.chargeStateText, "充电暂停")
  }
}
