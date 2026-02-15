import Foundation

// MARK: - SMC Models

/// SMC 键
struct SMCKey: Equatable, Sendable {
  let rawValue: String
  let code: UInt32

  init(_ rawValue: String) throws {
    guard let code = FourCharCode.from(rawValue) else {
      throw BatteryError.smcKeyInvalid
    }
    self.rawValue = rawValue
    self.code = code
  }
}

/// SMC 数据类型
struct SMCDataType: Equatable, Sendable {
  let rawValue: String
  let code: UInt32

  init?(rawValue: String) {
    guard let code = FourCharCode.from(rawValue) else {
      return nil
    }
    self.rawValue = rawValue
    self.code = code
  }
}

/// SMC 键定义
struct SMCKeyDefinition: Sendable {
  let key: SMCKey
  let dataType: SMCDataType?
  let dataSize: Int
}

private enum FourCharCode {
  static func from(_ rawValue: String) -> UInt32? {
    guard rawValue.count == 4 else {
      return nil
    }

    var value: UInt32 = 0
    for byte in rawValue.utf8 {
      value = (value << 8) | UInt32(byte)
    }
    return value
  }
}
