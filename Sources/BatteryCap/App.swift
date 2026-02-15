import SwiftUI

// MARK: - CLI 入口

@main
struct BatteryCapEntry {
  static func main() {
    let arguments = CommandLine.arguments
    let environment = ProcessInfo.processInfo.environment

    switch LaunchMode.resolve(arguments: arguments, environment: environment) {
    case .maintenance:
      BatteryCapMaintenance.run()
    case .diagnostics:
      BatteryCapDiagnostics.run()
    case .app:
      BatteryCapApp.main()
    }
  }
}

private enum LaunchMode {
  case app
  case maintenance
  case diagnostics

  static func resolve(arguments: [String], environment: [String: String]) -> LaunchMode {
    if BatteryCapMaintenance.shouldRun(arguments: arguments) {
      return .maintenance
    }
    if BatteryCapDiagnostics.shouldRun(arguments: arguments, environment: environment) {
      return .diagnostics
    }
    return .app
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
    let baseIconName: String
    switch viewModel.batteryInfo?.chargeState {
    case .charging:
      baseIconName = "bolt.batteryblock"
    case .discharging:
      baseIconName = "minus.plus.batteryblock"
    case .paused, .charged, .unknown, .none:
      baseIconName = "batteryblock"
    }

    return isLocked ? "\(baseIconName).fill" : baseIconName
  }
}
