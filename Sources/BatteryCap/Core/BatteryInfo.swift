import Foundation

/// 供电来源
enum BatteryPowerSource: Equatable {
  case battery
  case adapter
  case unknown
}

/// 充电状态
enum BatteryChargeState: Equatable {
  case charging
  case discharging
  case charged
  case paused
  case unknown
}

/// 电池状态快照
struct BatteryInfo: Equatable {
  let chargePercentage: Int
  let cycleCount: Int?
  let powerSource: BatteryPowerSource
  let chargeState: BatteryChargeState
}

extension BatteryInfo {
  var powerSourceText: String {
    powerSource.descriptionText
  }

  var chargeStateText: String {
    chargeState.descriptionText
  }
}

extension BatteryPowerSource {
  fileprivate var descriptionText: String {
    switch self {
    case .battery:
      return "电池供电"
    case .adapter:
      return "适配器供电"
    case .unknown:
      return "未知供电"
    }
  }
}

extension BatteryChargeState {
  fileprivate var descriptionText: String {
    switch self {
    case .charging:
      return "充电中"
    case .discharging:
      return "放电中"
    case .charged:
      return "已充满"
    case .paused:
      return "充电暂停"
    case .unknown:
      return "未知状态"
    }
  }
}
