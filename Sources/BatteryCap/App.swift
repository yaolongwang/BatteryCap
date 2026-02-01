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
    MenuBarExtra("BatteryCap", systemImage: menuBarIconName) {
      ContentView(viewModel: viewModel)
    }
    .menuBarExtraStyle(.window)
  }

  private var menuBarIconName: String {
    let isLocked = viewModel.isLimitControlEnabled
    switch viewModel.batteryInfo?.chargeState {
    case .charging:
      return isLocked ? "bolt.batteryblock.fill" : "bolt.batteryblock"
    case .discharging:
      return isLocked ? "minus.plus.batteryblock.fill" : "minus.plus.batteryblock"
    case .paused, .charged, .unknown, .none:
      return isLocked ? "batteryblock.fill" : "batteryblock"
    }
  }
}
