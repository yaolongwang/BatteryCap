import Foundation

/// 充电控制模式
enum ChargingMode: Equatable {
    case normal
    case chargeLimit(Int)
    case hold(Int)

    var targetLimit: Int {
        switch self {
        case .normal:
            return BatteryConstants.maxChargeLimit
        case .chargeLimit(let limit):
            return limit
        case .hold(let level):
            return level
        }
    }
}

/// 电池控制器协议
protocol BatteryControllerProtocol: Sendable {
    /// 是否支持实际硬件写入
    var isSupported: Bool { get }

    /// 应用充电模式（会写入 SMC 键值，存在硬件风险）
    func applyChargingMode(_ mode: ChargingMode) async throws
}

/// SMC 控制器实现
struct SMCBatteryController: BatteryControllerProtocol, Sendable {
    private let configuration: SMCConfiguration
    let isSupported: Bool

    init(configuration: SMCConfiguration = .load()) {
        self.configuration = configuration
        self.isSupported = configuration.isWritable
    }

    func applyChargingMode(_ mode: ChargingMode) async throws {
        guard isSupported else {
            throw BatteryError.unsupportedOperation
        }

        let limit = clampLimit(for: mode)
        try applyChargeLimit(limit)
    }

    private func applyChargeLimit(_ limit: Int) throws {
        guard let keyDefinition = configuration.chargeLimitKey else {
            throw BatteryError.unsupportedOperation
        }

        let value = UInt8(limit)
        let client = try SMCClient()
        try client.writeUInt8(value, to: keyDefinition)
    }

    private func clampLimit(for mode: ChargingMode) -> Int {
        let minValue: Int
        switch mode {
        case .hold:
            minValue = 1
        case .normal, .chargeLimit:
            minValue = BatteryConstants.minChargeLimit
        }

        return min(max(mode.targetLimit, minValue), BatteryConstants.maxChargeLimit)
    }
}
