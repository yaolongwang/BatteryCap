import Foundation

enum BatteryCapMaintenance {
  private static let disableControlsArgument = "--disable-controls-for-uninstall"

  static var shouldRun: Bool {
    shouldRun(arguments: CommandLine.arguments)
  }

  static func shouldRun(arguments: [String]) -> Bool {
    arguments.contains(disableControlsArgument)
  }

  static func run() {
    let settingsStore = UserDefaultsBatterySettingsStore()
    var settings = settingsStore.load()
    settings.isLimitControlEnabled = false
    settings.launchAtLoginEnabled = false
    settingsStore.save(settings)

    do {
      _ = try LaunchAtLoginManager.shared.setEnabled(false)
      print("BatteryCap 维护: 已关闭电量锁定与开机自启动。")
    } catch {
      print("BatteryCap 维护: 已关闭电量锁定，但关闭开机自启动失败：\(error.localizedDescription)")
    }
  }
}
