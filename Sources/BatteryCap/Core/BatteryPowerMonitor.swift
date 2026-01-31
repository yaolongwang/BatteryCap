import Foundation
import IOKit.ps

/// 电源变化监听器
final class BatteryPowerMonitor: @unchecked Sendable {
  // MARK: - Callbacks

  var onPowerSourceChange: (() -> Void)?

  // MARK: - State

  private var runLoopSource: CFRunLoopSource?

  // MARK: - Lifecycle

  deinit {
    stop()
  }

  // MARK: - Control

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

  // MARK: - Callback

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
