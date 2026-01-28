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

    func setChargingEnabled(_ enabled: Bool, reply: @escaping (Int32) -> Void) {
        do {
            try SMCHelperSMCClient().setChargingEnabled(enabled)
            reply(SMCHelperStatus.ok.rawValue)
        } catch let error as SMCHelperError {
            reply(error.status.rawValue)
        } catch {
            reply(SMCHelperStatus.unknown.rawValue)
        }
    }

    func diagnoseChargeLimit(
        _ limit: Int,
        reply: @escaping (Int32, Int32, Int32, Int32, Int32) -> Void
    ) {
        let clamped = min(max(limit, 1), 100)
        let report = SMCHelperSMCClient.diagnose(limit: UInt8(clamped))
        reply(
            report.status.rawValue,
            report.stage.rawValue,
            Int32(report.kernReturn),
            Int32(report.dataSize),
            Int32(bitPattern: report.dataType)
        )
    }

    func readKey(
        _ key: String,
        reply: @escaping (Int32, Int32, Int32, Int32, Int32, Int32, Data) -> Void
    ) {
        let report = SMCHelperSMCClient.readKeyReport(key)
        reply(
            report.stage.rawValue,
            Int32(report.kernReturn),
            Int32(report.dataSize),
            Int32(bitPattern: report.dataType),
            report.truncated ? 1 : 0,
            Int32(report.bytes.count),
            report.bytes
        )
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
