import SwiftUI

// MARK: - CLI 入口

@main
struct BatteryCapEntry {
  static func main() {
    if BatteryCapDiagnostics.shouldRun {
      BatteryCapDiagnostics.run()
      return
    }
    BatteryCapApp.main()
  }
}

// MARK: - 主应用

/// BatteryCap 主应用入口
/// 使用 MenuBarExtra 作为主场景，提供菜单栏常驻体验
struct BatteryCapApp: App {
  @NSApplicationDelegateAdaptor(BatteryCapAppDelegate.self) private var appDelegate
  @StateObject private var viewModel = BatteryViewModel()

  var body: some Scene {
    MenuBarExtra("BatteryCap", systemImage: "battery.100") {
      ContentView(viewModel: viewModel)
    }
    .menuBarExtraStyle(.window)
  }
}
