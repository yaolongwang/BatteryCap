import Foundation
import IOKit
import IOKit.ps

/// 电池信息提供者协议
protocol BatteryInfoProviderProtocol: Sendable {
    /// 获取当前电池信息
    func fetchBatteryInfo() async throws -> BatteryInfo
}

/// 使用 IOKit 读取电池信息
struct IOKitBatteryInfoProvider: BatteryInfoProviderProtocol, Sendable {
    func fetchBatteryInfo() async throws -> BatteryInfo {
        try fetchBatteryInfoSync()
    }

    private func fetchBatteryInfoSync() throws -> BatteryInfo {
        guard let powerSourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            throw BatteryError.powerSourceUnavailable
        }

        guard
            let powerSourcesList = IOPSCopyPowerSourcesList(powerSourcesInfo)?.takeRetainedValue()
                as? [CFTypeRef]
        else {
            throw BatteryError.powerSourceUnavailable
        }

        for powerSource in powerSourcesList {
            guard
                let description = IOPSGetPowerSourceDescription(powerSourcesInfo, powerSource)?
                    .takeUnretainedValue() as? [String: Any]
            else {
                continue
            }

            guard isInternalBattery(description) else {
                continue
            }

            guard
                let currentCapacity = intValue(for: kIOPSCurrentCapacityKey, in: description),
                let maxCapacity = intValue(for: kIOPSMaxCapacityKey, in: description),
                maxCapacity > 0
            else {
                throw BatteryError.invalidPowerSourceData
            }

            let percentage = Int((Double(currentCapacity) / Double(maxCapacity)) * 100.0)
            let cycleCount =
                readCycleCountFromRegistry()
                ?? intValue(for: RegistryKeys.cycleCountFallback, in: description)
            let powerSourceState = stringValue(for: kIOPSPowerSourceStateKey, in: description)
            let isCharging = boolValue(for: kIOPSIsChargingKey, in: description) ?? false
            let isCharged = boolValue(for: kIOPSIsChargedKey, in: description) ?? false

            let powerSource = mapPowerSource(from: powerSourceState)
            let chargeState = mapChargeState(
                isCharging: isCharging, isCharged: isCharged, powerSource: powerSource)

            return BatteryInfo(
                chargePercentage: percentage,
                cycleCount: cycleCount,
                powerSource: powerSource,
                chargeState: chargeState
            )
        }

        throw BatteryError.batteryNotFound
    }

    private func isInternalBattery(_ description: [String: Any]) -> Bool {
        guard let typeValue = stringValue(for: kIOPSTypeKey, in: description) else {
            return false
        }

        return typeValue == kIOPSInternalBatteryType
    }

    private func intValue(for key: String, in description: [String: Any]) -> Int? {
        if let value = description[key] as? Int {
            return value
        }
        if let value = description[key] as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private func boolValue(for key: String, in description: [String: Any]) -> Bool? {
        if let value = description[key] as? Bool {
            return value
        }
        if let value = description[key] as? NSNumber {
            return value.boolValue
        }
        return nil
    }

    private func stringValue(for key: String, in description: [String: Any]) -> String? {
        if let value = description[key] as? String {
            return value
        }
        if let value = description[key] as? NSString {
            return value as String
        }
        return nil
    }

    private func mapPowerSource(from state: String?) -> BatteryPowerSource {
        switch state {
        case kIOPSACPowerValue:
            return .adapter
        case kIOPSBatteryPowerValue:
            return .battery
        default:
            return .unknown
        }
    }

    private func mapChargeState(isCharging: Bool, isCharged: Bool, powerSource: BatteryPowerSource)
        -> BatteryChargeState
    {
        if isCharging {
            return .charging
        }
        if isCharged {
            return .charged
        }
        switch powerSource {
        case .battery:
            return .discharging
        case .adapter:
            return .paused
        case .unknown:
            return .unknown
        }
    }

    private func readCycleCountFromRegistry() -> Int? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching(RegistryKeys.smartBatteryService))
        guard service != 0 else {
            return nil
        }
        defer {
            IOObjectRelease(service)
        }

        guard
            let value = IORegistryEntryCreateCFProperty(
                service,
                RegistryKeys.cycleCount as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue()
        else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.intValue
        }
        if let intValue = value as? Int {
            return intValue
        }
        return nil
    }
}

private enum RegistryKeys {
    static let smartBatteryService = "AppleSmartBattery"
    static let cycleCount = "CycleCount"
    static let cycleCountFallback = "Cycle Count"
}
