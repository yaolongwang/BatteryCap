import Foundation
import XCTest

@testable import BatteryCap

@MainActor final class BatteryViewModelTests: XCTestCase {
  func testUpdateLaunchAtLoginEnabled_EnableSuccessWithoutMessage_DoesNotShowAlert() {
    let infoProvider = MockBatteryInfoProvider(result: .success(sampleInfo))
    let controller = MockBatteryController()
    let settingsStore = MockBatterySettingsStore(initial: defaultSettings)
    let launchAtLoginManager = MockLaunchAtLoginManager(
      currentState: LaunchAtLoginState(isEnabled: false, message: nil))
    launchAtLoginManager.setEnabledHandler = { enabled in
      LaunchAtLoginState(isEnabled: enabled, message: nil)
    }
    let viewModel = makeViewModel(
      infoProvider: infoProvider, controller: controller, settingsStore: settingsStore,
      launchAtLoginManager: launchAtLoginManager)

    viewModel.updateLaunchAtLoginEnabled(true)

    XCTAssertEqual(viewModel.isLaunchAtLoginEnabled, true)
    XCTAssertNil(viewModel.activeAlert)
    XCTAssertEqual(settingsStore.lastSaved?.launchAtLoginEnabled, true)
  }

  func testUpdateLaunchAtLoginEnabled_EnableNotFound_ShowsAlertMessage() {
    let infoProvider = MockBatteryInfoProvider(result: .success(sampleInfo))
    let controller = MockBatteryController()
    let settingsStore = MockBatterySettingsStore(initial: defaultSettings)
    let launchAtLoginManager = MockLaunchAtLoginManager(
      currentState: LaunchAtLoginState(isEnabled: false, message: nil))
    launchAtLoginManager.setEnabledHandler = { _ in
      LaunchAtLoginState(isEnabled: false, message: "系统未找到开机自启动注册项，请重试或重启应用后再试。")
    }
    let viewModel = makeViewModel(
      infoProvider: infoProvider, controller: controller, settingsStore: settingsStore,
      launchAtLoginManager: launchAtLoginManager)

    viewModel.updateLaunchAtLoginEnabled(true)

    XCTAssertEqual(viewModel.isLaunchAtLoginEnabled, false)
    XCTAssertEqual(viewModel.activeAlert, .launchAtLogin(message: "系统未找到开机自启动注册项，请重试或重启应用后再试。"))
  }

  func testUpdateLaunchAtLoginEnabled_EnableThrows_ShowsAlertMessage() {
    let infoProvider = MockBatteryInfoProvider(result: .success(sampleInfo))
    let controller = MockBatteryController()
    let settingsStore = MockBatterySettingsStore(initial: defaultSettings)
    let launchAtLoginManager = MockLaunchAtLoginManager(
      currentState: LaunchAtLoginState(isEnabled: false, message: nil))
    launchAtLoginManager.setEnabledHandler = { _ in
      throw MockLocalizedError(message: "mock enable failure")
    }
    let viewModel = makeViewModel(
      infoProvider: infoProvider, controller: controller, settingsStore: settingsStore,
      launchAtLoginManager: launchAtLoginManager)

    viewModel.updateLaunchAtLoginEnabled(true)

    XCTAssertEqual(viewModel.activeAlert, .launchAtLogin(message: "mock enable failure"))
  }

  func testUpdateLaunchAtLoginEnabled_DisableThrows_ShowsGeneralErrorOnly() {
    let infoProvider = MockBatteryInfoProvider(result: .success(sampleInfo))
    let controller = MockBatteryController()
    let initial = BatterySettings(
      isLimitControlEnabled: false, chargeLimit: BatteryConstants.defaultChargeLimit,
      keepStateOnQuit: false,
      launchAtLoginEnabled: true)
    let settingsStore = MockBatterySettingsStore(initial: initial)
    let launchAtLoginManager = MockLaunchAtLoginManager(
      currentState: LaunchAtLoginState(isEnabled: true, message: nil))
    launchAtLoginManager.setEnabledHandler = { _ in
      throw MockLocalizedError(message: "mock disable failure")
    }
    let viewModel = makeViewModel(
      infoProvider: infoProvider, controller: controller, settingsStore: settingsStore,
      launchAtLoginManager: launchAtLoginManager)

    viewModel.updateLaunchAtLoginEnabled(false)

    XCTAssertEqual(viewModel.activeAlert, .operationFailure(message: "mock disable failure"))
  }

  func testUpdateChargeLimit_ValueAboveMax_ClampsAndPersists() {
    let infoProvider = MockBatteryInfoProvider(result: .success(sampleInfo))
    let controller = MockBatteryController()
    let settingsStore = MockBatterySettingsStore(initial: defaultSettings)
    let launchAtLoginManager = MockLaunchAtLoginManager()
    let viewModel = makeViewModel(
      infoProvider: infoProvider, controller: controller, settingsStore: settingsStore,
      launchAtLoginManager: launchAtLoginManager)

    viewModel.updateChargeLimit(999)

    XCTAssertEqual(viewModel.chargeLimit, BatteryConstants.maxChargeLimit)
    XCTAssertEqual(settingsStore.lastSaved?.chargeLimit, BatteryConstants.maxChargeLimit)
  }

  func testUpdateLimitControlEnabled_UpdatesStateAndPersists() {
    let infoProvider = MockBatteryInfoProvider(result: .success(sampleInfo))
    let controller = MockBatteryController()
    let settingsStore = MockBatterySettingsStore(initial: defaultSettings)
    let launchAtLoginManager = MockLaunchAtLoginManager()
    let viewModel = makeViewModel(
      infoProvider: infoProvider, controller: controller, settingsStore: settingsStore,
      launchAtLoginManager: launchAtLoginManager)

    viewModel.updateLimitControlEnabled(true)

    XCTAssertTrue(viewModel.isLimitControlEnabled)
    XCTAssertEqual(settingsStore.lastSaved?.isLimitControlEnabled, true)
  }

  func testRestoreSystemDefault_DisablesControlAndPersistsMaxLimit() {
    let infoProvider = MockBatteryInfoProvider(result: .success(sampleInfo))
    let controller = MockBatteryController()
    let launchAtLoginManager = MockLaunchAtLoginManager()
    let initial = BatterySettings(
      isLimitControlEnabled: true, chargeLimit: 60, keepStateOnQuit: false,
      launchAtLoginEnabled: false)
    let settingsStore = MockBatterySettingsStore(initial: initial)
    let viewModel = makeViewModel(
      infoProvider: infoProvider, controller: controller, settingsStore: settingsStore,
      launchAtLoginManager: launchAtLoginManager)

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
    let launchAtLoginManager = MockLaunchAtLoginManager()
    let viewModel = makeViewModel(
      infoProvider: infoProvider, controller: controller, settingsStore: settingsStore,
      launchAtLoginManager: launchAtLoginManager)

    viewModel.refreshNow()
    await waitUntil { viewModel.batteryInfo != nil }

    XCTAssertEqual(viewModel.batteryInfo, sampleInfo)
    XCTAssertNotNil(viewModel.lastUpdated)
    XCTAssertNil(viewModel.activeAlert)
  }

  func testRefreshNow_InfoFetchFailure_SetsErrorAlert() async {
    let infoProvider = MockBatteryInfoProvider(
      result: .failure(BatteryError.invalidPowerSourceData))
    let controller = MockBatteryController()
    let settingsStore = MockBatterySettingsStore(initial: defaultSettings)
    let launchAtLoginManager = MockLaunchAtLoginManager()
    let viewModel = makeViewModel(
      infoProvider: infoProvider, controller: controller, settingsStore: settingsStore,
      launchAtLoginManager: launchAtLoginManager)

    viewModel.refreshNow()
    await waitUntil { viewModel.activeAlert != nil }

    XCTAssertEqual(
      viewModel.activeAlert,
      .operationFailure(message: BatteryError.invalidPowerSourceData.localizedDescription))
  }

  private func makeViewModel(
    infoProvider: MockBatteryInfoProvider, controller: MockBatteryController,
    settingsStore: MockBatterySettingsStore, launchAtLoginManager: MockLaunchAtLoginManager
  ) -> BatteryViewModel {
    BatteryViewModel(
      infoProvider: infoProvider, controller: controller, settingsStore: settingsStore,
      policy: BatteryPolicy(hysteresisPercent: BatteryConstants.hysteresisPercent),
      monitor: BatteryPowerMonitor(), privilegeManager: SMCPrivilegeManager(),
      launchAtLoginManager: launchAtLoginManager)
  }

  private func waitUntil(timeout: TimeInterval = 1.0, condition: @escaping () -> Bool) async {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
      if condition() { return }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("等待异步状态更新超时")
  }

  private var defaultSettings: BatterySettings {
    BatterySettings(
      isLimitControlEnabled: false, chargeLimit: BatteryConstants.defaultChargeLimit,
      keepStateOnQuit: false,
      launchAtLoginEnabled: false)
  }

  private var sampleInfo: BatteryInfo {
    BatteryInfo(
      chargePercentage: 72, cycleCount: 123, powerSource: .adapter, chargeState: .charging)
  }
}

private final class MockBatterySettingsStore: BatterySettingsStoreProtocol {
  private var storage: BatterySettings
  private(set) var lastSaved: BatterySettings?

  init(initial: BatterySettings) { storage = initial }

  func load() -> BatterySettings { storage }

  func save(_ settings: BatterySettings) {
    storage = settings
    lastSaved = settings
  }
}

private struct MockBatteryInfoProvider: BatteryInfoProviderProtocol {
  let result: Result<BatteryInfo, Error>

  func fetchBatteryInfo() async throws -> BatteryInfo { try result.get() }
}

private final class MockBatteryController: BatteryControllerProtocol, @unchecked Sendable {
  let isSupported: Bool
  private(set) var appliedModes: [ChargingMode] = []

  init(isSupported: Bool = true) { self.isSupported = isSupported }

  func applyChargingMode(_ mode: ChargingMode) async throws { appliedModes.append(mode) }
}

private final class MockLaunchAtLoginManager: LaunchAtLoginManaging {
  var currentStateValue: LaunchAtLoginState
  var setEnabledHandler: ((Bool) throws -> LaunchAtLoginState)?

  init(currentState: LaunchAtLoginState = LaunchAtLoginState(isEnabled: false, message: nil)) {
    self.currentStateValue = currentState
  }

  func currentState() -> LaunchAtLoginState { currentStateValue }

  func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginState {
    if let setEnabledHandler {
      let state = try setEnabledHandler(enabled)
      currentStateValue = state
      return state
    }
    let state = LaunchAtLoginState(isEnabled: enabled, message: nil)
    currentStateValue = state
    return state
  }
}

private struct MockLocalizedError: LocalizedError {
  let message: String

  var errorDescription: String? { message }
}
