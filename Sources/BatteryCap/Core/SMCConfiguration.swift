import Foundation

/// SMC 配置
struct SMCConfiguration: Sendable {
  let controlStrategy: SMCChargeControlStrategy?
  let allowWrites: Bool
  let status: SMCWriteStatus

  var isWritable: Bool {
    status == .enabledDirect
  }

  static func load(userDefaults: UserDefaults = .standard) -> SMCConfiguration {
    let allowWrites = userDefaults.object(forKey: SettingsKeys.allowSmcWrites) as? Bool ?? true
    let resolved = resolveStrategy()
    let status = resolveStatus(allowWrites: allowWrites, resolved: resolved)
    return SMCConfiguration(
      controlStrategy: resolved.strategy, allowWrites: allowWrites, status: status)
  }

  private static func resolveStrategy() -> SMCResolvedStrategy {
    let candidates = SMCKeys.chargeControlCandidates
    guard !candidates.isEmpty else {
      return SMCResolvedStrategy(strategy: nil, result: .keyNotFound)
    }

    var permissionDeniedStrategy: SMCChargeControlStrategy?
    for candidate in candidates {
      let result = SMCClient.checkWriteAccess(candidate)
      switch result {
      case .supported:
        return SMCResolvedStrategy(strategy: candidate, result: .supported)
      case .permissionDenied:
        if permissionDeniedStrategy == nil {
          permissionDeniedStrategy = candidate
        }
      case .smcUnavailable:
        return SMCResolvedStrategy(strategy: nil, result: .smcUnavailable)
      case .typeMismatch, .keyNotFound, .unknown:
        continue
      }
    }

    if let permissionDeniedStrategy {
      return SMCResolvedStrategy(
        strategy: permissionDeniedStrategy, result: .permissionDenied)
    }

    return SMCResolvedStrategy(strategy: nil, result: .keyNotFound)
  }

  private static func resolveStatus(
    allowWrites: Bool,
    resolved: SMCResolvedStrategy
  )
    -> SMCWriteStatus
  {
    guard allowWrites else {
      return .disabled("SMC 写入已关闭")
    }
    guard resolved.strategy != nil else {
      return .disabled("未找到可写的 SMC 键")
    }

    switch resolved.result {
    case .smcUnavailable:
      return .disabled("无法连接到 SMC")
    case .keyNotFound:
      return .disabled("SMC 键不存在或不可写")
    case .typeMismatch:
      return .disabled("SMC 键类型不匹配")
    case .supported, .permissionDenied, .unknown:
      if SMCHelperClient.isInstalled {
        return .enabledHelper
      }
      if resolved.result == .supported {
        return .enabledDirect
      }
      if resolved.result == .permissionDenied {
        return .disabled("需要管理员安装写入组件（运行 scripts/install-helper.sh）")
      }
      return .disabled("SMC 写入不可用")
    }
  }
}

private enum SettingsKeys {
  static let allowSmcWrites = "BatteryCap.allowSmcWrites"
}

private struct SMCResolvedStrategy: Sendable {
  let strategy: SMCChargeControlStrategy?
  let result: SMCWriteCheckResult
}
