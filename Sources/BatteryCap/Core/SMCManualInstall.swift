import Foundation

// MARK: - Manual Install

/// 手动安装脚本定位
enum SMCManualInstall {
  static var installScriptURL: URL? {
    let cwd = FileManager.default.currentDirectoryPath
    let url = URL(fileURLWithPath: cwd).appendingPathComponent("scripts/install-helper.sh")
    guard FileManager.default.isExecutableFile(atPath: url.path) else {
      return nil
    }
    return url
  }
}
