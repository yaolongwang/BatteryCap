import Foundation

/// SMC 写入状态
enum SMCWriteStatus: Equatable {
    case enabledDirect
    case enabledHelper
    case disabled(String)

    var isEnabled: Bool {
        switch self {
        case .enabledDirect, .enabledHelper:
            return true
        case .disabled:
            return false
        }
    }

    var needsPrivilege: Bool {
        switch self {
        case .disabled(let reason):
            return reason.contains("管理员") || reason.contains("授权")
        default:
            return false
        }
    }

    var message: String {
        switch self {
        case .enabledDirect:
            return "已启用 SMC 写入"
        case .enabledHelper:
            return "已启用特权写入"
        case .disabled(let reason):
            return reason
        }
    }

    var hintMessage: String? {
        switch self {
        case .disabled(let reason):
            return reason
        case .enabledDirect, .enabledHelper:
            return nil
        }
    }
}

/// 写入能力检测结果
enum SMCWriteCheckResult: Equatable {
    case supported
    case permissionDenied
    case keyNotFound
    case typeMismatch
    case smcUnavailable
    case unknown
}
