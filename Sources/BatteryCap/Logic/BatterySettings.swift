import Foundation

/// 用户设置快照
struct BatterySettings: Equatable {
  var isLimitControlEnabled: Bool
  var chargeLimit: Int
  var keepStateOnQuit: Bool
  var launchAtLoginEnabled: Bool
}

/// 设置存储协议
protocol BatterySettingsStoreProtocol {
  func load() -> BatterySettings
  func save(_ settings: BatterySettings)
}

/// 基于 UserDefaults 的设置存储
final class UserDefaultsBatterySettingsStore: BatterySettingsStoreProtocol {
  // MARK: - Keys

  private enum Keys {
    static let isLimitControlEnabled = "BatteryCap.isLimitControlEnabled"
    static let chargeLimit = "BatteryCap.chargeLimit"
    static let keepStateOnQuit = "BatteryCap.keepStateOnQuit"
    static let launchAtLoginEnabled = "BatteryCap.launchAtLoginEnabled"
  }

  // MARK: - Dependencies

  private let userDefaults: UserDefaults

  // MARK: - Init

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  // MARK: - BatterySettingsStoreProtocol

  func load() -> BatterySettings {
    let enabled = userDefaults.object(forKey: Keys.isLimitControlEnabled) as? Bool ?? false
    let limit =
      userDefaults.object(forKey: Keys.chargeLimit) as? Int
      ?? BatteryConstants.defaultChargeLimit
    let keepStateOnQuit = userDefaults.object(forKey: Keys.keepStateOnQuit) as? Bool ?? false
    let launchAtLoginEnabled =
      userDefaults.object(forKey: Keys.launchAtLoginEnabled) as? Bool ?? false

    return BatterySettings(
      isLimitControlEnabled: enabled,
      chargeLimit: BatteryConstants.clampChargeLimit(limit),
      keepStateOnQuit: keepStateOnQuit,
      launchAtLoginEnabled: launchAtLoginEnabled
    )
  }

  func save(_ settings: BatterySettings) {
    userDefaults.set(settings.isLimitControlEnabled, forKey: Keys.isLimitControlEnabled)
    userDefaults.set(BatteryConstants.clampChargeLimit(settings.chargeLimit), forKey: Keys.chargeLimit)
    userDefaults.set(settings.keepStateOnQuit, forKey: Keys.keepStateOnQuit)
    userDefaults.set(settings.launchAtLoginEnabled, forKey: Keys.launchAtLoginEnabled)
  }
}
