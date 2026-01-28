import Foundation

@testable import BatteryCap

final class MockBatteryController: BatteryControllerProtocol, @unchecked Sendable {
  let isSupported: Bool
  private(set) var appliedModes: [ChargingMode] = []

  init(isSupported: Bool = true) {
    self.isSupported = isSupported
  }

  func applyChargingMode(_ mode: ChargingMode) async throws {
    appliedModes.append(mode)
  }
}
