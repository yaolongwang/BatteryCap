import Foundation

// MARK: - SMC Write Status

/// SMC 写入状态
enum SMCWriteStatus: Equatable {
  case enabled
  case disabled(String)

  var isEnabled: Bool {
    switch self {
    case .enabled:
      return true
    case .disabled:
      return false
    }
  }

  var needsPrivilege: Bool {
    switch self {
    case .disabled(let reason):
      return privilegeKeywords.contains { reason.contains($0) }
    case .enabled:
      return false
    }
  }

  var message: String {
    switch self {
    case .enabled:
      return "已启用特权写入"
    case .disabled(let reason):
      return reason
    }
  }

  var hintMessage: String? {
    switch self {
    case .disabled(let reason):
      return reason
    case .enabled:
      return nil
    }
  }

  private var privilegeKeywords: [String] {
    Self.requiredPrivilegeKeywords
  }

  private static let requiredPrivilegeKeywords = ["管理员", "授权"]
}

/// 写入能力检测结果
enum SMCWriteCheckResult: Equatable {
  case supported
  case permissionDenied
  case keyNotFound
  case typeMismatch
  case smcUnavailable
  case unknown
}
