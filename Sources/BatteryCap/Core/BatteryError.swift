import Foundation

/// 电池相关错误
enum BatteryError: Error, LocalizedError {
    case powerSourceUnavailable
    case batteryNotFound
    case invalidPowerSourceData
    case unsupportedOperation
    case controllerUnavailable
    case permissionDenied
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
        case .unknown(let message):
            return message
        }
    }
}
