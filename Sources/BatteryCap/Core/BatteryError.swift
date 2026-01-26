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
            return "电池控制器不可用。"
        case .permissionDenied:
            return "权限不足，无法执行该操作。"
        case .smcUnavailable:
            return "无法连接到 SMC。"
        case .smcKeyInvalid:
            return "SMC 键格式无效。"
        case .smcKeyNotFound:
            return "SMC 键不存在或不可写。"
        case .smcTypeMismatch:
            return "SMC 键类型不匹配。"
        case .smcWriteFailed:
            return "写入 SMC 失败。"
        case .unknown(let message):
            return message
        }
    }
}
