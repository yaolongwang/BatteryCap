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
            let connection = NSXPCConnection(
                machServiceName: Self.machServiceName, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: SMCHelperProtocol.self)
            connection.invalidationHandler = {
                continuation.resume(throwing: BatteryError.controllerUnavailable)
            }
            connection.resume()

            guard
                let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                    continuation.resume(throwing: BatteryError.controllerUnavailable)
                }) as? SMCHelperProtocol
            else {
                connection.invalidate()
                continuation.resume(throwing: BatteryError.controllerUnavailable)
                return
            }

            proxy.setChargeLimit(limit) { status in
                connection.invalidate()
                if status == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: BatteryError.smcWriteFailed)
                }
            }
        }
    }
}
