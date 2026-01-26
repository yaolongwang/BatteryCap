import Foundation
import IOKit

final class SMCHelperSMCClient {
    private var connection: io_connect_t = 0
    private var isClosed = false

    init() throws {
        try open()
    }

    deinit {
        close()
    }

    func writeChargeLimit(_ value: UInt8) throws {
        let key = try SMCHelperSMCKey(SMCHelperConstants.chargeLimitKey)
        let keyInfo = try getKeyInfo(for: key)
        guard keyInfo.dataSize == 1 else {
            throw SMCHelperError.typeMismatch
        }

        var input = SMCHelperKeyData()
        input.key = key.code
        input.data8 = SMCHelperCommand.writeKey
        input.keyInfo.dataSize = UInt32(keyInfo.dataSize)
        withUnsafeMutableBytes(of: &input.bytes) { bytes in
            if !bytes.isEmpty {
                bytes[0] = value
            }
        }

        _ = try call(&input)
    }

    private func open() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            throw SMCHelperError.unavailable
        }
        defer {
            IOObjectRelease(service)
        }

        var openedConnection: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &openedConnection)
        guard openResult == KERN_SUCCESS else {
            throw SMCHelperError.permissionDenied
        }
        connection = openedConnection

        let openCallResult = IOConnectCallStructMethod(
            connection,
            SMCHelperCommand.userClientOpen,
            nil,
            0,
            nil,
            nil
        )
        guard openCallResult == KERN_SUCCESS else {
            close()
            throw SMCHelperError.permissionDenied
        }
    }

    private func close() {
        guard !isClosed else {
            return
        }
        isClosed = true

        if connection != 0 {
            _ = IOConnectCallStructMethod(connection, SMCHelperCommand.userClientClose, nil, 0, nil, nil)
            IOServiceClose(connection)
            connection = 0
        }
    }

    private func getKeyInfo(for key: SMCHelperSMCKey) throws -> SMCHelperKeyInfo {
        var input = SMCHelperKeyData()
        input.key = key.code
        input.data8 = SMCHelperCommand.getKeyInfo

        let output = try call(&input)
        let dataSize = Int(output.keyInfo.dataSize)
        guard dataSize > 0 else {
            throw SMCHelperError.keyNotFound
        }
        return SMCHelperKeyInfo(dataSize: dataSize, dataType: output.keyInfo.dataType)
    }

    private func call(_ input: inout SMCHelperKeyData) throws -> SMCHelperKeyData {
        var output = SMCHelperKeyData()
        var outputSize = MemoryLayout<SMCHelperKeyData>.size

        let result = IOConnectCallStructMethod(
            connection,
            SMCHelperCommand.handleYPCEvent,
            &input,
            MemoryLayout<SMCHelperKeyData>.size,
            &output,
            &outputSize
        )
        guard result == KERN_SUCCESS else {
            throw SMCHelperError.writeFailed
        }
        return output
    }
}

private struct SMCHelperSMCKey {
    let rawValue: String
    let code: UInt32

    init(_ rawValue: String) throws {
        guard rawValue.count == 4 else {
            throw SMCHelperError.invalidKey
        }
        self.rawValue = rawValue
        var value: UInt32 = 0
        for byte in rawValue.utf8 {
            value = (value << 8) | UInt32(byte)
        }
        self.code = value
    }
}

private struct SMCHelperKeyInfo {
    let dataSize: Int
    let dataType: UInt32
}

private enum SMCHelperCommand {
    static let userClientOpen: UInt32 = 0
    static let userClientClose: UInt32 = 1
    static let handleYPCEvent: UInt32 = 2
    static let getKeyInfo: UInt8 = 9
    static let writeKey: UInt8 = 6
}

private struct SMCHelperKeyDataVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCHelperKeyDataPLimit {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCHelperKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private typealias SMCHelperBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCHelperKeyData {
    var key: UInt32 = 0
    var vers: SMCHelperKeyDataVersion = SMCHelperKeyDataVersion()
    var pLimitData: SMCHelperKeyDataPLimit = SMCHelperKeyDataPLimit()
    var keyInfo: SMCHelperKeyInfoData = SMCHelperKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCHelperBytes = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

private enum SMCHelperError: Error {
    case unavailable
    case permissionDenied
    case invalidKey
    case keyNotFound
    case typeMismatch
    case writeFailed
}
