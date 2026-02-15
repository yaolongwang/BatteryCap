import XCTest

@testable import BatteryCap

final class BatteryErrorTests: XCTestCase {
  func testErrorDescription_PermissionDenied_ReturnsLocalizedMessage() {
    XCTAssertEqual(BatteryError.permissionDenied.localizedDescription, "权限不足，无法执行该操作。")
  }

  func testErrorDescription_SmcKeyNotFound_ReturnsLocalizedMessage() {
    XCTAssertEqual(BatteryError.smcKeyNotFound.localizedDescription, "当前机型不支持该充电控制。")
  }

  func testErrorDescription_Unknown_ReturnsProvidedMessage() {
    XCTAssertEqual(BatteryError.unknown("自定义错误").localizedDescription, "自定义错误")
  }
}
