import Foundation

/// SMC 键集合
enum SMCKeys {
  /// Tahoe 机型充电开关键
  static var chargingSwitchTahoe: SMCChargingSwitch? {
    guard let key = try? SMCKey("CHTE") else {
      return nil
    }
    let keyDefinition = SMCKeyDefinition(key: key, dataType: nil, dataSize: 4)
    return SMCChargingSwitch(
      keys: [keyDefinition],
      enableBytes: [0x00, 0x00, 0x00, 0x00],
      disableBytes: [0x01, 0x00, 0x00, 0x00]
    )
  }

  /// 旧版固件充电开关键（需成对写入）
  static var chargingSwitchLegacy: SMCChargingSwitch? {
    guard let key1 = try? SMCKey("CH0B"), let key2 = try? SMCKey("CH0C") else {
      return nil
    }
    let keyDef1 = SMCKeyDefinition(key: key1, dataType: nil, dataSize: 1)
    let keyDef2 = SMCKeyDefinition(key: key2, dataType: nil, dataSize: 1)
    return SMCChargingSwitch(
      keys: [keyDef1, keyDef2],
      enableBytes: [0x00],
      disableBytes: [0x02]
    )
  }

  /// 充电开关键候选（按优先级排序）
  static var chargingSwitchCandidates: [SMCChargingSwitch] {
    var candidates: [SMCChargingSwitch] = []
    if let tahoe = chargingSwitchTahoe {
      candidates.append(tahoe)
    }
    if let legacy = chargingSwitchLegacy {
      candidates.append(legacy)
    }
    return candidates
  }
}
