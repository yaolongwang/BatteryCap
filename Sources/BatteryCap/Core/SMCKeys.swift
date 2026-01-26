import Foundation

/// SMC 键集合
enum SMCKeys {
    /// 电池最大充电上限键（需确认机型支持）
    static var batteryChargeLimit: SMCKeyDefinition? {
        guard let key = try? SMCKey("BCLM") else {
            return nil
        }
        let dataType = SMCDataType(rawValue: "ui8 ")
        return SMCKeyDefinition(key: key, dataType: dataType, dataSize: 1)
    }
}
