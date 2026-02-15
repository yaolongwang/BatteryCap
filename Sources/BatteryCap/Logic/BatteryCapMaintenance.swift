import Foundation

enum BatteryCapMaintenance {
  private static let disableControlsArgument = "--disable-controls-for-uninstall"

  static var shouldRun: Bool {
    CommandLine.arguments.contains(disableControlsArgument)
  }

  static func run() {
    var settings = UserDefaultsBatterySettingsStore().load()
    settings.isLimitControlEnabled = false
    settings.launchAtLoginEnabled = false
    UserDefaultsBatterySettingsStore().save(settings)

    do {
      _ = try LaunchAtLoginManager.shared.setEnabled(false)
      print("BatteryCap 维护: 已关闭电量锁定与开机自启动。")
    } catch {
      print("BatteryCap 维护: 已关闭电量锁定，但关闭开机自启动失败：\(error.localizedDescription)")
    }
  }
}
