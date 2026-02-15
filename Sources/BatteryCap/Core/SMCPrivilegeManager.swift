import Foundation

/// SMC 特权安装管理
final class SMCPrivilegeManager {
  // MARK: - Public

  func installHelper() throws {
    guard let scriptURL = SMCManualInstall.installScriptURL else {
      throw BatteryError.unknown("未找到安装脚本，请检查安装包是否完整或在项目根目录运行。")
    }

    try runScript(scriptURL)
  }

  func uninstallHelper() throws {
    guard let scriptURL = SMCManualInstall.uninstallScriptURL else {
      throw BatteryError.unknown("未找到卸载脚本，请检查安装包是否完整或在项目根目录运行。")
    }

    try runScript(scriptURL)
  }

  // MARK: - Private

  private func runScript(_ scriptURL: URL) throws {
    let task = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.standardOutput = stdoutPipe
    task.standardError = stderrPipe
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
      let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      let scriptOutput = [stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                          stderr.trimmingCharacters(in: .whitespacesAndNewlines)]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

      if scriptOutput.localizedCaseInsensitiveContains("User canceled") {
        throw BatteryError.permissionDenied
      }

      if scriptOutput.isEmpty {
        throw BatteryError.unknown("脚本执行失败（退出码 \(task.terminationStatus)）。")
      }

      throw BatteryError.unknown("脚本执行失败（退出码 \(task.terminationStatus)）：\(scriptOutput)")
    }
  }
}
