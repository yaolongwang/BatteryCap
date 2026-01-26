import Foundation

/// SMC 配置
struct SMCConfiguration: Sendable {
    let chargeLimitKey: SMCKeyDefinition?
    let allowWrites: Bool
    let isWritable: Bool

    static func load(userDefaults: UserDefaults = .standard) -> SMCConfiguration {
        let allowWrites = userDefaults.object(forKey: SettingsKeys.allowSmcWrites) as? Bool ?? true
        let keyDefinition = SMCKeys.batteryChargeLimit
        let isWritable = allowWrites && canWrite(keyDefinition)
        return SMCConfiguration(chargeLimitKey: keyDefinition, allowWrites: allowWrites, isWritable: isWritable)
    }

    private static func canWrite(_ keyDefinition: SMCKeyDefinition?) -> Bool {
        guard let keyDefinition else {
            return false
        }
        return SMCClient.canWrite(keyDefinition)
    }
}

private enum SettingsKeys {
    static let allowSmcWrites = "BatteryCap.allowSmcWrites"
}
