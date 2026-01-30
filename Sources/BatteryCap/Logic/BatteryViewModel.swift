import Foundation
import SwiftUI

/// 电池视图模型
@MainActor
final class BatteryViewModel: ObservableObject {
  // MARK: - Published State

  @Published private(set) var batteryInfo: BatteryInfo?
  @Published private(set) var lastUpdated: Date?
  @Published private(set) var isRefreshing: Bool = false
  @Published var isLimitControlEnabled: Bool
  @Published var chargeLimit: Int
  @Published var keepStateOnQuit: Bool
  @Published var isLaunchAtLoginEnabled: Bool
  @Published private(set) var launchAtLoginMessage: String?
  @Published var errorMessage: String?
  @Published private(set) var smcStatus: SMCWriteStatus

  // MARK: - Derived State

  var isControlSupported: Bool {
    smcStatus.isEnabled
  }

  var canRequestSmcWriteAccess: Bool {
    smcStatus.needsPrivilege && SMCManualInstall.installScriptURL != nil
  }

  // MARK: - Dependencies

  nonisolated private let infoProvider: BatteryInfoProviderProtocol
  nonisolated private let controller: BatteryControllerProtocol
  private let settingsStore: BatterySettingsStoreProtocol
  private let policy: BatteryPolicy
  private let monitor: BatteryPowerMonitor
  private let privilegeManager: SMCPrivilegeManager
  private var lastAppliedMode: ChargingMode?
  private var refreshTimer: Timer?

  // MARK: - Initialization

  init(
    infoProvider: BatteryInfoProviderProtocol = IOKitBatteryInfoProvider(),
    controller: BatteryControllerProtocol = SMCBatteryController(),
    settingsStore: BatterySettingsStoreProtocol = UserDefaultsBatterySettingsStore(),
    policy: BatteryPolicy = BatteryPolicy(),
    monitor: BatteryPowerMonitor = BatteryPowerMonitor(),
    privilegeManager: SMCPrivilegeManager = SMCPrivilegeManager()
  ) {
    self.infoProvider = infoProvider
    self.controller = controller
    self.settingsStore = settingsStore
    self.policy = policy
    self.monitor = monitor
    self.privilegeManager = privilegeManager

    let settings = settingsStore.load()
    self.isLimitControlEnabled = settings.isLimitControlEnabled
    self.chargeLimit = settings.chargeLimit
    self.keepStateOnQuit = settings.keepStateOnQuit
    let launchState = LaunchAtLoginManager.shared.currentState()
    self.isLaunchAtLoginEnabled = launchState.isEnabled
    self.launchAtLoginMessage = launchState.message
    self.smcStatus = SMCConfiguration.load().status

    self.monitor.onPowerSourceChange = { [weak self] in
      self?.refreshNow()
    }
  }

  deinit {
    monitor.stop()
    Task { @MainActor [weak self] in
      self?.stopRefreshTimer()
    }
  }

  // MARK: - Lifecycle

  func start() {
    monitor.start()
    startRefreshTimer()
    refreshLaunchAtLoginState()
    refreshNow()
  }

  // MARK: - User Actions

  func refreshNow() {
    Task { [weak self] in
      await self?.refresh()
    }
  }

  func updateLimitControlEnabled(_ enabled: Bool) {
    isLimitControlEnabled = enabled
    persistSettings()
    refreshSmcStatus()
    applyControlIfNeeded(force: true)
  }

  func updateChargeLimit(_ newValue: Int) {
    chargeLimit = clampLimit(newValue)
    persistSettings()
    refreshSmcStatus()
    applyControlIfNeeded(force: false)
  }

  func restoreSystemDefault() {
    isLimitControlEnabled = false
    chargeLimit = BatteryConstants.maxChargeLimit
    persistSettings()
    refreshSmcStatus()
    applyModeIfNeeded(.normal, force: true)
  }

  func updateKeepStateOnQuit(_ enabled: Bool) {
    keepStateOnQuit = enabled
    persistSettings()
  }

  func updateLaunchAtLoginEnabled(_ enabled: Bool) {
    do {
      let state = try LaunchAtLoginManager.shared.setEnabled(enabled)
      isLaunchAtLoginEnabled = state.isEnabled
      launchAtLoginMessage = state.message
      persistSettings()
    } catch {
      refreshLaunchAtLoginState()
      handle(error)
    }
  }

  func requestSmcWriteAccess() {
    Task { [weak self] in
      do {
        try self?.privilegeManager.installHelper()
        self?.refreshSmcStatus()
      } catch {
        self?.handle(error)
      }
    }
  }

  func clearError() {
    errorMessage = nil
  }

  // MARK: - Core Logic

  private func refresh() async {
    isRefreshing = true
    defer {
      isRefreshing = false
    }

    do {
      let info = try await infoProvider.fetchBatteryInfo()
      batteryInfo = info
      lastUpdated = Date()
      refreshSmcStatus()
      applyControlIfNeeded(force: false)
    } catch {
      handle(error)
    }
  }

  // MARK: - Settings & Control

  private func persistSettings() {
    let settings = BatterySettings(
      isLimitControlEnabled: isLimitControlEnabled,
      chargeLimit: clampLimit(chargeLimit),
      keepStateOnQuit: keepStateOnQuit,
      launchAtLoginEnabled: isLaunchAtLoginEnabled
    )
    settingsStore.save(settings)
  }

  private func applyControlIfNeeded(force: Bool) {
    guard isControlSupported else {
      return
    }

    if !isLimitControlEnabled {
      applyModeIfNeeded(.normal, force: force)
      return
    }

    guard let info = batteryInfo else {
      return
    }

    let desiredMode = policy.desiredMode(
      currentCharge: info.chargePercentage, settings: currentSettings)
    applyModeIfNeeded(desiredMode, force: force)
  }

  private func applyModeIfNeeded(_ mode: ChargingMode, force: Bool) {
    if !force, let lastAppliedMode, lastAppliedMode == mode {
      return
    }

    lastAppliedMode = mode

    Task { [weak self] in
      do {
        try await self?.controller.applyChargingMode(mode)
      } catch {
        self?.handle(error)
      }
    }
  }

  // MARK: - State Refresh

  private func refreshSmcStatus() {
    smcStatus = SMCConfiguration.load().status
  }

  private func refreshLaunchAtLoginState() {
    let state = LaunchAtLoginManager.shared.currentState()
    isLaunchAtLoginEnabled = state.isEnabled
    launchAtLoginMessage = state.message
  }

  private var currentSettings: BatterySettings {
    BatterySettings(
      isLimitControlEnabled: isLimitControlEnabled,
      chargeLimit: clampLimit(chargeLimit),
      keepStateOnQuit: keepStateOnQuit,
      launchAtLoginEnabled: isLaunchAtLoginEnabled
    )
  }

  // MARK: - Helpers

  private func clampLimit(_ value: Int) -> Int {
    min(max(value, BatteryConstants.minChargeLimit), BatteryConstants.maxChargeLimit)
  }

  private func handle(_ error: Error) {
    if let batteryError = error as? BatteryError {
      errorMessage = batteryError.localizedDescription
    } else {
      errorMessage = error.localizedDescription
    }
  }

  private func startRefreshTimer() {
    guard refreshTimer == nil else {
      return
    }
    let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.refreshNow()
      }
    }
    timer.tolerance = 5
    refreshTimer = timer
  }

  private func stopRefreshTimer() {
    refreshTimer?.invalidate()
    refreshTimer = nil
  }
}
