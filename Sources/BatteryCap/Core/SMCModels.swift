import Foundation

/// SMC 键
struct SMCKey: Equatable, Sendable {
    let rawValue: String
    let code: UInt32

    init(_ rawValue: String) throws {
        guard rawValue.count == 4 else {
            throw BatteryError.smcKeyInvalid
        }
        self.rawValue = rawValue
        var value: UInt32 = 0
        for byte in rawValue.utf8 {
            value = (value << 8) | UInt32(byte)
        }
        self.code = value
    }
}

/// SMC 数据类型
struct SMCDataType: Equatable, Sendable {
    let rawValue: String
    let code: UInt32

    init?(rawValue: String) {
        guard rawValue.count == 4 else {
            return nil
        }
        self.rawValue = rawValue
        var value: UInt32 = 0
        for byte in rawValue.utf8 {
            value = (value << 8) | UInt32(byte)
        }
        self.code = value
    }
}

/// SMC 键定义
struct SMCKeyDefinition: Sendable {
    let key: SMCKey
    let dataType: SMCDataType?
    let dataSize: Int
}
