import Foundation
import IOKit

/// SMC 客户端（简化写入）
final class SMCClient {
  // MARK: - State

  private var connection: io_connect_t = 0
  private var isClosed = false

  // MARK: - Lifecycle

  init() throws {
    try open()
  }

  deinit {
    close()
  }

  // MARK: - Write

  func writeBytes(_ bytes: [UInt8], to keyDefinition: SMCKeyDefinition) throws {
    let keyInfo = try validatedKeyInfo(for: keyDefinition)
    guard bytes.count == keyDefinition.dataSize else {
      throw BatteryError.smcTypeMismatch
    }

    var input = SMCKeyData()
    input.key = keyDefinition.key.code
    input.data8 = SMCCommand.writeKey
    input.keyInfo.dataSize = UInt32(keyInfo.dataSize)

    withUnsafeMutableBytes(of: &input.bytes) { rawBytes in
      for index in 0..<rawBytes.count {
        rawBytes[index] = 0
      }
      for (index, byte) in bytes.enumerated() where index < rawBytes.count {
        rawBytes[index] = byte
      }
    }

    _ = try call(&input)
  }

  // MARK: - Access Check

  static func checkWriteAccess(_ chargingSwitch: SMCChargingSwitch) -> SMCWriteCheckResult {
    do {
      let client = try SMCClient()
      try client.validate(chargingSwitch)
      return .supported
    } catch let error as BatteryError {
      switch error {
      case .permissionDenied:
        return .permissionDenied
      case .smcKeyNotFound:
        return .keyNotFound
      case .smcTypeMismatch:
        return .typeMismatch
      case .smcUnavailable:
        return .smcUnavailable
      default:
        return .unknown
      }
    } catch {
      return .unknown
    }
  }

  // MARK: - Private Validation

  private func validate(_ keyDefinition: SMCKeyDefinition) throws {
    _ = try validatedKeyInfo(for: keyDefinition)
  }

  private func validatedKeyInfo(for keyDefinition: SMCKeyDefinition) throws -> SMCKeyInfo {
    let keyInfo = try getKeyInfo(for: keyDefinition.key)
    guard keyInfo.dataSize == keyDefinition.dataSize else {
      throw BatteryError.smcTypeMismatch
    }
    if let expectedType = keyDefinition.dataType, expectedType.code != keyInfo.dataType {
      throw BatteryError.smcTypeMismatch
    }
    return keyInfo
  }

  private func validate(_ chargingSwitch: SMCChargingSwitch) throws {
    guard !chargingSwitch.keys.isEmpty else {
      throw BatteryError.smcKeyNotFound
    }
    for keyDefinition in chargingSwitch.keys {
      try validate(keyDefinition)
    }
    guard chargingSwitch.dataSize == chargingSwitch.enableBytes.count,
      chargingSwitch.dataSize == chargingSwitch.disableBytes.count
    else {
      throw BatteryError.smcTypeMismatch
    }
  }

  // MARK: - Connection

  private func open() throws {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault,
      IOServiceMatching(SMCService.name)
    )
    guard service != 0 else {
      throw BatteryError.smcUnavailable
    }
    defer {
      IOObjectRelease(service)
    }

    var openedConnection: io_connect_t = 0
    let openResult = IOServiceOpen(service, mach_task_self_, 0, &openedConnection)
    guard openResult == KERN_SUCCESS else {
      throw mapReturn(openResult)
    }

    connection = openedConnection

    let openCallResult = IOConnectCallStructMethod(
      connection,
      SMCCommand.userClientOpen,
      nil,
      0,
      nil,
      nil
    )

    guard openCallResult == KERN_SUCCESS else {
      close()
      throw mapReturn(openCallResult)
    }
  }

  private func close() {
    guard !isClosed else {
      return
    }
    isClosed = true

    if connection != 0 {
      _ = IOConnectCallStructMethod(connection, SMCCommand.userClientClose, nil, 0, nil, nil)
      IOServiceClose(connection)
      connection = 0
    }
  }

  // MARK: - Key Info

  private func getKeyInfo(for key: SMCKey) throws -> SMCKeyInfo {
    var input = SMCKeyData()
    input.key = key.code
    input.data8 = SMCCommand.getKeyInfo

    let output = try call(&input)

    let dataSize = Int(output.keyInfo.dataSize)
    guard dataSize > 0 else {
      throw BatteryError.smcKeyNotFound
    }

    return SMCKeyInfo(dataSize: dataSize, dataType: output.keyInfo.dataType)
  }

  // MARK: - IO Call

  private func call(_ input: inout SMCKeyData) throws -> SMCKeyData {
    var output = SMCKeyData()
    var outputSize = MemoryLayout<SMCKeyData>.size

    let result = IOConnectCallStructMethod(
      connection,
      SMCCommand.handleYPCEvent,
      &input,
      MemoryLayout<SMCKeyData>.size,
      &output,
      &outputSize
    )

    guard result == KERN_SUCCESS else {
      throw mapReturn(result)
    }

    return output
  }

  // MARK: - Error Mapping

  private func mapReturn(_ result: kern_return_t) -> BatteryError {
    switch result {
    case kIOReturnNotPrivileged, kIOReturnNotPermitted:
      return .permissionDenied
    case kIOReturnNoDevice:
      return .smcUnavailable
    default:
      return .smcWriteFailed
    }
  }
}

struct SMCKeyListReport {
  let stage: SMCKeyListStage
  let kernReturn: kern_return_t
  let keyCount: Int
  let scannedCount: Int
  let candidates: [String]
}

enum SMCKeyListStage: Int32 {
  case ok = 0
  case serviceNotFound = 1
  case serviceOpenFailed = 2
  case userClientOpenFailed = 3
  case keyCountFailed = 4
  case keyReadFailed = 5
  case unknown = 99
}

struct SMCKeyReadReport {
  let key: String
  let stage: SMCKeyReadStage
  let kernReturn: kern_return_t
  let dataSize: Int
  let dataType: UInt32
  let bytes: [UInt8]
  let truncated: Bool
}

enum SMCKeyReadStage: Int32 {
  case ok = 0
  case invalidKey = 1
  case serviceNotFound = 2
  case serviceOpenFailed = 3
  case userClientOpenFailed = 4
  case keyInfoFailed = 5
  case keyInfoInvalid = 6
  case readFailed = 7
}

// MARK: - Diagnostics

extension SMCClient {
  static func keyListReport(maxKeys: Int? = nil) -> SMCKeyListReport {
    let result = withDiagnosticConnection { connection in
      guard let keyCount = readKeyCount(connection: connection) else {
        return makeKeyListReport(stage: .keyCountFailed)
      }

      let scanLimit = min(maxKeys ?? keyCount, keyCount)
      var candidates: [String] = []
      candidates.reserveCapacity(64)

      for index in 0..<scanLimit {
        guard let key = readKeyAtIndex(connection: connection, index: index) else {
          return makeKeyListReport(
            stage: .keyReadFailed,
            keyCount: keyCount,
            scannedCount: index,
            candidates: candidates
          )
        }

        if candidateKeywords.contains(where: { key.contains($0) }) {
          candidates.append(key)
        }
      }

      let trimmedCandidates = candidates.count > 120 ? Array(candidates.prefix(120)) : candidates
      return makeKeyListReport(
        stage: .ok,
        keyCount: keyCount,
        scannedCount: scanLimit,
        candidates: trimmedCandidates
      )
    }
    return makeKeyListReport(from: result)
  }

  static func readKeyReport(_ keyName: String) -> SMCKeyReadReport {
    guard let key = try? SMCKey(keyName) else {
      return makeKeyReadReport(key: keyName, stage: .invalidKey, kernReturn: KERN_FAILURE)
    }

    let result = withDiagnosticConnection { connection in
      var keyInfoInput = SMCKeyData()
      keyInfoInput.key = key.code
      keyInfoInput.data8 = SMCCommand.getKeyInfo

      let keyInfoCall = call(connection: connection, input: &keyInfoInput)
      guard keyInfoCall.result == KERN_SUCCESS else {
        return makeKeyReadReport(
          key: keyName,
          stage: .keyInfoFailed,
          kernReturn: keyInfoCall.result
        )
      }

      let dataSize = Int(keyInfoCall.output.keyInfo.dataSize)
      let dataType = keyInfoCall.output.keyInfo.dataType
      guard dataSize > 0 else {
        return makeKeyReadReport(
          key: keyName,
          stage: .keyInfoInvalid,
          dataType: dataType
        )
      }

      var readInput = SMCKeyData()
      readInput.key = key.code
      readInput.data8 = SMCCommand.readKey
      readInput.keyInfo.dataSize = UInt32(dataSize)

      let readCall = call(connection: connection, input: &readInput)
      guard readCall.result == KERN_SUCCESS else {
        return makeKeyReadReport(
          key: keyName,
          stage: .readFailed,
          kernReturn: readCall.result,
          dataSize: dataSize,
          dataType: dataType
        )
      }

      let maxBytes = min(dataSize, 32)
      var bytesSource = readCall.output.bytes
      let bytes = extractBytes(from: &bytesSource, count: maxBytes)

      return makeKeyReadReport(
        key: keyName,
        stage: .ok,
        dataSize: dataSize,
        dataType: dataType,
        bytes: bytes,
        truncated: dataSize > 32
      )
    }
    return makeKeyReadReport(key: keyName, from: result)
  }

  private static func makeKeyListReport(
    stage: SMCKeyListStage,
    kernReturn: kern_return_t = KERN_SUCCESS,
    keyCount: Int = 0,
    scannedCount: Int = 0,
    candidates: [String] = []
  ) -> SMCKeyListReport {
    SMCKeyListReport(
      stage: stage,
      kernReturn: kernReturn,
      keyCount: keyCount,
      scannedCount: scannedCount,
      candidates: candidates
    )
  }

  private static func makeKeyListReport(
    from result: SMCDiagnosticConnectionResult<SMCKeyListReport>
  ) -> SMCKeyListReport {
    switch result {
    case .success(let report):
      return report
    case .serviceNotFound:
      return makeKeyListReport(stage: .serviceNotFound, kernReturn: kIOReturnNoDevice)
    case .serviceOpenFailed(let openResult):
      return makeKeyListReport(stage: .serviceOpenFailed, kernReturn: openResult)
    case .userClientOpenFailed(let openCallResult):
      return makeKeyListReport(stage: .userClientOpenFailed, kernReturn: openCallResult)
    }
  }

  private static func makeKeyReadReport(
    key: String,
    stage: SMCKeyReadStage,
    kernReturn: kern_return_t = KERN_SUCCESS,
    dataSize: Int = 0,
    dataType: UInt32 = 0,
    bytes: [UInt8] = [],
    truncated: Bool = false
  ) -> SMCKeyReadReport {
    SMCKeyReadReport(
      key: key,
      stage: stage,
      kernReturn: kernReturn,
      dataSize: dataSize,
      dataType: dataType,
      bytes: bytes,
      truncated: truncated
    )
  }

  private static func makeKeyReadReport(
    key: String,
    from result: SMCDiagnosticConnectionResult<SMCKeyReadReport>
  ) -> SMCKeyReadReport {
    switch result {
    case .success(let report):
      return report
    case .serviceNotFound:
      return makeKeyReadReport(key: key, stage: .serviceNotFound, kernReturn: kIOReturnNoDevice)
    case .serviceOpenFailed(let openResult):
      return makeKeyReadReport(key: key, stage: .serviceOpenFailed, kernReturn: openResult)
    case .userClientOpenFailed(let openCallResult):
      return makeKeyReadReport(key: key, stage: .userClientOpenFailed, kernReturn: openCallResult)
    }
  }

  private static func readKeyCount(connection: io_connect_t) -> Int? {
    if let count = readKeyCount(connection: connection, keyName: "#KEY") {
      return count
    }
    if let count = readKeyCount(connection: connection, keyName: "NKEY") {
      return count
    }
    return nil
  }

  private static func readKeyCount(connection: io_connect_t, keyName: String) -> Int? {
    guard let key = try? SMCKey(keyName) else {
      return nil
    }

    var keyInfoInput = SMCKeyData()
    keyInfoInput.key = key.code
    keyInfoInput.data8 = SMCCommand.getKeyInfo

    let keyInfoCall = call(connection: connection, input: &keyInfoInput)
    guard keyInfoCall.result == KERN_SUCCESS else {
      return nil
    }

    let dataSize = Int(keyInfoCall.output.keyInfo.dataSize)
    guard dataSize >= 4 else {
      return nil
    }

    var readInput = SMCKeyData()
    readInput.key = key.code
    readInput.data8 = SMCCommand.readKey
    readInput.keyInfo.dataSize = UInt32(dataSize)

    let readCall = call(connection: connection, input: &readInput)
    guard readCall.result == KERN_SUCCESS else {
      return nil
    }

    var bytesSource = readCall.output.bytes
    let bytes = extractBytes(from: &bytesSource, count: 4)
    guard bytes.count == 4 else {
      return nil
    }

    let value =
      (UInt32(bytes[0]) << 24)
      | (UInt32(bytes[1]) << 16)
      | (UInt32(bytes[2]) << 8)
      | UInt32(bytes[3])
    return Int(value)
  }

  private static func readKeyAtIndex(connection: io_connect_t, index: Int) -> String? {
    var input = SMCKeyData()
    input.data8 = SMCCommand.getKeyByIndex
    input.data32 = UInt32(index)

    let result = call(connection: connection, input: &input)
    guard result.result == KERN_SUCCESS else {
      return nil
    }

    return smcKeyString(from: result.output.key)
  }

  private static func smcKeyString(from code: UInt32) -> String? {
    let bytes: [UInt8] = [
      UInt8((code >> 24) & 0xFF),
      UInt8((code >> 16) & 0xFF),
      UInt8((code >> 8) & 0xFF),
      UInt8(code & 0xFF),
    ]
    return String(bytes: bytes, encoding: .ascii)
  }

  private static func withDiagnosticConnection<T>(
    _ body: (io_connect_t) -> T
  ) -> SMCDiagnosticConnectionResult<T> {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault,
      IOServiceMatching(SMCService.name)
    )
    guard service != 0 else {
      return .serviceNotFound
    }
    defer {
      IOObjectRelease(service)
    }

    var connection: io_connect_t = 0
    let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
    guard openResult == KERN_SUCCESS else {
      return .serviceOpenFailed(openResult)
    }
    defer {
      _ = IOConnectCallStructMethod(connection, SMCCommand.userClientClose, nil, 0, nil, nil)
      IOServiceClose(connection)
    }

    let openCallResult = IOConnectCallStructMethod(
      connection,
      SMCCommand.userClientOpen,
      nil,
      0,
      nil,
      nil
    )
    guard openCallResult == KERN_SUCCESS else {
      return .userClientOpenFailed(openCallResult)
    }

    return .success(body(connection))
  }

  private static func extractBytes(from source: inout SMCBytes, count: Int) -> [UInt8] {
    let cappedCount = min(max(count, 0), MemoryLayout<SMCBytes>.size)
    var bytes: [UInt8] = []
    bytes.reserveCapacity(cappedCount)
    withUnsafeBytes(of: &source) { raw in
      for index in 0..<min(cappedCount, raw.count) {
        bytes.append(raw[index])
      }
    }
    return bytes
  }

  private static func call(
    connection: io_connect_t,
    input: inout SMCKeyData
  ) -> (result: kern_return_t, output: SMCKeyData) {
    var output = SMCKeyData()
    var outputSize = MemoryLayout<SMCKeyData>.size
    let result = IOConnectCallStructMethod(
      connection,
      SMCCommand.handleYPCEvent,
      &input,
      MemoryLayout<SMCKeyData>.size,
      &output,
      &outputSize
    )
    return (result: result, output: output)
  }

  private static let candidateKeywords = ["BCL", "BFCL", "CHG", "CH0", "CH1", "CHT", "CHWA", "BAT"]
}

private struct SMCKeyInfo {
  let dataSize: Int
  let dataType: UInt32
}

private enum SMCDiagnosticConnectionResult<T> {
  case success(T)
  case serviceNotFound
  case serviceOpenFailed(kern_return_t)
  case userClientOpenFailed(kern_return_t)
}

private enum SMCService {
  static let name = "AppleSMC"
}

private enum SMCCommand {
  static let userClientOpen: UInt32 = 0
  static let userClientClose: UInt32 = 1
  static let handleYPCEvent: UInt32 = 2
  static let readKey: UInt8 = 5
  static let getKeyInfo: UInt8 = 9
  static let getKeyByIndex: UInt8 = 8
  static let writeKey: UInt8 = 6
}

private struct SMCKeyDataVersion {
  var major: UInt8 = 0
  var minor: UInt8 = 0
  var build: UInt8 = 0
  var reserved: UInt8 = 0
  var release: UInt16 = 0
}

private struct SMCKeyDataPLimit {
  var version: UInt16 = 0
  var length: UInt16 = 0
  var cpuPLimit: UInt32 = 0
  var gpuPLimit: UInt32 = 0
  var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
  var dataSize: UInt32 = 0
  var dataType: UInt32 = 0
  var dataAttributes: UInt8 = 0
  var reserved: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

private typealias SMCBytes = (
  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyData {
  var key: UInt32 = 0
  var vers: SMCKeyDataVersion = SMCKeyDataVersion()
  var pLimitData: SMCKeyDataPLimit = SMCKeyDataPLimit()
  var keyInfo: SMCKeyInfoData = SMCKeyInfoData()
  var result: UInt8 = 0
  var status: UInt8 = 0
  var data8: UInt8 = 0
  var data32: UInt32 = 0
  var bytes: SMCBytes = (
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0
  )
}
