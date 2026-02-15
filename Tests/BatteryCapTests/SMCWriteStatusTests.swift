import XCTest

@testable import BatteryCap

final class SMCWriteStatusTests: XCTestCase {
  func testEnabledStatus_PropertiesMatchExpectedValues() {
    let status = SMCWriteStatus.enabled

    XCTAssertTrue(status.isEnabled)
    XCTAssertFalse(status.needsPrivilege)
    XCTAssertEqual(status.message, "已启用特权写入")
    XCTAssertNil(status.hintMessage)
  }

  func testDisabledStatus_WithPrivilegeReason_NeedsPrivilegeTrue() {
    let status = SMCWriteStatus.disabled("需要管理员安装写入组件")

    XCTAssertFalse(status.isEnabled)
    XCTAssertTrue(status.needsPrivilege)
    XCTAssertEqual(status.message, "需要管理员安装写入组件")
    XCTAssertEqual(status.hintMessage, "需要管理员安装写入组件")
  }

  func testDisabledStatus_WithNeutralReason_NeedsPrivilegeFalse() {
    let status = SMCWriteStatus.disabled("无法连接到 SMC")

    XCTAssertFalse(status.needsPrivilege)
  }
}
