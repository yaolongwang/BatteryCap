// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "BatteryCapHelper",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .executable(
      name: "BatteryCapHelper",
      targets: ["BatteryCapHelper"]
    )
  ],
  targets: [
    .executableTarget(
      name: "BatteryCapHelper",
      path: "Sources/BatteryCapHelper",
      exclude: ["Info.plist"],
      swiftSettings: [
        .unsafeFlags([
          "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
          "-Xlinker", "Sources/BatteryCapHelper/Info.plist",
        ])
      ]
    )
  ]
)
