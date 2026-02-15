import Foundation

/// SMC 特权安装管理
final class SMCPrivilegeManager {
  private static let missingScriptMessage = "未找到 Helper 服务脚本，请检查安装包是否完整或在项目根目录运行。"

  // MARK: - Public

  func installHelper() throws {
    try runScript(requireHelperScriptURL(), arguments: ["install"])
  }

  func uninstallHelper() throws {
    try runScript(requireHelperScriptURL(), arguments: ["uninstall"])
  }

  // MARK: - Private

  private func runScript(_ scriptURL: URL, arguments: [String]) throws {
    let task = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.standardOutput = stdoutPipe
    task.standardError = stderrPipe
    let quotedPath = shellQuote(scriptURL.path)
    let quotedArguments = arguments.map { shellQuote($0) }.joined(separator: " ")
    let command = quotedArguments.isEmpty
      ? "/bin/bash \(quotedPath)"
      : "/bin/bash \(quotedPath) \(quotedArguments)"
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

  private func requireHelperScriptURL() throws -> URL {
    guard let scriptURL = SMCManualInstall.helperServiceScriptURL else {
      throw BatteryError.unknown(Self.missingScriptMessage)
    }
    return scriptURL
  }

  private func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
  }
}
