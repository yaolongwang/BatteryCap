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

    static func diagnose(limit: UInt8) -> SMCHelperDiagnosticReport {
        let keyName = SMCHelperConstants.chargeLimitKey
        guard let key = try? SMCHelperSMCKey(keyName) else {
            return SMCHelperDiagnosticReport(
                status: .invalidKey,
                stage: .invalidKey,
                kernReturn: KERN_FAILURE,
                dataSize: 0,
                dataType: 0
            )
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            return SMCHelperDiagnosticReport(
                status: .smcUnavailable,
                stage: .serviceNotFound,
                kernReturn: kIOReturnNoDevice,
                dataSize: 0,
                dataType: 0
            )
        }
        defer {
            IOObjectRelease(service)
        }

        var connection: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard openResult == KERN_SUCCESS else {
            return SMCHelperDiagnosticReport(
                status: mapReturnToStatus(openResult),
                stage: .serviceOpenFailed,
                kernReturn: openResult,
                dataSize: 0,
                dataType: 0
            )
        }
        defer {
            _ = IOConnectCallStructMethod(
                connection, SMCHelperCommand.userClientClose, nil, 0, nil, nil
            )
            IOServiceClose(connection)
        }

        let userClientResult = IOConnectCallStructMethod(
            connection,
            SMCHelperCommand.userClientOpen,
            nil,
            0,
            nil,
            nil
        )
        guard userClientResult == KERN_SUCCESS else {
            return SMCHelperDiagnosticReport(
                status: mapReturnToStatus(userClientResult),
                stage: .userClientOpenFailed,
                kernReturn: userClientResult,
                dataSize: 0,
                dataType: 0
            )
        }

        var keyInfoInput = SMCHelperKeyData()
        keyInfoInput.key = key.code
        keyInfoInput.data8 = SMCHelperCommand.getKeyInfo
        var keyInfoOutput = SMCHelperKeyData()
        var keyInfoOutputSize = MemoryLayout<SMCHelperKeyData>.size
        let keyInfoResult = IOConnectCallStructMethod(
            connection,
            SMCHelperCommand.handleYPCEvent,
            &keyInfoInput,
            MemoryLayout<SMCHelperKeyData>.size,
            &keyInfoOutput,
            &keyInfoOutputSize
        )
        guard keyInfoResult == KERN_SUCCESS else {
            return SMCHelperDiagnosticReport(
                status: mapReturnToStatus(keyInfoResult),
                stage: .keyInfoFailed,
                kernReturn: keyInfoResult,
                dataSize: 0,
                dataType: 0
            )
        }

        let dataSize = Int(keyInfoOutput.keyInfo.dataSize)
        let dataType = keyInfoOutput.keyInfo.dataType
        guard dataSize > 0 else {
            return SMCHelperDiagnosticReport(
                status: .keyNotFound,
                stage: .keyInfoInvalid,
                kernReturn: KERN_SUCCESS,
                dataSize: 0,
                dataType: dataType
            )
        }
        guard dataSize == 1 else {
            return SMCHelperDiagnosticReport(
                status: .typeMismatch,
                stage: .typeMismatch,
                kernReturn: KERN_SUCCESS,
                dataSize: dataSize,
                dataType: dataType
            )
        }

        var writeInput = SMCHelperKeyData()
        writeInput.key = key.code
        writeInput.data8 = SMCHelperCommand.writeKey
        writeInput.keyInfo.dataSize = UInt32(dataSize)
        withUnsafeMutableBytes(of: &writeInput.bytes) { bytes in
            if !bytes.isEmpty {
                bytes[0] = limit
            }
        }

        var writeOutput = SMCHelperKeyData()
        var writeOutputSize = MemoryLayout<SMCHelperKeyData>.size
        let writeResult = IOConnectCallStructMethod(
            connection,
            SMCHelperCommand.handleYPCEvent,
            &writeInput,
            MemoryLayout<SMCHelperKeyData>.size,
            &writeOutput,
            &writeOutputSize
        )
        guard writeResult == KERN_SUCCESS else {
            return SMCHelperDiagnosticReport(
                status: mapReturnToStatus(writeResult),
                stage: .writeFailed,
                kernReturn: writeResult,
                dataSize: dataSize,
                dataType: dataType
            )
        }

        return SMCHelperDiagnosticReport(
            status: .ok,
            stage: .ok,
            kernReturn: KERN_SUCCESS,
            dataSize: dataSize,
            dataType: dataType
        )
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
            throw mapReturn(openResult)
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
            throw mapReturn(openCallResult)
        }
    }

    private func close() {
        guard !isClosed else {
            return
        }
        isClosed = true

        if connection != 0 {
            _ = IOConnectCallStructMethod(
                connection, SMCHelperCommand.userClientClose, nil, 0, nil, nil)
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
            throw mapReturn(result)
        }
        return output
    }

    private func mapReturn(_ result: kern_return_t) -> SMCHelperError {
        switch result {
        case kIOReturnNotPrivileged, kIOReturnNotPermitted:
            return .permissionDenied
        case kIOReturnNoDevice:
            return .unavailable
        default:
            return .writeFailed
        }
    }
}

extension SMCHelperSMCClient {
    static func readKeyReport(_ keyName: String) -> SMCHelperKeyReadReport {
        guard let key = try? SMCHelperSMCKey(keyName) else {
            return SMCHelperKeyReadReport(
                key: keyName,
                stage: .invalidKey,
                kernReturn: KERN_FAILURE,
                dataSize: 0,
                dataType: 0,
                bytes: Data(),
                truncated: false
            )
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            return SMCHelperKeyReadReport(
                key: keyName,
                stage: .serviceNotFound,
                kernReturn: kIOReturnNoDevice,
                dataSize: 0,
                dataType: 0,
                bytes: Data(),
                truncated: false
            )
        }
        defer {
            IOObjectRelease(service)
        }

        var connection: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard openResult == KERN_SUCCESS else {
            return SMCHelperKeyReadReport(
                key: keyName,
                stage: .serviceOpenFailed,
                kernReturn: openResult,
                dataSize: 0,
                dataType: 0,
                bytes: Data(),
                truncated: false
            )
        }
        defer {
            _ = IOConnectCallStructMethod(
                connection, SMCHelperCommand.userClientClose, nil, 0, nil, nil
            )
            IOServiceClose(connection)
        }

        let openCallResult = IOConnectCallStructMethod(
            connection,
            SMCHelperCommand.userClientOpen,
            nil,
            0,
            nil,
            nil
        )
        guard openCallResult == KERN_SUCCESS else {
            return SMCHelperKeyReadReport(
                key: keyName,
                stage: .userClientOpenFailed,
                kernReturn: openCallResult,
                dataSize: 0,
                dataType: 0,
                bytes: Data(),
                truncated: false
            )
        }

        var keyInfoInput = SMCHelperKeyData()
        keyInfoInput.key = key.code
        keyInfoInput.data8 = SMCHelperCommand.getKeyInfo

        var keyInfoOutput = SMCHelperKeyData()
        var keyInfoOutputSize = MemoryLayout<SMCHelperKeyData>.size
        let keyInfoResult = IOConnectCallStructMethod(
            connection,
            SMCHelperCommand.handleYPCEvent,
            &keyInfoInput,
            MemoryLayout<SMCHelperKeyData>.size,
            &keyInfoOutput,
            &keyInfoOutputSize
        )
        guard keyInfoResult == KERN_SUCCESS else {
            return SMCHelperKeyReadReport(
                key: keyName,
                stage: .keyInfoFailed,
                kernReturn: keyInfoResult,
                dataSize: 0,
                dataType: 0,
                bytes: Data(),
                truncated: false
            )
        }

        let dataSize = Int(keyInfoOutput.keyInfo.dataSize)
        let dataType = keyInfoOutput.keyInfo.dataType
        guard dataSize > 0 else {
            return SMCHelperKeyReadReport(
                key: keyName,
                stage: .keyInfoInvalid,
                kernReturn: KERN_SUCCESS,
                dataSize: 0,
                dataType: dataType,
                bytes: Data(),
                truncated: false
            )
        }

        var readInput = SMCHelperKeyData()
        readInput.key = key.code
        readInput.data8 = SMCHelperCommand.readKey
        readInput.keyInfo.dataSize = UInt32(dataSize)

        var readOutput = SMCHelperKeyData()
        var readOutputSize = MemoryLayout<SMCHelperKeyData>.size
        let readResult = IOConnectCallStructMethod(
            connection,
            SMCHelperCommand.handleYPCEvent,
            &readInput,
            MemoryLayout<SMCHelperKeyData>.size,
            &readOutput,
            &readOutputSize
        )
        guard readResult == KERN_SUCCESS else {
            return SMCHelperKeyReadReport(
                key: keyName,
                stage: .readFailed,
                kernReturn: readResult,
                dataSize: dataSize,
                dataType: dataType,
                bytes: Data(),
                truncated: false
            )
        }

        let maxBytes = min(dataSize, 32)
        var bytes = [UInt8]()
        bytes.reserveCapacity(maxBytes)
        withUnsafeBytes(of: &readOutput.bytes) { raw in
            for index in 0..<min(maxBytes, raw.count) {
                bytes.append(raw[index])
            }
        }

        return SMCHelperKeyReadReport(
            key: keyName,
            stage: .ok,
            kernReturn: KERN_SUCCESS,
            dataSize: dataSize,
            dataType: dataType,
            bytes: Data(bytes),
            truncated: dataSize > 32
        )
    }
}

private func mapReturnToStatus(_ result: kern_return_t) -> SMCHelperStatus {
    switch result {
    case kIOReturnNotPrivileged, kIOReturnNotPermitted:
        return .permissionDenied
    case kIOReturnNotFound:
        return .keyNotFound
    case kIOReturnNoDevice:
        return .smcUnavailable
    default:
        return .writeFailed
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
    static let readKey: UInt8 = 5
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
    var reserved: (UInt8, UInt8, UInt8) = (0, 0, 0)
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

enum SMCHelperError: Error {
    case unavailable
    case permissionDenied
    case invalidKey
    case keyNotFound
    case typeMismatch
    case writeFailed
}

struct SMCHelperKeyReadReport {
    let key: String
    let stage: SMCHelperKeyReadStage
    let kernReturn: kern_return_t
    let dataSize: Int
    let dataType: UInt32
    let bytes: Data
    let truncated: Bool
}

enum SMCHelperKeyReadStage: Int32 {
    case ok = 0
    case invalidKey = 1
    case serviceNotFound = 2
    case serviceOpenFailed = 3
    case userClientOpenFailed = 4
    case keyInfoFailed = 5
    case keyInfoInvalid = 6
    case readFailed = 7
}

enum SMCHelperDiagnosticStage: Int32 {
    case ok = 0
    case invalidKey = 1
    case serviceNotFound = 2
    case serviceOpenFailed = 3
    case userClientOpenFailed = 4
    case keyInfoFailed = 5
    case keyInfoInvalid = 6
    case typeMismatch = 7
    case writeFailed = 8
}

struct SMCHelperDiagnosticReport {
    let status: SMCHelperStatus
    let stage: SMCHelperDiagnosticStage
    let kernReturn: kern_return_t
    let dataSize: Int
    let dataType: UInt32
}

extension SMCHelperError {
    var status: SMCHelperStatus {
        switch self {
        case .permissionDenied:
            return .permissionDenied
        case .keyNotFound:
            return .keyNotFound
        case .typeMismatch:
            return .typeMismatch
        case .unavailable:
            return .smcUnavailable
        case .writeFailed:
            return .writeFailed
        case .invalidKey:
            return .invalidKey
        }
    }
}
