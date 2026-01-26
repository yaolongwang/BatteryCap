import Foundation

@objc protocol SMCHelperProtocol {
    func setChargeLimit(_ limit: Int, reply: @escaping (Int32) -> Void)
}

final class SMCHelper: NSObject, NSXPCListenerDelegate, SMCHelperProtocol {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: SMCHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func setChargeLimit(_ limit: Int, reply: @escaping (Int32) -> Void) {
        let clamped = min(max(limit, 1), 100)
        do {
            try SMCHelperSMCClient().writeChargeLimit(UInt8(clamped))
            reply(0)
        } catch {
            reply(1)
        }
    }
}
