import Foundation
import SwiftUI

/// 电池视图模型
@MainActor
final class BatteryViewModel: ObservableObject {
    @Published private(set) var batteryInfo: BatteryInfo?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing: Bool = false
    @Published var isLimitControlEnabled: Bool
    @Published var chargeLimit: Int
    @Published var errorMessage: String?

    let isControlSupported: Bool

    nonisolated private let infoProvider: BatteryInfoProviderProtocol
    nonisolated private let controller: BatteryControllerProtocol
    private let settingsStore: BatterySettingsStoreProtocol
    private let policy: BatteryPolicy
    private var refreshTask: Task<Void, Never>?
    private var lastAppliedMode: ChargingMode?

    init(
        infoProvider: BatteryInfoProviderProtocol = IOKitBatteryInfoProvider(),
        controller: BatteryControllerProtocol = SMCBatteryController(),
        settingsStore: BatterySettingsStoreProtocol = UserDefaultsBatterySettingsStore(),
        policy: BatteryPolicy = BatteryPolicy()
    ) {
        self.infoProvider = infoProvider
        self.controller = controller
        self.settingsStore = settingsStore
        self.policy = policy

        let settings = settingsStore.load()
        self.isLimitControlEnabled = settings.isLimitControlEnabled
        self.chargeLimit = settings.chargeLimit
        self.isControlSupported = controller.isSupported
    }

    deinit {
        refreshTask?.cancel()
    }

    func start() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(nanoseconds: BatteryConstants.refreshIntervalNanoseconds)
            }
        }
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.refresh()
        }
    }

    func updateLimitControlEnabled(_ enabled: Bool) {
        isLimitControlEnabled = enabled
        persistSettings()
        applyControlIfNeeded(force: true)
    }

    func updateChargeLimit(_ newValue: Int) {
        chargeLimit = clampLimit(newValue)
        persistSettings()
        applyControlIfNeeded(force: false)
    }

    func clearError() {
        errorMessage = nil
    }

    private func refresh() async {
        isRefreshing = true
        defer {
            isRefreshing = false
        }

        do {
            let info = try await infoProvider.fetchBatteryInfo()
            batteryInfo = info
            lastUpdated = Date()
            applyControlIfNeeded(force: false)
        } catch {
            handle(error)
        }
    }

    private func persistSettings() {
        let settings = BatterySettings(
            isLimitControlEnabled: isLimitControlEnabled,
            chargeLimit: clampLimit(chargeLimit)
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

    private var currentSettings: BatterySettings {
        BatterySettings(
            isLimitControlEnabled: isLimitControlEnabled,
            chargeLimit: clampLimit(chargeLimit)
        )
    }

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
}
