import Foundation

/// 业务常量
enum BatteryConstants {
  static let minChargeLimit = 50
  static let maxChargeLimit = 100
  static let defaultChargeLimit = 80
  static let refreshIntervalSeconds: UInt64 = 20
  static let refreshIntervalNanoseconds: UInt64 = refreshIntervalSeconds * 1_000_000_000
}
