import Foundation

// MARK: - SMC Keys

/// SMC 键集合
enum SMCKeys {
  /// Tahoe 机型充电开关键
  static let chargingSwitchTahoe: SMCChargingSwitch? = {
    guard let keyDefinition = keyDefinition(rawValue: "CHTE", dataSize: 4) else {
      return nil
    }
    return SMCChargingSwitch(
      keys: [keyDefinition],
      enableBytes: [0x00, 0x00, 0x00, 0x00],
      disableBytes: [0x01, 0x00, 0x00, 0x00]
    )
  }()

  /// 旧版固件充电开关键（需成对写入）
  static let chargingSwitchLegacy: SMCChargingSwitch? = {
    guard
      let key1 = keyDefinition(rawValue: "CH0B", dataSize: 1),
      let key2 = keyDefinition(rawValue: "CH0C", dataSize: 1)
    else {
      return nil
    }
    return SMCChargingSwitch(
      keys: [key1, key2],
      enableBytes: [0x00],
      disableBytes: [0x02]
    )
  }()

  /// 充电开关键候选（按优先级排序）
  static let chargingSwitchCandidates: [SMCChargingSwitch] = {
    [chargingSwitchTahoe, chargingSwitchLegacy].compactMap { $0 }
  }()

  private static func keyDefinition(rawValue: String, dataSize: Int) -> SMCKeyDefinition? {
    guard let key = try? SMCKey(rawValue) else {
      return nil
    }
    return SMCKeyDefinition(key: key, dataType: nil, dataSize: dataSize)
  }
}
