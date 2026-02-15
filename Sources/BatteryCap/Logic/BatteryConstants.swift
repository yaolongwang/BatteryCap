import Foundation

/// 业务常量
enum BatteryConstants {
  static let minChargeLimit = 50
  static let maxChargeLimit = 100
  static let defaultChargeLimit = 80
  static let hysteresisPercent = 1
  static let refreshInterval: TimeInterval = 60
  static let refreshTolerance: TimeInterval = 5

  static var chargeLimitSliderRange: ClosedRange<Double> {
    Double(minChargeLimit)...Double(maxChargeLimit)
  }

  static func clampChargeLimit(_ value: Int) -> Int {
    min(max(value, minChargeLimit), maxChargeLimit)
  }
}
