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
    let keyInfo = try getKeyInfo(for: keyDefinition.key)
    guard keyInfo.dataSize == keyDefinition.dataSize else {
      throw BatteryError.smcTypeMismatch
    }
    if let expectedType = keyDefinition.dataType, expectedType.code != keyInfo.dataType {
      throw BatteryError.smcTypeMismatch
    }
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
    let keyInfo = try getKeyInfo(for: keyDefinition.key)
    guard keyInfo.dataSize == keyDefinition.dataSize else {
      throw BatteryError.smcTypeMismatch
    }
    if let expectedType = keyDefinition.dataType, expectedType.code != keyInfo.dataType {
      throw BatteryError.smcTypeMismatch
    }
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
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
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
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
    guard service != 0 else {
      return SMCKeyListReport(
        stage: .serviceNotFound,
        kernReturn: kIOReturnNoDevice,
        keyCount: 0,
        scannedCount: 0,
        candidates: []
      )
    }
    defer {
      IOObjectRelease(service)
    }

    var connection: io_connect_t = 0
    let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
    guard openResult == KERN_SUCCESS else {
      return SMCKeyListReport(
        stage: .serviceOpenFailed,
        kernReturn: openResult,
        keyCount: 0,
        scannedCount: 0,
        candidates: []
      )
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
      return SMCKeyListReport(
        stage: .userClientOpenFailed,
        kernReturn: openCallResult,
        keyCount: 0,
        scannedCount: 0,
        candidates: []
      )
    }

    guard let keyCount = readKeyCount(connection: connection) else {
      return SMCKeyListReport(
        stage: .keyCountFailed,
        kernReturn: KERN_SUCCESS,
        keyCount: 0,
        scannedCount: 0,
        candidates: []
      )
    }

    let scanLimit = min(maxKeys ?? keyCount, keyCount)
    var candidates: [String] = []
    candidates.reserveCapacity(64)
    let keywords = ["BCL", "BFCL", "CHG", "CH0", "CH1", "CHT", "CHWA", "BAT"]

    for index in 0..<scanLimit {
      guard let key = readKeyAtIndex(connection: connection, index: index) else {
        return SMCKeyListReport(
          stage: .keyReadFailed,
          kernReturn: KERN_SUCCESS,
          keyCount: keyCount,
          scannedCount: index,
          candidates: candidates
        )
      }

      if keywords.contains(where: { key.contains($0) }) {
        candidates.append(key)
      }
    }

    let trimmedCandidates = candidates.count > 120 ? Array(candidates.prefix(120)) : candidates
    return SMCKeyListReport(
      stage: .ok,
      kernReturn: KERN_SUCCESS,
      keyCount: keyCount,
      scannedCount: scanLimit,
      candidates: trimmedCandidates
    )
  }

  static func readKeyReport(_ keyName: String) -> SMCKeyReadReport {
    guard let key = try? SMCKey(keyName) else {
      return SMCKeyReadReport(
        key: keyName,
        stage: .invalidKey,
        kernReturn: KERN_FAILURE,
        dataSize: 0,
        dataType: 0,
        bytes: [],
        truncated: false
      )
    }

    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
    guard service != 0 else {
      return SMCKeyReadReport(
        key: keyName,
        stage: .serviceNotFound,
        kernReturn: kIOReturnNoDevice,
        dataSize: 0,
        dataType: 0,
        bytes: [],
        truncated: false
      )
    }
    defer {
      IOObjectRelease(service)
    }

    var connection: io_connect_t = 0
    let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
    guard openResult == KERN_SUCCESS else {
      return SMCKeyReadReport(
        key: keyName,
        stage: .serviceOpenFailed,
        kernReturn: openResult,
        dataSize: 0,
        dataType: 0,
        bytes: [],
        truncated: false
      )
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
      return SMCKeyReadReport(
        key: keyName,
        stage: .userClientOpenFailed,
        kernReturn: openCallResult,
        dataSize: 0,
        dataType: 0,
        bytes: [],
        truncated: false
      )
    }

    var keyInfoInput = SMCKeyData()
    keyInfoInput.key = key.code
    keyInfoInput.data8 = SMCCommand.getKeyInfo

    var keyInfoOutput = SMCKeyData()
    var keyInfoOutputSize = MemoryLayout<SMCKeyData>.size
    let keyInfoResult = IOConnectCallStructMethod(
      connection,
      SMCCommand.handleYPCEvent,
      &keyInfoInput,
      MemoryLayout<SMCKeyData>.size,
      &keyInfoOutput,
      &keyInfoOutputSize
    )
    guard keyInfoResult == KERN_SUCCESS else {
      return SMCKeyReadReport(
        key: keyName,
        stage: .keyInfoFailed,
        kernReturn: keyInfoResult,
        dataSize: 0,
        dataType: 0,
        bytes: [],
        truncated: false
      )
    }

    let dataSize = Int(keyInfoOutput.keyInfo.dataSize)
    let dataType = keyInfoOutput.keyInfo.dataType
    guard dataSize > 0 else {
      return SMCKeyReadReport(
        key: keyName,
        stage: .keyInfoInvalid,
        kernReturn: KERN_SUCCESS,
        dataSize: 0,
        dataType: dataType,
        bytes: [],
        truncated: false
      )
    }

    var readInput = SMCKeyData()
    readInput.key = key.code
    readInput.data8 = SMCCommand.readKey
    readInput.keyInfo.dataSize = UInt32(dataSize)

    var readOutput = SMCKeyData()
    var readOutputSize = MemoryLayout<SMCKeyData>.size
    let readResult = IOConnectCallStructMethod(
      connection,
      SMCCommand.handleYPCEvent,
      &readInput,
      MemoryLayout<SMCKeyData>.size,
      &readOutput,
      &readOutputSize
    )
    guard readResult == KERN_SUCCESS else {
      return SMCKeyReadReport(
        key: keyName,
        stage: .readFailed,
        kernReturn: readResult,
        dataSize: dataSize,
        dataType: dataType,
        bytes: [],
        truncated: false
      )
    }

    let maxBytes = min(dataSize, 32)
    var bytes: [UInt8] = []
    bytes.reserveCapacity(maxBytes)
    withUnsafeBytes(of: &readOutput.bytes) { raw in
      for index in 0..<min(maxBytes, raw.count) {
        bytes.append(raw[index])
      }
    }

    return SMCKeyReadReport(
      key: keyName,
      stage: .ok,
      kernReturn: KERN_SUCCESS,
      dataSize: dataSize,
      dataType: dataType,
      bytes: bytes,
      truncated: dataSize > 32
    )
  }

  private static func mapReturnToResult(_ result: kern_return_t) -> SMCWriteCheckResult {
    switch result {
    case kIOReturnNotPrivileged, kIOReturnNotPermitted:
      return .permissionDenied
    case kIOReturnNotFound:
      return .keyNotFound
    case kIOReturnNoDevice:
      return .smcUnavailable
    default:
      return .unknown
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

    var keyInfoOutput = SMCKeyData()
    var keyInfoOutputSize = MemoryLayout<SMCKeyData>.size
    let keyInfoResult = IOConnectCallStructMethod(
      connection,
      SMCCommand.handleYPCEvent,
      &keyInfoInput,
      MemoryLayout<SMCKeyData>.size,
      &keyInfoOutput,
      &keyInfoOutputSize
    )
    guard keyInfoResult == KERN_SUCCESS else {
      return nil
    }

    let dataSize = Int(keyInfoOutput.keyInfo.dataSize)
    guard dataSize >= 4 else {
      return nil
    }

    var readInput = SMCKeyData()
    readInput.key = key.code
    readInput.data8 = SMCCommand.readKey
    readInput.keyInfo.dataSize = UInt32(dataSize)

    var readOutput = SMCKeyData()
    var readOutputSize = MemoryLayout<SMCKeyData>.size
    let readResult = IOConnectCallStructMethod(
      connection,
      SMCCommand.handleYPCEvent,
      &readInput,
      MemoryLayout<SMCKeyData>.size,
      &readOutput,
      &readOutputSize
    )
    guard readResult == KERN_SUCCESS else {
      return nil
    }

    var bytes = [UInt8](repeating: 0, count: 4)
    withUnsafeBytes(of: &readOutput.bytes) { raw in
      for index in 0..<min(4, raw.count) {
        bytes[index] = raw[index]
      }
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
      return nil
    }

    return smcKeyString(from: output.key)
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

}

private struct SMCKeyInfo {
  let dataSize: Int
  let dataType: UInt32
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
