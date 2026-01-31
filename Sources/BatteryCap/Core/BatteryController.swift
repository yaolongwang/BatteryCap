import Foundation

// MARK: - Charging Mode

/// 充电控制模式
enum ChargingMode: Equatable {
  case normal
  case chargeLimit(Int)
  case hold(Int)

  var shouldEnableCharging: Bool {
    if case .hold = self {
      return false
    }
    return true
  }
}

// MARK: - Battery Controller Protocol

/// 电池控制器协议
protocol BatteryControllerProtocol: Sendable {
  /// 是否支持实际硬件写入
  var isSupported: Bool { get }

  /// 应用充电模式（会写入 SMC 键值，存在硬件风险）
  func applyChargingMode(_ mode: ChargingMode) async throws
}

// MARK: - SMC Controller

/// SMC 控制器实现（统一通过 Helper 写入）
struct SMCBatteryController: BatteryControllerProtocol, Sendable {
  private let configuration: SMCConfiguration
  let isSupported: Bool
  private let helperClient: SMCHelperClient

  init(configuration: SMCConfiguration = .load()) {
    self.configuration = configuration
    self.isSupported = configuration.status.isEnabled
    self.helperClient = SMCHelperClient()
  }

  func applyChargingMode(_ mode: ChargingMode) async throws {
    guard isSupported else {
      throw BatteryError.unsupportedOperation
    }
    guard configuration.chargingSwitch != nil else {
      throw BatteryError.unsupportedOperation
    }
    guard configuration.status.isEnabled else {
      throw BatteryError.permissionDenied
    }

    try await helperClient.setChargingEnabled(mode.shouldEnableCharging)
  }
}
