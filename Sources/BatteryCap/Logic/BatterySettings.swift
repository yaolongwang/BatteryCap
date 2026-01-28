import Foundation

/// 用户设置快照
struct BatterySettings: Equatable {
  var isLimitControlEnabled: Bool
  var chargeLimit: Int
}

/// 设置存储协议
protocol BatterySettingsStoreProtocol {
  func load() -> BatterySettings
  func save(_ settings: BatterySettings)
}

/// 基于 UserDefaults 的设置存储
final class UserDefaultsBatterySettingsStore: BatterySettingsStoreProtocol {
  private enum Keys {
    static let isLimitControlEnabled = "BatteryCap.isLimitControlEnabled"
    static let chargeLimit = "BatteryCap.chargeLimit"
  }

  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  func load() -> BatterySettings {
    let enabled = userDefaults.object(forKey: Keys.isLimitControlEnabled) as? Bool ?? false
    let limit =
      userDefaults.object(forKey: Keys.chargeLimit) as? Int ?? BatteryConstants.defaultChargeLimit

    return BatterySettings(
      isLimitControlEnabled: enabled,
      chargeLimit: clampLimit(limit)
    )
  }

  func save(_ settings: BatterySettings) {
    userDefaults.set(settings.isLimitControlEnabled, forKey: Keys.isLimitControlEnabled)
    userDefaults.set(clampLimit(settings.chargeLimit), forKey: Keys.chargeLimit)
  }

  private func clampLimit(_ value: Int) -> Int {
    min(max(value, BatteryConstants.minChargeLimit), BatteryConstants.maxChargeLimit)
  }
}
