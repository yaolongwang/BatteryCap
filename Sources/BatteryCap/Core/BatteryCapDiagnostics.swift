import Darwin
import Foundation
import IOKit

enum BatteryCapDiagnostics {
  // MARK: - Entry

  static var shouldRun: Bool {
    CommandLine.arguments.contains("--diagnose")
      || CommandLine.arguments.contains("--smc-diagnose")
      || ProcessInfo.processInfo.environment["BATTERYCAP_DIAG"] == "1"
  }

  static func run() {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    print("BatteryCap 诊断开始")
    print("时间: \(timestamp)")
    print("系统: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("机型: \(HardwareInfo.modelIdentifier ?? "未知")")
    print("架构: \(HardwareInfo.cpuArch ?? "未知")")
    print("进程参数: \(CommandLine.arguments.joined(separator: " "))")

    let settings = UserDefaultsBatterySettingsStore().load()
    print(
      "设置: 电量锁定=\(settings.isLimitControlEnabled), 最高电量=\(settings.chargeLimit)%, 退出保留=\(settings.keepStateOnQuit)"
    )

    let configuration = SMCConfiguration.load()
    print("SMC 写入开关: \(configuration.allowWrites ? "开启" : "关闭")")
    print("SMC 状态: \(configuration.status.message)")
    print("Helper 已安装: \(SMCHelperClient.isInstalled ? "是" : "否")")
    if let scriptURL = SMCManualInstall.helperServiceScriptURL {
      print("Helper 脚本: \(scriptURL.path)")
    } else {
      print("Helper 脚本: 未找到")
    }

    guard let chargingSwitch = configuration.chargingSwitch else {
      print("SMC 充电控制键: 未找到（无法诊断）")
      print("BatteryCap 诊断结束")
      return
    }

    let keys = chargingSwitch.keyNames.joined(separator: ", ")
    print("SMC 充电开关键: \(keys) / \(chargingSwitch.dataSize) 字节")

    let keyList = SMCClient.keyListReport()
    print("SMC Key 列表: 阶段=\(describe(keyList.stage))")
    print("SMC Key 列表: 返回=\(formatKernReturn(keyList.kernReturn))")
    print("SMC Key 列表: 总数=\(keyList.keyCount), 扫描=\(keyList.scannedCount)")
    if keyList.candidates.isEmpty {
      print("SMC Key 列表: 候选键=空")
    } else {
      let joined = keyList.candidates.joined(separator: ", ")
      print("SMC Key 列表: 候选键=\(joined)")
      print("候选键读取:")
      for key in keyList.candidates {
        let report = SMCClient.readKeyReport(key)
        printKeyReport(report)
      }
      if SMCHelperClient.isInstalled {
        runHelperCandidateReads(keys: keyList.candidates)
      }
    }

    let directResult = SMCClient.checkWriteAccess(chargingSwitch)
    print("直接写入检测: \(describe(directResult))")

    print("充电开关键读取:")
    for key in chargingSwitch.keyNames {
      let report = SMCClient.readKeyReport(key)
      printKeyReport(report)
    }
    if SMCHelperClient.isInstalled {
      runHelperCandidateReads(keys: chargingSwitch.keyNames)
      print("Helper 写入检测: 跳过（充电开关键会改变充电状态）")
      print("Helper 诊断: 跳过（充电开关键会改变充电状态）")
    } else {
      print("Helper 写入检测: 跳过（未安装）")
      print("Helper 诊断: 跳过（未安装）")
    }

    print("BatteryCap 诊断结束")
  }

  // MARK: - Helper Reads

  private static func runHelperCandidateReads(keys: [String]) {
    guard !keys.isEmpty else {
      return
    }
    let semaphore = DispatchSemaphore(value: 0)
    print("候选键读取（特权）:")
    Task {
      for key in keys {
        do {
          let report = try await SMCHelperClient().readKey(key)
          printHelperKeyReport(report)
        } catch {
          let message =
            (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
          print("  \(key): 失败 - \(message)")
        }
      }
      semaphore.signal()
    }

    if semaphore.wait(timeout: .now() + .seconds(15)) == .timedOut {
      print("候选键读取（特权）: 超时（15 秒）")
    }
  }

  // MARK: - Formatting

  private static func describe(_ result: SMCWriteCheckResult) -> String {
    switch result {
    case .supported:
      return "支持（可写）"
    case .permissionDenied:
      return "权限不足"
    case .keyNotFound:
      return "键不存在/不可写"
    case .typeMismatch:
      return "键类型不匹配"
    case .smcUnavailable:
      return "无法连接到 SMC"
    case .unknown:
      return "未知"
    }
  }

  private static func describe(_ stage: SMCKeyListStage) -> String {
    switch stage {
    case .ok:
      return "成功"
    case .serviceNotFound:
      return "未找到 AppleSMC 服务"
    case .serviceOpenFailed:
      return "打开服务失败"
    case .userClientOpenFailed:
      return "userClient 打开失败"
    case .keyCountFailed:
      return "读取 Key 总数失败"
    case .keyReadFailed:
      return "读取 Key 列表失败"
    case .unknown:
      return "未知"
    }
  }

  private static func describe(_ stage: SMCKeyReadStage) -> String {
    switch stage {
    case .ok:
      return "成功"
    case .invalidKey:
      return "键格式无效"
    case .serviceNotFound:
      return "未找到 AppleSMC 服务"
    case .serviceOpenFailed:
      return "打开服务失败"
    case .userClientOpenFailed:
      return "userClient 打开失败"
    case .keyInfoFailed:
      return "读取 KeyInfo 失败"
    case .keyInfoInvalid:
      return "KeyInfo 无效"
    case .readFailed:
      return "读取失败"
    }
  }

  private static func printKeyReport(_ report: SMCKeyReadReport) {
    print(
      "  \(report.key): stage=\(describe(report.stage)), return=\(formatKernReturn(report.kernReturn))"
    )
    let value = formatBytes(report.bytes, dataType: report.dataType)
    let suffix = report.truncated ? " (truncated)" : ""
    print(
      "    size=\(report.dataSize), type=\(formatDataType(report.dataType)), value=\(value)\(suffix)"
    )
  }

  private static func printHelperKeyReport(_ report: SMCHelperKeyReadReport) {
    print(
      "  \(report.key): stage=\(describe(report.stage)), return=\(formatKernReturn(report.kernReturn))"
    )
    let dataType = UInt32(bitPattern: report.dataType)
    let value = formatBytes(Array(report.bytes), dataType: dataType)
    let suffix = report.truncated ? " (truncated)" : ""
    print(
      "    size=\(report.dataSize), type=\(formatDataType(dataType)), value=\(value)\(suffix)"
    )
  }

  private static func describe(_ stage: SMCHelperKeyReadStage) -> String {
    switch stage {
    case .ok:
      return "成功"
    case .invalidKey:
      return "键格式无效"
    case .serviceNotFound:
      return "未找到 AppleSMC 服务"
    case .serviceOpenFailed:
      return "打开服务失败"
    case .userClientOpenFailed:
      return "userClient 打开失败"
    case .keyInfoFailed:
      return "读取 KeyInfo 失败"
    case .keyInfoInvalid:
      return "KeyInfo 无效"
    case .readFailed:
      return "读取失败"
    case .unknown:
      return "未知"
    }
  }

  private static func formatDataType(_ code: UInt32) -> String {
    guard code != 0 else {
      return "未知"
    }
    let bytes: [UInt8] = [
      UInt8((code >> 24) & 0xFF),
      UInt8((code >> 16) & 0xFF),
      UInt8((code >> 8) & 0xFF),
      UInt8(code & 0xFF),
    ]
    if let text = String(bytes: bytes, encoding: .ascii) {
      return "\(text) (0x\(String(format: "%08X", code)))"
    }
    return "0x\(String(format: "%08X", code))"
  }

  private static func formatBytes(_ bytes: [UInt8], dataType: UInt32) -> String {
    if bytes.isEmpty {
      return "空"
    }

    let hex = bytes.map { String(format: "%02X", $0) }.joined()
    if bytes.count == 1 {
      return "0x\(hex) (u8=\(bytes[0]))"
    }
    if bytes.count == 2 {
      let value = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
      return "0x\(hex) (u16=\(value))"
    }
    if bytes.count == 4 {
      let value =
        (UInt32(bytes[0]) << 24)
        | (UInt32(bytes[1]) << 16)
        | (UInt32(bytes[2]) << 8)
        | UInt32(bytes[3])
      return "0x\(hex) (u32=\(value))"
    }
    return "0x\(hex)"
  }

  private static func formatKernReturn(_ code: Int32) -> String {
    let name = kernName(code)
    let description = kernDescription(code)
    return "\(code) \(name) - \(description)"
  }

  private static func kernName(_ code: Int32) -> String {
    switch code {
    case KERN_SUCCESS:
      return "KERN_SUCCESS"
    case kIOReturnNotPrivileged:
      return "kIOReturnNotPrivileged"
    case kIOReturnNotPermitted:
      return "kIOReturnNotPermitted"
    case kIOReturnNotOpen:
      return "kIOReturnNotOpen"
    case kIOReturnNotFound:
      return "kIOReturnNotFound"
    case kIOReturnNoDevice:
      return "kIOReturnNoDevice"
    case kIOReturnUnsupported:
      return "kIOReturnUnsupported"
    case kIOReturnError:
      return "kIOReturnError"
    default:
      return "unknown"
    }
  }

  private static func kernDescription(_ code: Int32) -> String {
    guard let cString = mach_error_string(code) else {
      return "unknown"
    }
    return String(cString: cString)
  }
}

private enum HardwareInfo {
  static var modelIdentifier: String? {
    sysctlString("hw.model")
  }

  static var cpuArch: String? {
    sysctlString("hw.optional.arm64") == "1" ? "arm64" : sysctlString("hw.machine")
  }

  private static func sysctlString(_ name: String) -> String? {
    var size = 0
    if sysctlbyname(name, nil, &size, nil, 0) != 0 || size <= 0 {
      return nil
    }
    var data = [CChar](repeating: 0, count: size)
    if sysctlbyname(name, &data, &size, nil, 0) != 0 {
      return nil
    }
    let bytes = data.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(bytes: bytes, encoding: .utf8)
  }
}
