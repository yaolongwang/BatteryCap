import Foundation

// MARK: - Manual Install

/// 手动安装脚本定位
enum SMCManualInstall {
  static var helperServiceScriptURL: URL? {
    scriptURL(inProjectPath: "scripts/batterycap-service.sh", bundleResource: "batterycap-service")
  }

  private static func scriptURL(inProjectPath path: String, bundleResource: String) -> URL? {
    let fileManager = FileManager.default
    let cwd = FileManager.default.currentDirectoryPath
    let url = URL(fileURLWithPath: cwd).appendingPathComponent(path)
    if fileManager.fileExists(atPath: url.path) {
      return url
    }

    if let bundleURL = Bundle.main.url(forResource: bundleResource, withExtension: "sh") {
      return bundleURL
    }

    return nil
  }
}
