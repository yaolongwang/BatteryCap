import Foundation

/// Helper 位置检测
enum SMCHelperLocator {
    static var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static func helperPaths() -> (executable: URL, plist: URL)? {
        guard isRunningFromAppBundle else {
            return nil
        }
        let bundleURL = Bundle.main.bundleURL
        let baseURL = bundleURL.appendingPathComponent("Contents/Library/LaunchServices", isDirectory: true)
        let executable = baseURL.appendingPathComponent(SMCHelperClient.machServiceName)
        let plist = baseURL.appendingPathComponent("\(SMCHelperClient.machServiceName).plist")
        return (executable, plist)
    }

    static var helperFilesExist: Bool {
        guard let paths = helperPaths() else {
            return false
        }
        return FileManager.default.fileExists(atPath: paths.executable.path)
            && FileManager.default.fileExists(atPath: paths.plist.path)
    }
}
