import Foundation

/// SMC 配置
struct SMCConfiguration: Sendable {
  let chargingSwitch: SMCChargingSwitch?
  let allowWrites: Bool
  let status: SMCWriteStatus

  // MARK: - Factory

  static func load(userDefaults: UserDefaults = .standard) -> SMCConfiguration {
    let allowWrites = userDefaults.object(forKey: DefaultsKeys.allowSmcWrites) as? Bool ?? true
    let resolved = resolveChargingSwitch()
    let status = resolveStatus(allowWrites: allowWrites, resolved: resolved)
    return SMCConfiguration(
      chargingSwitch: resolved.chargingSwitch, allowWrites: allowWrites, status: status)
  }

  // MARK: - Resolution

  private static func resolveChargingSwitch() -> SMCResolvedSwitch {
    let candidates = SMCKeys.chargingSwitchCandidates
    guard !candidates.isEmpty else {
      return SMCResolvedSwitch(chargingSwitch: nil, result: .keyNotFound)
    }

    var permissionDeniedSwitch: SMCChargingSwitch?
    for candidate in candidates {
      let result = SMCClient.checkWriteAccess(candidate)
      switch result {
      case .supported:
        return SMCResolvedSwitch(chargingSwitch: candidate, result: .supported)
      case .permissionDenied:
        if permissionDeniedSwitch == nil {
          permissionDeniedSwitch = candidate
        }
      case .smcUnavailable:
        return SMCResolvedSwitch(chargingSwitch: nil, result: .smcUnavailable)
      case .typeMismatch, .keyNotFound, .unknown:
        continue
      }
    }

    if let permissionDeniedSwitch {
      return SMCResolvedSwitch(
        chargingSwitch: permissionDeniedSwitch, result: .permissionDenied)
    }

    return SMCResolvedSwitch(chargingSwitch: nil, result: .keyNotFound)
  }

  private static func resolveStatus(
    allowWrites: Bool,
    resolved: SMCResolvedSwitch
  )
    -> SMCWriteStatus
  {
    guard allowWrites else {
      return .disabled("SMC 写入已关闭")
    }
    guard resolved.chargingSwitch != nil else {
      return .disabled("未找到可写的 SMC 键")
    }
    if !SMCHelperClient.isInstalled {
      return .disabled("需要管理员安装写入组件（点击“授权写入”或运行 scripts/install-helper.sh）")
    }

    switch resolved.result {
    case .smcUnavailable:
      return .disabled("无法连接到 SMC")
    case .keyNotFound:
      return .disabled("SMC 键不存在或不可写")
    case .typeMismatch:
      return .disabled("SMC 键类型不匹配")
    case .supported, .permissionDenied, .unknown:
      return .enabled
    }
  }
}

private enum DefaultsKeys {
  static let allowSmcWrites = "BatteryCap.allowSmcWrites"
}

private struct SMCResolvedSwitch: Sendable {
  let chargingSwitch: SMCChargingSwitch?
  let result: SMCWriteCheckResult
}
