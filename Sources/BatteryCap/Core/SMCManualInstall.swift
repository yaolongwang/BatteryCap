import Foundation

// MARK: - Manual Install

/// 手动安装脚本定位
enum SMCManualInstall {
  static var installScriptURL: URL? {
    let cwd = FileManager.default.currentDirectoryPath
    let url = URL(fileURLWithPath: cwd).appendingPathComponent("scripts/install-helper.sh")
    if FileManager.default.isExecutableFile(atPath: url.path) {
      return url
    }

    if let bundleURL = Bundle.main.url(forResource: "install-helper", withExtension: "sh") {
      return bundleURL
    }

    return nil
  }
}
