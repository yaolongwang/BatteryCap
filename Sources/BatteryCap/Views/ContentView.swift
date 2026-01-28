import AppKit
import SwiftUI

/// 主视图：显示电池状态和控制面板
struct ContentView: View {
  @ObservedObject var viewModel: BatteryViewModel

  private var chargeText: String {
    guard let info = viewModel.batteryInfo else {
      return "--%"
    }
    return "\(info.chargePercentage)%"
  }

  private var cycleText: String {
    guard let cycleCount = viewModel.batteryInfo?.cycleCount else {
      return "--"
    }
    return "\(cycleCount)"
  }

  private var powerSourceText: String {
    viewModel.batteryInfo?.powerSourceText ?? "--"
  }

  private var chargeStateText: String {
    viewModel.batteryInfo?.chargeStateText ?? "--"
  }

  private var lastUpdatedText: String {
    guard let lastUpdated = viewModel.lastUpdated else {
      return "--"
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: lastUpdated)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("BatteryCap")
        .font(.headline)

      GroupBox("状态") {
        VStack(alignment: .leading, spacing: 8) {
          statusRow(title: "电量", value: chargeText, useMonospacedDigits: true)
          statusRow(title: "供电", value: powerSourceText, useMonospacedDigits: false)
          statusRow(title: "状态", value: chargeStateText, useMonospacedDigits: false)
          statusRow(title: "循环次数", value: cycleText, useMonospacedDigits: true)
          statusRow(title: "更新时间", value: lastUpdatedText, useMonospacedDigits: true)
        }
        .frame(maxWidth: .infinity)
      }

      GroupBox("控制") {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("电量锁定")
            Spacer()
            Toggle(
              "",
              isOn: Binding(
                get: { viewModel.isLimitControlEnabled },
                set: { viewModel.updateLimitControlEnabled($0) }
              )
            )
            .labelsHidden()
            .toggleStyle(.switch)
          }

          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text("最高电量")
              Spacer()
              Text("\(viewModel.chargeLimit)%")
                .monospacedDigit()
            }

            Slider(
              value: Binding(
                get: { Double(viewModel.chargeLimit) },
                set: { viewModel.updateChargeLimit(Int($0.rounded())) }
              ),
              in: Double(
                BatteryConstants.minChargeLimit)...Double(
                  BatteryConstants.maxChargeLimit),
              step: 1
            )
            .disabled(!viewModel.isLimitControlEnabled)
          }

          HStack {
            Button("立即刷新") {
              viewModel.refreshNow()
            }
            .disabled(viewModel.isRefreshing)

            Button("恢复系统默认") {
              viewModel.restoreSystemDefault()
            }

            Button("退出") {
              NSApplication.shared.terminate(nil)
            }
          }
        }
        .frame(maxWidth: .infinity)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("提示：\(viewModel.smcStatus.message)")
          .font(.footnote)
          .foregroundStyle(.secondary)

        if viewModel.smcStatus.needsPrivilege {
          Button("授权写入") {
            viewModel.requestSmcWriteAccess()
          }
          .font(.footnote)
          .disabled(!viewModel.canRequestSmcWriteAccess)
        }
      }
    }
    .padding()
    .frame(width: 320)
    .onAppear {
      viewModel.start()
    }
    .alert(
      "操作失败",
      isPresented: Binding(
        get: { viewModel.errorMessage != nil },
        set: { if !$0 { viewModel.clearError() } }
      )
    ) {
      Button("好的") {
        viewModel.clearError()
      }
    } message: {
      Text(viewModel.errorMessage ?? "")
    }
  }

  private func statusRow(title: String, value: String, useMonospacedDigits: Bool) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(value)
        .if(useMonospacedDigits) { view in
          view.monospacedDigit()
        }
    }
  }
}

extension View {
  @ViewBuilder
  fileprivate func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content)
    -> some View
  {
    if condition {
      transform(self)
    } else {
      self
    }
  }
}
