import Foundation

/// 充电控制策略
struct BatteryPolicy {
  let hysteresisPercent: Int

  init(hysteresisPercent: Int = BatteryConstants.hysteresisPercent) {
    self.hysteresisPercent = max(0, hysteresisPercent)
  }

  func desiredMode(
    currentCharge: Int,
    settings: BatterySettings,
    lastAppliedMode: ChargingMode?
  ) -> ChargingMode {
    guard settings.isLimitControlEnabled else {
      return .normal
    }

    let limit = settings.chargeLimit
    let upper = min(limit + hysteresisPercent, BatteryConstants.maxChargeLimit)
    let lower = max(limit - hysteresisPercent, BatteryConstants.minChargeLimit)

    switch lastAppliedMode {
    case .hold:
      if currentCharge <= lower {
        return .chargeLimit(limit)
      }
      return .hold(currentCharge)
    case .chargeLimit, .normal, .none:
      if currentCharge >= upper {
        return .hold(currentCharge)
      }
      return .chargeLimit(limit)
    }
  }
}

extension BatteryPolicy {
  static func defaultPolicy() -> BatteryPolicy {
    BatteryPolicy(hysteresisPercent: BatteryConstants.hysteresisPercent)
  }
}
