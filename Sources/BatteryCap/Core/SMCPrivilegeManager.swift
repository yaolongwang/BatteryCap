import Foundation

/// SMC 特权安装管理
final class SMCPrivilegeManager {
  func installHelper() throws {
    guard let scriptURL = SMCManualInstall.installScriptURL else {
      throw BatteryError.unknown("未找到安装脚本，请在项目根目录运行。")
    }

    try runInstallScript(scriptURL)
  }

  private func runInstallScript(_ scriptURL: URL) throws {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = [
      "-e",
      "do shell script \"\\(scriptURL.path)\" with administrator privileges",
    ]
    try task.run()
    task.waitUntilExit()
    if task.terminationStatus != 0 {
      throw BatteryError.permissionDenied
    }
  }
}
