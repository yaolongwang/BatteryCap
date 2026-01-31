import Foundation

/// 应用退出时的电池恢复逻辑
enum BatteryTerminationController {
  static func restoreIfNeeded() {
    let settings = UserDefaultsBatterySettingsStore().load()
    guard !settings.keepStateOnQuit else {
      return
    }

    let controller = SMCBatteryController(configuration: .load())
    guard controller.isSupported else {
      return
    }

    applyNormalModeWithTimeout(controller: controller)
  }

  private static func applyNormalModeWithTimeout(controller: SMCBatteryController) {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
      do {
        try await controller.applyChargingMode(.normal)
      } catch {
        // 退出阶段不阻塞用户，失败时直接忽略
      }
      semaphore.signal()
    }

    _ = semaphore.wait(timeout: .now() + .seconds(2))
  }
}
