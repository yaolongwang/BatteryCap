import Foundation

/// 充电控制模式
enum ChargingMode: Equatable {
    case normal
    case bypass
}

/// 电池控制器协议
protocol BatteryControllerProtocol: Sendable {
    /// 是否支持实际硬件写入
    var isSupported: Bool { get }

    /// 应用充电模式（会写入 SMC 键值，存在硬件风险）
    func applyChargingMode(_ mode: ChargingMode) async throws
}

/// SMC 控制器占位实现
/// 注意：此实现暂不写入 SMC，避免硬件风险
struct SMCBatteryController: BatteryControllerProtocol, Sendable {
    var isSupported: Bool {
        false
    }

    func applyChargingMode(_ mode: ChargingMode) async throws {
        throw BatteryError.unsupportedOperation
    }
}
