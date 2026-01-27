import Foundation
import IOKit

/// SMC 客户端（简化写入）
final class SMCClient {
    private var connection: io_connect_t = 0
    private var isClosed = false

    init() throws {
        try open()
    }

    deinit {
        close()
    }

    func writeUInt8(_ value: UInt8, to keyDefinition: SMCKeyDefinition) throws {
        let keyInfo = try getKeyInfo(for: keyDefinition.key)
        guard keyInfo.dataSize == keyDefinition.dataSize else {
            throw BatteryError.smcTypeMismatch
        }
        if let expectedType = keyDefinition.dataType, expectedType.code != keyInfo.dataType {
            throw BatteryError.smcTypeMismatch
        }

        var input = SMCKeyData()
        input.key = keyDefinition.key.code
        input.data8 = SMCCommand.writeKey
        input.keyInfo.dataSize = UInt32(keyInfo.dataSize)

        withUnsafeMutableBytes(of: &input.bytes) { bytes in
            if !bytes.isEmpty {
                bytes[0] = value
            }
        }

        _ = try call(&input)
    }

    static func canWrite(_ keyDefinition: SMCKeyDefinition) -> Bool {
        checkWriteAccess(keyDefinition) == .supported
    }

    static func checkWriteAccess(_ keyDefinition: SMCKeyDefinition) -> SMCWriteCheckResult {
        do {
            let client = try SMCClient()
            try client.validate(keyDefinition)
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

    private func validate(_ keyDefinition: SMCKeyDefinition) throws {
        let keyInfo = try getKeyInfo(for: keyDefinition.key)
        guard keyInfo.dataSize == keyDefinition.dataSize else {
            throw BatteryError.smcTypeMismatch
        }
        if let expectedType = keyDefinition.dataType, expectedType.code != keyInfo.dataType {
            throw BatteryError.smcTypeMismatch
        }
    }

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

private struct SMCKeyInfo {
    let dataSize: Int
    let dataType: UInt32
}

private enum SMCCommand {
    static let userClientOpen: UInt32 = 0
    static let userClientClose: UInt32 = 1
    static let handleYPCEvent: UInt32 = 2
    static let getKeyInfo: UInt8 = 9
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
