import AppKit
import SwiftUI

/// 主视图：显示电池状态和控制面板
struct ContentView: View {
  // MARK: - State

  @ObservedObject var viewModel: BatteryViewModel
  @State private var isSettingsPresented = false

  // MARK: - Derived Text

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

  // MARK: - View

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("BatteryCap")
        .font(.headline)

      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          statusRow(title: "电量", value: chargeText, useMonospacedDigits: true)
          statusRow(title: "供电", value: powerSourceText, useMonospacedDigits: false)
          statusRow(title: "电池状态", value: chargeStateText, useMonospacedDigits: false)
          statusRow(title: "循环次数", value: cycleText, useMonospacedDigits: true)
          statusRow(title: "更新时间", value: lastUpdatedText, useMonospacedDigits: true)
        }
        .frame(maxWidth: .infinity)
      } label: {
        Text("状态")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
      }

      GroupBox {
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
            Button {
              isSettingsPresented = true
            } label: {
              Label("设置", systemImage: "gearshape")
            }
            Spacer()
            Button {
              viewModel.refreshNow()
            } label: {
              Label("立即刷新", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isRefreshing)
          }
        }
        .frame(maxWidth: .infinity)
      } label: {
        Text("控制")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
      }

      smcHintView
    }
    .padding()
    .frame(width: 320)
    .popover(isPresented: $isSettingsPresented, arrowEdge: .top) {
      settingsView
    }
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

  // MARK: - Subviews

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

  @ViewBuilder
  private var smcHintView: some View {
    if let message = viewModel.smcStatus.hintMessage {
      VStack(alignment: .leading, spacing: 6) {
        Text("提示：\(message)")
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
  }

  private var settingsView: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("设置")
        .font(.headline)

      HStack {
        Text("开机自启动")
        Spacer()
        Toggle(
          "",
          isOn: Binding(
            get: { viewModel.isLaunchAtLoginEnabled },
            set: { viewModel.updateLaunchAtLoginEnabled($0) }
          )
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .focusable(false)
      }

      if let message = viewModel.launchAtLoginMessage {
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      HStack {
        Text("退出时保持当前状态")
        Spacer()
        Toggle(
          "",
          isOn: Binding(
            get: { viewModel.keepStateOnQuit },
            set: { viewModel.updateKeepStateOnQuit($0) }
          )
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .focusable(false)
      }

      Text(viewModel.keepStateOnQuit ? "关闭应用后将保持当前充电状态。" : "关闭应用后会恢复系统默认充电。")
        .font(.footnote)
        .foregroundStyle(.secondary)

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline) {
          Text("Helper 服务")
            .font(.subheadline)
            .fontWeight(.semibold)

          Spacer()

          if viewModel.isHelperServiceInstalled {
            Button("卸载 Helper 服务") {
              viewModel.uninstallHelperService()
            }
            .buttonStyle(.bordered)
            .focusable(false)
            .disabled(!viewModel.canUninstallHelperService)
          } else {
            Button("安装 Helper 服务") {
              viewModel.requestSmcWriteAccess()
            }
            .buttonStyle(.bordered)
            .focusable(false)
            .disabled(!viewModel.canInstallHelperService)
          }
        }

        HStack(alignment: .firstTextBaseline) {
          Text(viewModel.isHelperServiceInstalled ? "当前状态：已安装" : "当前状态：未安装")
            .font(.footnote)
            .foregroundStyle(.secondary)

          Spacer()

          Text(viewModel.isHelperServiceInstalled ? "卸载将触发系统管理员授权。" : "安装将触发系统管理员授权。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }

        if !viewModel.canInstallHelperService && !viewModel.canUninstallHelperService {
          Text("未找到安装/卸载脚本，请检查应用资源或项目脚本目录。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      HStack {
        Button("恢复系统默认") {
          viewModel.restoreSystemDefault()
        }
        .buttonStyle(.bordered)
        .focusable(false)

        Spacer()

        Button("退出") {
          NSApplication.shared.terminate(nil)
        }
        .buttonStyle(.bordered)
        .focusable(false)
      }
    }
    .padding(16)
    .frame(width: 300)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12))
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
