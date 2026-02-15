import XCTest

@testable import BatteryCap

final class SMCKeysTests: XCTestCase {
  func testChargingSwitchTahoe_ContainsExpectedKeyAndBytes() {
    let tahoe = SMCKeys.chargingSwitchTahoe

    XCTAssertNotNil(tahoe)
    XCTAssertEqual(tahoe?.keyNames, ["CHTE"])
    XCTAssertEqual(tahoe?.dataSize, 4)
    XCTAssertEqual(tahoe?.enableBytes, [0x00, 0x00, 0x00, 0x00])
    XCTAssertEqual(tahoe?.disableBytes, [0x01, 0x00, 0x00, 0x00])
  }

  func testChargingSwitchLegacy_ContainsExpectedKeysAndBytes() {
    let legacy = SMCKeys.chargingSwitchLegacy

    XCTAssertNotNil(legacy)
    XCTAssertEqual(legacy?.keyNames, ["CH0B", "CH0C"])
    XCTAssertEqual(legacy?.dataSize, 1)
    XCTAssertEqual(legacy?.enableBytes, [0x00])
    XCTAssertEqual(legacy?.disableBytes, [0x02])
  }

  func testChargingSwitchCandidates_PreservesPriorityOrder() {
    let candidates = SMCKeys.chargingSwitchCandidates

    XCTAssertGreaterThanOrEqual(candidates.count, 2)
    XCTAssertEqual(candidates.first?.keyNames, ["CHTE"])
    XCTAssertEqual(candidates.dropFirst().first?.keyNames, ["CH0B", "CH0C"])
  }
}
