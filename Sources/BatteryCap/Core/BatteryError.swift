import Foundation

/// 电池相关错误
enum BatteryError: Error, LocalizedError {
  case powerSourceUnavailable
  case batteryNotFound
  case invalidPowerSourceData
  case unsupportedOperation
  case controllerUnavailable
  case permissionDenied
  case smcUnavailable
  case smcKeyInvalid
  case smcKeyNotFound
  case smcTypeMismatch
  case smcWriteFailed
  case unknown(String)

  var errorDescription: String? {
    switch self {
    case .powerSourceUnavailable:
      return "无法获取电源信息。"
    case .batteryNotFound:
      return "未找到内置电池。"
    case .invalidPowerSourceData:
      return "电源信息解析失败。"
    case .unsupportedOperation:
      return "当前版本未实现该硬件操作。"
    case .controllerUnavailable:
      return "特权组件不可用，请重新安装写入组件。"
    case .permissionDenied:
      return "权限不足，无法执行该操作。"
    case .smcUnavailable:
      return "无法连接到 SMC。"
    case .smcKeyInvalid:
      return "SMC 键格式无效。"
    case .smcKeyNotFound:
      return "当前机型不支持该充电控制。"
    case .smcTypeMismatch:
      return "SMC 键类型不匹配。"
    case .smcWriteFailed:
      return "系统拒绝写入 SMC，可能当前机型或系统不支持充电控制。"
    case .unknown(let message):
      return message
    }
  }
}
