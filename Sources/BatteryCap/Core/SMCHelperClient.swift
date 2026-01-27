import Foundation

@objc protocol SMCHelperProtocol {
    func setChargeLimit(_ limit: Int, reply: @escaping (Int32) -> Void)
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
}

private enum SMCHelperStatus: Int32 {
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

private final class ContinuationGate {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<Void, Error>, _ result: Result<Void, Error>) {
        lock.lock()
        if didResume {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()

        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
