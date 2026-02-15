import XCTest

@testable import BatteryCap

final class SMCChargeControlTests: XCTestCase {
  func testKeyNamesAndDataSize_WithMultipleKeys_ReturnsFirstDataSize() throws {
    let keyA = try SMCKey("CH0B")
    let keyB = try SMCKey("CH0C")
    let control = SMCChargingSwitch(
      keys: [
        SMCKeyDefinition(key: keyA, dataType: nil, dataSize: 1),
        SMCKeyDefinition(key: keyB, dataType: nil, dataSize: 4),
      ],
      enableBytes: [0x00],
      disableBytes: [0x02]
    )

    XCTAssertEqual(control.keyNames, ["CH0B", "CH0C"])
    XCTAssertEqual(control.dataSize, 1)
  }

  func testDataSize_WithoutKeys_ReturnsZero() {
    let control = SMCChargingSwitch(keys: [], enableBytes: [0x00], disableBytes: [0x01])
    XCTAssertEqual(control.dataSize, 0)
  }
}
