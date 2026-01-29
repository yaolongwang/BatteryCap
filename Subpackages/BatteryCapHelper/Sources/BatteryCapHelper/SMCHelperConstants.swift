import Foundation

enum SMCHelperConstants {
  static let machServiceName = "com.batterycap.helper"
  static let chargingKeyLegacy1 = "CH0B"
  static let chargingKeyLegacy2 = "CH0C"
  static let chargingKeyTahoe = "CHTE"

  static let chargingEnableLegacy: [UInt8] = [0x00]
  static let chargingDisableLegacy: [UInt8] = [0x02]
  static let chargingEnableTahoe: [UInt8] = [0x00, 0x00, 0x00, 0x00]
  static let chargingDisableTahoe: [UInt8] = [0x01, 0x00, 0x00, 0x00]
}
