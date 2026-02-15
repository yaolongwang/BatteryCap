import XCTest

@testable import BatteryCap

final class BatterySettingsStoreTests: XCTestCase {
  private var suiteName: String!
  private var userDefaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "BatteryCapTests.\(UUID().uuidString)"
    userDefaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    if let suiteName {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    userDefaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testLoad_NoStoredValues_ReturnsExpectedDefaults() {
    let store = UserDefaultsBatterySettingsStore(userDefaults: userDefaults)

    let settings = store.load()

    XCTAssertEqual(settings.isLimitControlEnabled, false)
    XCTAssertEqual(settings.chargeLimit, BatteryConstants.defaultChargeLimit)
    XCTAssertEqual(settings.keepStateOnQuit, false)
    XCTAssertEqual(settings.launchAtLoginEnabled, false)
  }

  func testSave_ChargeLimitOutOfRange_StoresClampedValue() {
    let store = UserDefaultsBatterySettingsStore(userDefaults: userDefaults)
    let settings = BatterySettings(
      isLimitControlEnabled: true,
      chargeLimit: 999,
      keepStateOnQuit: true,
      launchAtLoginEnabled: true
    )

    store.save(settings)
    let loaded = store.load()

    XCTAssertEqual(loaded.chargeLimit, BatteryConstants.maxChargeLimit)
    XCTAssertEqual(loaded.isLimitControlEnabled, true)
    XCTAssertEqual(loaded.keepStateOnQuit, true)
    XCTAssertEqual(loaded.launchAtLoginEnabled, true)
  }

  func testLoad_StoredChargeLimitBelowMinimum_ReturnsClampedValue() {
    userDefaults.set(-1, forKey: "BatteryCap.chargeLimit")
    let store = UserDefaultsBatterySettingsStore(userDefaults: userDefaults)

    let loaded = store.load()

    XCTAssertEqual(loaded.chargeLimit, BatteryConstants.minChargeLimit)
  }
}
