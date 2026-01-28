import Foundation

/// 充电控制策略
struct BatteryPolicy {
  func desiredMode(currentCharge: Int, settings: BatterySettings) -> ChargingMode {
    guard settings.isLimitControlEnabled else {
      return .normal
    }

    if currentCharge >= settings.chargeLimit {
      return .hold(currentCharge)
    }

    return .chargeLimit(settings.chargeLimit)
  }
}
