import XCTest

@testable import BatteryCap

final class SMCModelsTests: XCTestCase {
  func testSMCKey_ValidRawValue_ProducesExpectedCode() throws {
    let key = try SMCKey("CHTE")
    XCTAssertEqual(key.rawValue, "CHTE")
    XCTAssertEqual(key.code, 0x43485445)
  }

  func testSMCKey_InvalidRawValue_ThrowsSmcKeyInvalid() {
    XCTAssertThrowsError(try SMCKey("BAD")) { error in
      guard let batteryError = error as? BatteryError else {
        XCTFail("错误类型不匹配: \(error)")
        return
      }
      switch batteryError {
      case .smcKeyInvalid:
        break
      default:
        XCTFail("期望 smcKeyInvalid，实际为: \(batteryError)")
      }
    }
  }

  func testSMCDataType_ValidRawValue_ProducesExpectedCode() {
    let dataType = SMCDataType(rawValue: "ui32")
    XCTAssertEqual(dataType?.rawValue, "ui32")
    XCTAssertEqual(dataType?.code, 0x75693332)
  }

  func testSMCDataType_InvalidRawValue_ReturnsNil() {
    XCTAssertNil(SMCDataType(rawValue: "u8"))
  }
}
