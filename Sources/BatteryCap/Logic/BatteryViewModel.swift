import Foundation
import SwiftUI

enum BatteryAlert: Identifiable, Equatable {
  case operationFailure(message: String)
  case launchAtLogin(message: String)

  var id: String {
    switch self {
    case .operationFailure(let message): return "operationFailure:\(message)"
    case .launchAtLogin(let message): return "launchAtLogin:\(message)"
    }
  }

  var title: String {
    switch self {
    case .operationFailure: return "操作失败"
    case .launchAtLogin: return "开机自启动"
    }
  }

  var message: String {
    switch self {
    case .operationFailure(let message), .launchAtLogin(let message): return message
    }
  }
}

/// 电池视图模型
@MainActor final class BatteryViewModel: ObservableObject {
  // MARK: - Published State

  @Published private(set) var batteryInfo: BatteryInfo?
  @Published private(set) var lastUpdated: Date?
  @Published private(set) var isRefreshing: Bool = false
  @Published var isLimitControlEnabled: Bool
  @Published var chargeLimit: Int
  @Published var keepStateOnQuit: Bool
  @Published var isLaunchAtLoginEnabled: Bool
  @Published private(set) var activeAlert: BatteryAlert?
  @Published private(set) var smcStatus: SMCWriteStatus
  @Published private(set) var isHelperServiceInstalled: Bool

  // MARK: - Derived State

  var isControlSupported: Bool { smcStatus.isEnabled }

  var canRequestSmcWriteAccess: Bool { smcStatus.needsPrivilege && hasHelperServiceScript }

  var canInstallHelperService: Bool { hasHelperServiceScript }

  var canUninstallHelperService: Bool { hasHelperServiceScript }

  // MARK: - Dependencies

  nonisolated private let infoProvider: BatteryInfoProviderProtocol
  nonisolated private let controller: BatteryControllerProtocol
  private let settingsStore: BatterySettingsStoreProtocol
  private let policy: BatteryPolicy
  private let monitor: BatteryPowerMonitor
  private let privilegeManager: SMCPrivilegeManager
  private let launchAtLoginManager: LaunchAtLoginManaging
  private var lastAppliedMode: ChargingMode?
  private var refreshTimer: Timer?

  // MARK: - Initialization

  init(
    infoProvider: BatteryInfoProviderProtocol = IOKitBatteryInfoProvider(),
    controller: BatteryControllerProtocol = SMCBatteryController(),
    settingsStore: BatterySettingsStoreProtocol = UserDefaultsBatterySettingsStore(),
    policy: BatteryPolicy = BatteryPolicy.defaultPolicy(),
    monitor: BatteryPowerMonitor = BatteryPowerMonitor(),
    privilegeManager: SMCPrivilegeManager = SMCPrivilegeManager(),
    launchAtLoginManager: LaunchAtLoginManaging = LaunchAtLoginManager.shared
  ) {
    self.infoProvider = infoProvider
    self.controller = controller
    self.settingsStore = settingsStore
    self.policy = policy
    self.monitor = monitor
    self.privilegeManager = privilegeManager
    self.launchAtLoginManager = launchAtLoginManager

    let settings = settingsStore.load()
    self.isLimitControlEnabled = settings.isLimitControlEnabled
    self.chargeLimit = settings.chargeLimit
    self.keepStateOnQuit = settings.keepStateOnQuit
    let launchState = launchAtLoginManager.currentState()
    self.isLaunchAtLoginEnabled = launchState.isEnabled
    self.activeAlert = nil
    self.smcStatus = SMCConfiguration.load().status
    self.isHelperServiceInstalled = SMCHelperClient.isInstalled

    self.monitor.onPowerSourceChange = { [weak self] in self?.refreshNow() }
  }

  deinit {
    monitor.stop()
    Task { @MainActor [weak self] in self?.stopRefreshTimer() }
  }

  // MARK: - Lifecycle

  func start() {
    monitor.start()
    startRefreshTimer()
    refreshLaunchAtLoginState()
    refreshHelperServiceStatus()
    refreshNow()
  }

  // MARK: - User Actions

  func refreshNow() {
    Task { [weak self] in
      await self?.refresh()
      await MainActor.run { self?.refreshHelperServiceStatus() }
    }
  }

  func updateLimitControlEnabled(_ enabled: Bool) {
    isLimitControlEnabled = enabled
    persistAndApplyControl(force: true)
  }

  func updateChargeLimit(_ newValue: Int) {
    chargeLimit = BatteryConstants.clampChargeLimit(newValue)
    persistAndApplyControl(force: false)
  }

  func restoreSystemDefault() {
    isLimitControlEnabled = false
    chargeLimit = BatteryConstants.maxChargeLimit
    persistAndApplyMode(.normal, force: true)
  }

  func updateKeepStateOnQuit(_ enabled: Bool) {
    keepStateOnQuit = enabled
    persistSettings()
  }

  func updateLaunchAtLoginEnabled(_ enabled: Bool) {
    clearLaunchAtLoginAlertIfNeeded()
    do {
      let state = try launchAtLoginManager.setEnabled(enabled)
      applyLaunchAtLoginState(state, requestedEnabled: enabled)
      persistSettings()
    } catch {
      refreshLaunchAtLoginState()
      handleLaunchAtLoginUpdateError(error, requestedEnabled: enabled)
    }
  }

  func requestSmcWriteAccess() {
    Task { [weak self] in
      do {
        try self?.privilegeManager.installHelper()
        self?.handleHelperInstallSuccess()
      } catch { self?.handleHelperInstallFailure(error) }
    }
  }

  func uninstallHelperService() { Task { [weak self] in await self?.performHelperUninstall() } }

  func clearAlert() { activeAlert = nil }

  // MARK: - Core Logic

  private func refresh() async {
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      let info = try await infoProvider.fetchBatteryInfo()
      applyRefreshedBatteryInfo(info)
    } catch { handle(error) }
  }

  // MARK: - Settings & Control

  private func persistSettings() { settingsStore.save(currentSettings) }

  private func persistSettingsAndRefreshSmcStatus() {
    persistSettings()
    refreshSmcStatus()
  }

  private func persistAndApplyControl(force: Bool) {
    persistSettingsAndRefreshSmcStatus()
    applyControlIfNeeded(force: force)
  }

  private func persistAndApplyMode(_ mode: ChargingMode, force: Bool) {
    persistSettingsAndRefreshSmcStatus()
    applyModeIfNeeded(mode, force: force)
  }

  private func applyControlIfNeeded(force: Bool) {
    guard isControlSupported else { return }

    if !isLimitControlEnabled {
      applyModeIfNeeded(.normal, force: force)
      return
    }

    guard let info = batteryInfo else { return }

    let desiredMode = policy.desiredMode(
      currentCharge: info.chargePercentage, settings: currentSettings,
      lastAppliedMode: lastAppliedMode)
    applyModeIfNeeded(desiredMode, force: force)
  }

  private func applyModeIfNeeded(_ mode: ChargingMode, force: Bool) {
    if !force, let lastAppliedMode, lastAppliedMode == mode { return }

    Task { [weak self] in
      do {
        try await self?.controller.applyChargingMode(mode)
        await MainActor.run { self?.lastAppliedMode = mode }
      } catch { await MainActor.run { self?.handle(error) } }
    }
  }

  // MARK: - State Refresh

  private func refreshSmcStatus() { smcStatus = SMCConfiguration.load().status }

  private func refreshHelperServiceStatus() {
    isHelperServiceInstalled = SMCHelperClient.isInstalled
    if !isHelperServiceInstalled, isLimitControlEnabled {
      isLimitControlEnabled = false
      persistSettings()
    }
    refreshSmcStatus()
  }

  private func performHelperUninstall() async {
    await restoreNormalModeBeforeUninstallIfNeeded()

    do {
      try privilegeManager.uninstallHelper()
      refreshHelperServiceStatus()
    } catch {
      refreshHelperServiceStatus()
      handle(error)
    }
  }

  private func refreshLaunchAtLoginState() {
    let state = launchAtLoginManager.currentState()
    isLaunchAtLoginEnabled = state.isEnabled
  }

  private func applyLaunchAtLoginState(_ state: LaunchAtLoginState, requestedEnabled: Bool) {
    isLaunchAtLoginEnabled = state.isEnabled
    guard requestedEnabled else { return }
    activeAlert = launchAtLoginAlertForEnableResult(state)
  }

  private func handleLaunchAtLoginUpdateError(_ error: Error, requestedEnabled: Bool) {
    if requestedEnabled {
      activeAlert = .launchAtLogin(message: errorDescription(for: error))
      return
    }
    handle(error)
  }

  private func clearLaunchAtLoginAlertIfNeeded() {
    guard case .launchAtLogin = activeAlert else { return }
    activeAlert = nil
  }

  private func launchAtLoginAlertForEnableResult(_ state: LaunchAtLoginState) -> BatteryAlert? {
    if state.isEnabled {
      guard let message = state.message else { return nil }
      return .launchAtLogin(message: message)
    }
    return .launchAtLogin(message: state.message ?? "开启开机自启动失败，请重试。")
  }

  private var currentSettings: BatterySettings {
    BatterySettings(
      isLimitControlEnabled: isLimitControlEnabled,
      chargeLimit: BatteryConstants.clampChargeLimit(chargeLimit),
      keepStateOnQuit: keepStateOnQuit, launchAtLoginEnabled: isLaunchAtLoginEnabled)
  }

  private var hasHelperServiceScript: Bool { SMCManualInstall.helperServiceScriptURL != nil }

  // MARK: - Helpers

  private func applyRefreshedBatteryInfo(_ info: BatteryInfo) {
    batteryInfo = info
    lastUpdated = Date()
    refreshSmcStatus()
    applyControlIfNeeded(force: false)
  }

  private func handleHelperInstallSuccess() {
    refreshHelperServiceStatus()
    applyControlIfNeeded(force: true)
  }

  private func handleHelperInstallFailure(_ error: Error) {
    refreshHelperServiceStatus()
    guard !isHelperServiceInstalled else { return }
    handle(error)
  }

  private func restoreNormalModeBeforeUninstallIfNeeded() async {
    guard isControlSupported, isLimitControlEnabled else { return }

    do {
      try await controller.applyChargingMode(.normal)
      lastAppliedMode = .normal
    } catch { handle(error) }
  }

  private func handle(_ error: Error) {
    if shouldIgnoreControllerUnavailableError(error) {
      if case .operationFailure = activeAlert { activeAlert = nil }
      refreshHelperServiceStatus()
      return
    }
    activeAlert = .operationFailure(message: errorDescription(for: error))
  }

  private func shouldIgnoreControllerUnavailableError(_ error: Error) -> Bool {
    guard let batteryError = error as? BatteryError else { return false }
    if case .controllerUnavailable = batteryError { return true }
    return false
  }

  private func errorDescription(for error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
  }

  private func startRefreshTimer() {
    guard refreshTimer == nil else { return }
    let timer = Timer.scheduledTimer(
      withTimeInterval: BatteryConstants.refreshInterval, repeats: true
    ) {
      [weak self] _ in Task { @MainActor in self?.refreshNow() }
    }
    timer.tolerance = BatteryConstants.refreshTolerance
    refreshTimer = timer
  }

  private func stopRefreshTimer() {
    refreshTimer?.invalidate()
    refreshTimer = nil
  }
}
