import Foundation

@objc protocol SMCHelperProtocol {
    func setChargeLimit(_ limit: Int, reply: @escaping (Int32) -> Void)
    func setChargingEnabled(_ enabled: Bool, reply: @escaping (Int32) -> Void)
    func diagnoseChargeLimit(
        _ limit: Int,
        reply: @escaping (Int32, Int32, Int32, Int32, Int32) -> Void
    )
    func readKey(
        _ key: String,
        reply: @escaping (Int32, Int32, Int32, Int32, Int32, Int32, Data) -> Void
    )
}

/// 特权 Helper 客户端
final class SMCHelperClient: @unchecked Sendable {
    static let machServiceName = "com.batterycap.helper"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/\(machServiceName)")
    }

    func setChargeLimit(_ limit: Int) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate()
            let connection = NSXPCConnection(
                machServiceName: Self.machServiceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: SMCHelperProtocol.self)
            connection.invalidationHandler = {
                gate.resume(continuation, .failure(BatteryError.controllerUnavailable))
            }
            connection.resume()

            guard
                let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                    gate.resume(continuation, .failure(BatteryError.controllerUnavailable))
                    connection.invalidate()
                }) as? SMCHelperProtocol
            else {
                connection.invalidate()
                gate.resume(continuation, .failure(BatteryError.controllerUnavailable))
                return
            }

            proxy.setChargeLimit(limit) { status in
                connection.invalidationHandler = nil
                connection.invalidate()
                let result = SMCHelperStatus(rawValue: status) ?? .unknown
                if result == .ok {
                    gate.resume(continuation, .success(()))
                } else {
                    gate.resume(continuation, .failure(result.error))
                }
            }
        }
    }

    func setChargingEnabled(_ enabled: Bool) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate()
            let connection = NSXPCConnection(
                machServiceName: Self.machServiceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: SMCHelperProtocol.self)
            connection.invalidationHandler = {
                gate.resume(continuation, .failure(BatteryError.controllerUnavailable))
            }
            connection.resume()

            guard
                let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                    gate.resume(continuation, .failure(BatteryError.controllerUnavailable))
                    connection.invalidate()
                }) as? SMCHelperProtocol
            else {
                connection.invalidate()
                gate.resume(continuation, .failure(BatteryError.controllerUnavailable))
                return
            }

            proxy.setChargingEnabled(enabled) { status in
                connection.invalidationHandler = nil
                connection.invalidate()
                let result = SMCHelperStatus(rawValue: status) ?? .unknown
                if result == .ok {
                    gate.resume(continuation, .success(()))
                } else {
                    gate.resume(continuation, .failure(result.error))
                }
            }
        }
    }

    func diagnoseChargeLimit(_ limit: Int) async throws -> SMCHelperDiagnosticReport {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<SMCHelperDiagnosticReport, Error>) in
            let gate = ContinuationGate()
            let connection = NSXPCConnection(
                machServiceName: Self.machServiceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: SMCHelperProtocol.self)
            connection.invalidationHandler = {
                gate.resume(continuation, .failure(BatteryError.controllerUnavailable))
            }
            connection.resume()

            guard
                let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                    gate.resume(continuation, .failure(BatteryError.controllerUnavailable))
                    connection.invalidate()
                }) as? SMCHelperProtocol
            else {
                connection.invalidate()
                gate.resume(continuation, .failure(BatteryError.controllerUnavailable))
                return
            }

            proxy.diagnoseChargeLimit(limit) { status, stage, kern, dataSize, dataType in
                connection.invalidationHandler = nil
                connection.invalidate()
                let statusEnum = SMCHelperStatus(rawValue: status) ?? .unknown
                let stageEnum = SMCHelperDiagnosticStage(rawValue: stage) ?? .unknown
                let report = SMCHelperDiagnosticReport(
                    status: statusEnum,
                    stage: stageEnum,
                    kernReturn: kern,
                    dataSize: dataSize,
                    dataType: dataType
                )
                gate.resume(continuation, .success(report))
            }
        }
    }

    func readKey(_ key: String) async throws -> SMCHelperKeyReadReport {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<SMCHelperKeyReadReport, Error>) in
            let gate = ContinuationGate()
            let connection = NSXPCConnection(
                machServiceName: Self.machServiceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: SMCHelperProtocol.self)
            connection.invalidationHandler = {
                gate.resume(continuation, .failure(BatteryError.controllerUnavailable))
            }
            connection.resume()

            guard
                let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                    gate.resume(continuation, .failure(BatteryError.controllerUnavailable))
                    connection.invalidate()
                }) as? SMCHelperProtocol
            else {
                connection.invalidate()
                gate.resume(continuation, .failure(BatteryError.controllerUnavailable))
                return
            }

            proxy.readKey(key) { stage, kern, dataSize, dataType, truncated, _, bytes in
                connection.invalidationHandler = nil
                connection.invalidate()
                let report = SMCHelperKeyReadReport(
                    key: key,
                    stage: SMCHelperKeyReadStage(rawValue: stage) ?? .unknown,
                    kernReturn: kern,
                    dataSize: dataSize,
                    dataType: dataType,
                    bytes: bytes,
                    truncated: truncated != 0
                )
                gate.resume(continuation, .success(report))
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

enum SMCHelperDiagnosticStage: Int32, Sendable {
    case ok = 0
    case invalidKey = 1
    case serviceNotFound = 2
    case serviceOpenFailed = 3
    case userClientOpenFailed = 4
    case keyInfoFailed = 5
    case keyInfoInvalid = 6
    case typeMismatch = 7
    case writeFailed = 8
    case unknown = 99
}

struct SMCHelperDiagnosticReport: Sendable {
    let status: SMCHelperStatus
    let stage: SMCHelperDiagnosticStage
    let kernReturn: Int32
    let dataSize: Int32
    let dataType: Int32
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
        if didResume {
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
