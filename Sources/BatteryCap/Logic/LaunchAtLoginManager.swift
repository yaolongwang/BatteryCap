import Foundation
import ServiceManagement

protocol LaunchAtLoginManaging {
  func currentState() -> LaunchAtLoginState
  func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginState
}

/// 开机自启动状态
struct LaunchAtLoginState: Sendable, Equatable {
  let isEnabled: Bool
  let message: String?
}

/// 开机自启动管理
final class LaunchAtLoginManager: Sendable, LaunchAtLoginManaging {
  static let shared = LaunchAtLoginManager()
  private static let notFoundMessage = "系统未找到开机自启动注册项，请重试或重启应用后再试。"

  // MARK: - Public

  func currentState() -> LaunchAtLoginState { mapStatus(SMAppService.mainApp.status) }

  func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginState {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
    return currentState()
  }

  // MARK: - Private

  private func mapStatus(_ status: SMAppService.Status) -> LaunchAtLoginState {
    switch status {
    case .enabled: return state(enabled: true)
    case .requiresApproval: return state(enabled: true, message: "需要在“系统设置 → 登录项”中允许 BatteryCap。")
    case .notRegistered: return state(enabled: false)
    case .notFound: return state(enabled: false, message: Self.notFoundMessage)
    @unknown default: return state(enabled: false, message: "开机自启动状态未知。")
    }
  }

  private func state(enabled: Bool, message: String? = nil) -> LaunchAtLoginState {
    LaunchAtLoginState(isEnabled: enabled, message: message)
  }
}
