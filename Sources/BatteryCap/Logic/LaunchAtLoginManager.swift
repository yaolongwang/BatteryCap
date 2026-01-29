import Foundation
import ServiceManagement

struct LaunchAtLoginState: Sendable, Equatable {
  let isEnabled: Bool
  let message: String?
}

final class LaunchAtLoginManager: Sendable {
  static let shared = LaunchAtLoginManager()

  func currentState() -> LaunchAtLoginState {
    let status = SMAppService.mainApp.status
    return mapStatus(status)
  }

  func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginState {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
    return currentState()
  }

  private func mapStatus(_ status: SMAppService.Status) -> LaunchAtLoginState {
    switch status {
    case .enabled:
      return LaunchAtLoginState(isEnabled: true, message: nil)
    case .requiresApproval:
      return LaunchAtLoginState(
        isEnabled: true,
        message: "需要在“系统设置 → 登录项”中允许 BatteryCap。"
      )
    case .notRegistered:
      return LaunchAtLoginState(isEnabled: false, message: nil)
    case .notFound:
      return LaunchAtLoginState(
        isEnabled: false,
        message: "未找到应用。请将 BatteryCap 放入“应用程序”文件夹后再试。"
      )
    @unknown default:
      return LaunchAtLoginState(isEnabled: false, message: "开机自启动状态未知。")
    }
  }
}
