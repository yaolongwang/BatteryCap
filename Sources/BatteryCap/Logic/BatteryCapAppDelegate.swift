import AppKit
import Foundation

/// 应用生命周期代理
final class BatteryCapAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    BatteryTerminationController.restoreIfNeeded()
    return .terminateNow
  }
}
