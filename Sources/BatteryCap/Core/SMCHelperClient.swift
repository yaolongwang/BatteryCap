import Foundation

@objc protocol SMCHelperProtocol {
  func setChargingEnabled(_ enabled: Bool, reply: @escaping (Int32) -> Void)
  func readKey(
    _ key: String,
    reply: @escaping (Int32, Int32, Int32, Int32, Int32, Int32, Data) -> Void
  )
}

/// 特权 Helper 客户端
final class SMCHelperClient: @unchecked Sendable {
  // MARK: - Constants

  static let machServiceName = "com.batterycap.helper"
  static let helperBinaryPath = "/Library/PrivilegedHelperTools/\(machServiceName)"
  static let launchDaemonPlistPath = "/Library/LaunchDaemons/\(machServiceName).plist"

  // MARK: - Status

  static var isInstalled: Bool {
    let fileManager = FileManager.default
    return fileManager.fileExists(atPath: helperBinaryPath)
      && fileManager.fileExists(atPath: launchDaemonPlistPath)
  }

  // MARK: - Operations

  func setChargingEnabled(_ enabled: Bool) async throws {
    try await withHelperProxy { proxy, complete in
      proxy.setChargingEnabled(enabled) { status in
        let result = SMCHelperStatus(rawValue: status) ?? .unknown
        if result == .ok {
          complete(.success(()))
        } else {
          complete(.failure(result.error))
        }
      }
    }
  }

  func readKey(_ key: String) async throws -> SMCHelperKeyReadReport {
    try await withHelperProxy { proxy, complete in
      proxy.readKey(key) { stage, kern, dataSize, dataType, truncated, _, bytes in
        let report = SMCHelperKeyReadReport(
          key: key,
          stage: SMCHelperKeyReadStage(rawValue: stage) ?? .unknown,
          kernReturn: kern,
          dataSize: dataSize,
          dataType: dataType,
          bytes: bytes,
          truncated: truncated != 0
        )
        complete(.success(report))
      }
    }
  }

  // MARK: - Connection

  private func withHelperProxy<T: Sendable>(
    _ body: @escaping (SMCHelperProtocol, @escaping (Result<T, Error>) -> Void) -> Void
  ) async throws -> T {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<T, Error>) in
      let gate = ContinuationGate()
      let unavailableError = BatteryError.controllerUnavailable
      let connection = NSXPCConnection(
        machServiceName: Self.machServiceName,
        options: .privileged
      )
      connection.remoteObjectInterface = NSXPCInterface(with: SMCHelperProtocol.self)
      connection.invalidationHandler = {
        gate.resume(continuation, .failure(unavailableError))
      }
      connection.resume()

      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
          gate.resume(continuation, .failure(unavailableError))
          connection.invalidate()
        }) as? SMCHelperProtocol
      else {
        connection.invalidate()
        gate.resume(continuation, .failure(unavailableError))
        return
      }

      body(proxy) { result in
        connection.invalidationHandler = nil
        connection.invalidate()
        gate.resume(continuation, result)
      }
    }
  }
}

enum SMCHelperStatus: Int32, Sendable {
  case ok = 0
  case permissionDenied = 1
  case keyNotFound = 2
  case typeMismatch = 3
  case smcUnavailable = 4
  case writeFailed = 5
  case invalidKey = 6
  case unknown = 99

  var error: BatteryError {
    switch self {
    case .permissionDenied:
      return .permissionDenied
    case .keyNotFound:
      return .smcKeyNotFound
    case .typeMismatch:
      return .smcTypeMismatch
    case .smcUnavailable:
      return .smcUnavailable
    case .writeFailed:
      return .smcWriteFailed
    case .invalidKey:
      return .smcKeyInvalid
    case .unknown, .ok:
      return .unknown("写入 SMC 失败。")
    }
  }
}

enum SMCHelperKeyReadStage: Int32, Sendable {
  case ok = 0
  case invalidKey = 1
  case serviceNotFound = 2
  case serviceOpenFailed = 3
  case userClientOpenFailed = 4
  case keyInfoFailed = 5
  case keyInfoInvalid = 6
  case readFailed = 7
  case unknown = 99
}

struct SMCHelperKeyReadReport: Sendable {
  let key: String
  let stage: SMCHelperKeyReadStage
  let kernReturn: Int32
  let dataSize: Int32
  let dataType: Int32
  let bytes: Data
  let truncated: Bool
}

private final class ContinuationGate {
  private let lock = NSLock()
  private var didResume = false

  func resume<T: Sendable>(
    _ continuation: CheckedContinuation<T, Error>,
    _ result: Result<T, Error>
  ) {
    lock.lock()
    guard !didResume else {
      lock.unlock()
      return
    }
    didResume = true
    lock.unlock()

    switch result {
    case .success(let value):
      continuation.resume(returning: value)
    case .failure(let error):
      continuation.resume(throwing: error)
    }
  }
}
