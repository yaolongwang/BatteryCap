import Foundation

/// 充电控制模式
enum ChargingMode: Equatable {
  case normal
  case chargeLimit(Int)
  case hold(Int)

  var targetLimit: Int {
    switch self {
    case .normal:
      return BatteryConstants.maxChargeLimit
    case .chargeLimit(let limit):
      return limit
    case .hold(let level):
      return level
    }
  }
}

/// 电池控制器协议
protocol BatteryControllerProtocol: Sendable {
  /// 是否支持实际硬件写入
  var isSupported: Bool { get }

  /// 应用充电模式（会写入 SMC 键值，存在硬件风险）
  func applyChargingMode(_ mode: ChargingMode) async throws
}

/// SMC 控制器实现
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

    switch configuration.status {
    case .enabledDirect:
      do {
        try applyModeDirect(mode)
      } catch {
        if shouldFallbackToHelper(error), SMCHelperClient.isInstalled {
          try await applyModeWithHelper(mode)
          return
        }
        throw error
      }
    case .enabledHelper:
      do {
        try await applyModeWithHelper(mode)
      } catch {
        if shouldFallbackToDirect(error) {
          try applyModeDirect(mode)
          return
        }
        throw error
      }
    case .disabled:
      throw BatteryError.permissionDenied
    }
  }

  private func applyModeDirect(_ mode: ChargingMode) throws {
    guard let strategy = configuration.controlStrategy else {
      throw BatteryError.unsupportedOperation
    }

    let client = try SMCClient()
    switch strategy {
    case .chargeLimit(let keyDefinition):
      let limit = clampLimit(for: mode)
      try client.writeUInt8(UInt8(limit), to: keyDefinition)
    case .chargingSwitch(let chargingSwitch):
      let shouldEnable: Bool
      if case .hold = mode {
        shouldEnable = false
      } else {
        shouldEnable = true
      }
      let bytes = shouldEnable ? chargingSwitch.enableBytes : chargingSwitch.disableBytes
      for keyDefinition in chargingSwitch.keys {
        try client.writeBytes(bytes, to: keyDefinition)
      }
    }
  }

  private func applyModeWithHelper(_ mode: ChargingMode) async throws {
    guard let strategy = configuration.controlStrategy else {
      throw BatteryError.unsupportedOperation
    }

    switch strategy {
    case .chargeLimit:
      let limit = clampLimit(for: mode)
      try await helperClient.setChargeLimit(limit)
    case .chargingSwitch:
      let shouldEnable: Bool
      if case .hold = mode {
        shouldEnable = false
      } else {
        shouldEnable = true
      }
      try await helperClient.setChargingEnabled(shouldEnable)
    }
  }

  private func shouldFallbackToHelper(_ error: Error) -> Bool {
    guard let batteryError = error as? BatteryError else {
      return false
    }
    switch batteryError {
    case .permissionDenied, .smcWriteFailed:
      return true
    default:
      return false
    }
  }

  private func shouldFallbackToDirect(_ error: Error) -> Bool {
    guard let batteryError = error as? BatteryError else {
      return false
    }
    switch batteryError {
    case .controllerUnavailable:
      return true
    default:
      return false
    }
  }

  private func clampLimit(for mode: ChargingMode) -> Int {
    let minValue: Int
    switch mode {
    case .hold:
      minValue = 1
    case .normal, .chargeLimit:
      minValue = BatteryConstants.minChargeLimit
    }

    return min(max(mode.targetLimit, minValue), BatteryConstants.maxChargeLimit)
  }
}
