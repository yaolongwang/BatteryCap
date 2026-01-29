import AppKit
import Foundation

final class BatteryCapAppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    BatteryTerminationController.restoreIfNeeded()
    return .terminateNow
  }
}
