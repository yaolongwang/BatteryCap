import Foundation

/// SMC 配置
struct SMCConfiguration: Sendable {
    let chargeLimitKey: SMCKeyDefinition?
    let allowWrites: Bool
    let status: SMCWriteStatus

    var isWritable: Bool {
        status == .enabledDirect
    }

    static func load(userDefaults: UserDefaults = .standard) -> SMCConfiguration {
        let allowWrites = userDefaults.object(forKey: SettingsKeys.allowSmcWrites) as? Bool ?? true
        let keyDefinition = SMCKeys.batteryChargeLimit
        let status = resolveStatus(allowWrites: allowWrites, keyDefinition: keyDefinition)
        return SMCConfiguration(
            chargeLimitKey: keyDefinition, allowWrites: allowWrites, status: status)
    }

    private static func resolveStatus(allowWrites: Bool, keyDefinition: SMCKeyDefinition?)
        -> SMCWriteStatus
    {
        guard allowWrites else {
            return .disabled("SMC 写入已关闭")
        }
        guard let keyDefinition else {
            return .disabled("未找到可写的 SMC 键")
        }

        let directResult = SMCClient.checkWriteAccess(keyDefinition)
        if directResult == .supported {
            return .enabledDirect
        }
        if SMCHelperClient.isInstalled {
            return .enabledHelper
        }
        switch directResult {
        case .permissionDenied:
            return .disabled("需要管理员安装写入组件（运行 scripts/install-helper.sh）")
        case .keyNotFound:
            return .disabled("SMC 键不存在或不可写")
        case .typeMismatch:
            return .disabled("SMC 键类型不匹配")
        case .smcUnavailable:
            return .disabled("无法连接到 SMC")
        case .unknown, .supported:
            return .disabled("SMC 写入不可用")
        }
    }
}

private enum SettingsKeys {
    static let allowSmcWrites = "BatteryCap.allowSmcWrites"
}
