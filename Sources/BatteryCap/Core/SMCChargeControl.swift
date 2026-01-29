import Foundation

/// 充电开关键配置
struct SMCChargingSwitch: Sendable {
  let keys: [SMCKeyDefinition]
  let enableBytes: [UInt8]
  let disableBytes: [UInt8]

  var keyNames: [String] {
    keys.map { $0.key.rawValue }
  }

  var dataSize: Int {
    keys.first?.dataSize ?? 0
  }
}
