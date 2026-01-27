import Foundation

@objc protocol SMCHelperProtocol {
    func setChargeLimit(_ limit: Int, reply: @escaping (Int32) -> Void)
}

final class SMCHelper: NSObject, NSXPCListenerDelegate, SMCHelperProtocol {
    func listener(
        _ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: SMCHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func setChargeLimit(_ limit: Int, reply: @escaping (Int32) -> Void) {
        let clamped = min(max(limit, 1), 100)
        do {
            try SMCHelperSMCClient().writeChargeLimit(UInt8(clamped))
            reply(SMCHelperStatus.ok.rawValue)
        } catch let error as SMCHelperError {
            reply(error.status.rawValue)
        } catch {
            reply(SMCHelperStatus.unknown.rawValue)
        }
    }
}

enum SMCHelperStatus: Int32 {
    case ok = 0
    case permissionDenied = 1
    case keyNotFound = 2
    case typeMismatch = 3
    case smcUnavailable = 4
    case writeFailed = 5
    case invalidKey = 6
    case unknown = 99
}
