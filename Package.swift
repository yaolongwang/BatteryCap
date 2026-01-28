// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "BatteryCap",
  platforms: [
    .macOS(.v26)  // 确保目标系统为 macOS 26+
  ],
  products: [
    .executable(
      name: "BatteryCap",
      targets: ["BatteryCap"]
    )
  ],
  targets: [
    .executableTarget(
      name: "BatteryCap",
      path: "Sources/BatteryCap",
      exclude: ["Info.plist"],
      resources: [
        .process("Resources")
      ],
      swiftSettings: [
        .unsafeFlags([
          "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
          "-Xlinker", "Sources/BatteryCap/Info.plist",
        ])
      ]
    ),
    .testTarget(
      name: "BatteryCapTests",
      dependencies: ["BatteryCap"],
      path: "Tests"
    ),
  ]
)
