import Foundation
import IOKit.ps

/// 电源变化监听器
final class BatteryPowerMonitor: @unchecked Sendable {
  var onPowerSourceChange: (() -> Void)?

  private var runLoopSource: CFRunLoopSource?

  func start() {
    guard runLoopSource == nil else {
      return
    }

    let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

    guard
      let source = IOPSNotificationCreateRunLoopSource(powerSourceCallback, context)?
        .takeRetainedValue()
    else {
      return
    }

    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
  }

  func stop() {
    guard let source = runLoopSource else {
      return
    }

    CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
    runLoopSource = nil
  }

  fileprivate func handlePowerSourceChange() {
    onPowerSourceChange?()
  }
}

private let powerSourceCallback: IOPowerSourceCallbackType = { context in
  guard let context else {
    return
  }
  let monitor = Unmanaged<BatteryPowerMonitor>.fromOpaque(context).takeUnretainedValue()
  monitor.handlePowerSourceChange()
}
