import SwiftUI

/// BatteryCap 主应用入口
/// 使用 MenuBarExtra 作为主场景，提供菜单栏常驻体验
@main
struct BatteryCapApp: App {
    var body: some Scene {
        MenuBarExtra("BatteryCap", systemImage: "battery.100") {
            ContentView()
        }
    }
}
