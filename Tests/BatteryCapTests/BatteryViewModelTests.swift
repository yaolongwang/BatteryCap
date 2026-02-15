import Foundation
import XCTest

@testable import BatteryCap

@MainActor
final class BatteryViewModelTests: XCTestCase {
  func testUpdateChargeLimit_ValueAboveMax_ClampsAndPersists() {
    let infoProvider = MockBatteryInfoProvider(result: .success(sampleInfo))
    let controller = MockBatteryController()
    let settingsStore = MockBatterySettingsStore(initial: defaultSettings)
    let viewModel = makeViewModel(
      infoProvider: infoProvider,
      controller: controller,
      settingsStore: settingsStore
    )

    viewModel.updateChargeLimit(999)

    XCTAssertEqual(viewModel.chargeLimit, BatteryConstants.maxChargeLimit)
    XCTAssertEqual(settingsStore.lastSaved?.chargeLimit, BatteryConstants.maxChargeLimit)
  }

  func testUpdateLimitControlEnabled_UpdatesStateAndPersists() {
    let infoProvider = MockBatteryInfoProvider(result: .success(sampleInfo))
    let controller = MockBatteryController()
    let settingsStore = MockBatterySettingsStore(initial: defaultSettings)
    let viewModel = makeViewModel(
      infoProvider: infoProvider,
      controller: controller,
      settingsStore: settingsStore
    )

    viewModel.updateLimitControlEnabled(true)

    XCTAssertTrue(viewModel.isLimitControlEnabled)
    XCTAssertEqual(settingsStore.lastSaved?.isLimitControlEnabled, true)
  }

  func testRestoreSystemDefault_DisablesControlAndPersistsMaxLimit() {
    let infoProvider = MockBatteryInfoProvider(result: .success(sampleInfo))
    let controller = MockBatteryController()
    let initial = BatterySettings(
      isLimitControlEnabled: true,
      chargeLimit: 60,
      keepStateOnQuit: false,
      launchAtLoginEnabled: false
    )
    let settingsStore = MockBatterySettingsStore(initial: initial)
    let viewModel = makeViewModel(
      infoProvider: infoProvider,
      controller: controller,
      settingsStore: settingsStore
    )

    viewModel.restoreSystemDefault()

    XCTAssertFalse(viewModel.isLimitControlEnabled)
    XCTAssertEqual(viewModel.chargeLimit, BatteryConstants.maxChargeLimit)
    XCTAssertEqual(settingsStore.lastSaved?.isLimitControlEnabled, false)
    XCTAssertEqual(settingsStore.lastSaved?.chargeLimit, BatteryConstants.maxChargeLimit)
  }

  func testRefreshNow_InfoFetchSuccess_UpdatesBatteryInfoAndTimestamp() async {
    let infoProvider = MockBatteryInfoProvider(result: .success(sampleInfo))
    let controller = MockBatteryController()
    let settingsStore = MockBatterySettingsStore(initial: defaultSettings)
    let viewModel = makeViewModel(
      infoProvider: infoProvider,
      controller: controller,
      settingsStore: settingsStore
    )

    viewModel.refreshNow()
    await waitUntil { viewModel.batteryInfo != nil }

    XCTAssertEqual(viewModel.batteryInfo, sampleInfo)
    XCTAssertNotNil(viewModel.lastUpdated)
    XCTAssertNil(viewModel.errorMessage)
  }

  func testRefreshNow_InfoFetchFailure_SetsErrorMessage() async {
    let infoProvider = MockBatteryInfoProvider(
      result: .failure(BatteryError.invalidPowerSourceData))
    let controller = MockBatteryController()
    let settingsStore = MockBatterySettingsStore(initial: defaultSettings)
    let viewModel = makeViewModel(
      infoProvider: infoProvider,
      controller: controller,
      settingsStore: settingsStore
    )

    viewModel.refreshNow()
    await waitUntil { viewModel.errorMessage != nil }

    XCTAssertEqual(viewModel.errorMessage, BatteryError.invalidPowerSourceData.localizedDescription)
  }

  private func makeViewModel(
    infoProvider: MockBatteryInfoProvider,
    controller: MockBatteryController,
    settingsStore: MockBatterySettingsStore
  ) -> BatteryViewModel {
    BatteryViewModel(
      infoProvider: infoProvider,
      controller: controller,
      settingsStore: settingsStore,
      policy: BatteryPolicy(hysteresisPercent: BatteryConstants.hysteresisPercent),
      monitor: BatteryPowerMonitor(),
      privilegeManager: SMCPrivilegeManager()
    )
  }

  private func waitUntil(timeout: TimeInterval = 1.0, condition: @escaping () -> Bool) async {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
      if condition() {
        return
      }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("等待异步状态更新超时")
  }

  private var defaultSettings: BatterySettings {
    BatterySettings(
      isLimitControlEnabled: false,
      chargeLimit: BatteryConstants.defaultChargeLimit,
      keepStateOnQuit: false,
      launchAtLoginEnabled: false
    )
  }

  private var sampleInfo: BatteryInfo {
    BatteryInfo(
      chargePercentage: 72,
      cycleCount: 123,
      powerSource: .adapter,
      chargeState: .charging
    )
  }
}

private final class MockBatterySettingsStore: BatterySettingsStoreProtocol {
  private var storage: BatterySettings
  private(set) var lastSaved: BatterySettings?

  init(initial: BatterySettings) {
    storage = initial
  }

  func load() -> BatterySettings {
    storage
  }

  func save(_ settings: BatterySettings) {
    storage = settings
    lastSaved = settings
  }
}

private struct MockBatteryInfoProvider: BatteryInfoProviderProtocol {
  let result: Result<BatteryInfo, Error>

  func fetchBatteryInfo() async throws -> BatteryInfo {
    try result.get()
  }
}

private final class MockBatteryController: BatteryControllerProtocol, @unchecked Sendable {
  let isSupported: Bool
  private(set) var appliedModes: [ChargingMode] = []

  init(isSupported: Bool = true) {
    self.isSupported = isSupported
  }

  func applyChargingMode(_ mode: ChargingMode) async throws {
    appliedModes.append(mode)
  }
}
