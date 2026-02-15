import Foundation

/// SMC 特权安装管理
final class SMCPrivilegeManager {
  // MARK: - Public

  func installHelper() throws {
    guard let scriptURL = SMCManualInstall.installScriptURL else {
      throw BatteryError.unknown("未找到安装脚本，请检查安装包是否完整或在项目根目录运行。")
    }

    try runInstallScript(scriptURL)
  }

  // MARK: - Private

  private func runInstallScript(_ scriptURL: URL) throws {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    let command = "/bin/bash \"\(scriptURL.path)\""
    let escapedCommand = command
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    task.arguments = [
      "-e",
      "do shell script \"\(escapedCommand)\" with administrator privileges",
    ]
    try task.run()
    task.waitUntilExit()
    if task.terminationStatus != 0 {
      throw BatteryError.permissionDenied
    }
  }
}
