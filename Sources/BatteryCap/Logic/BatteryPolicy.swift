import Foundation

/// 充电控制策略（包含滞回区间）
struct BatteryPolicy {
  /// 滞回区间百分比（0 表示关闭滞回）
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

    let limit = clampLimit(settings.chargeLimit)
    let upper = min(limit + hysteresisPercent, BatteryConstants.maxChargeLimit)
    let lower = max(limit - hysteresisPercent, BatteryConstants.minChargeLimit)

    switch lastAppliedMode {
    case .hold:
      return currentCharge <= lower ? .chargeLimit(limit) : .hold(currentCharge)
    case .chargeLimit, .normal, .none:
      return currentCharge >= upper ? .hold(currentCharge) : .chargeLimit(limit)
    }
  }

  private func clampLimit(_ value: Int) -> Int {
    min(max(value, BatteryConstants.minChargeLimit), BatteryConstants.maxChargeLimit)
  }
}

extension BatteryPolicy {
  static func defaultPolicy() -> BatteryPolicy {
    BatteryPolicy(hysteresisPercent: BatteryConstants.hysteresisPercent)
  }
}
