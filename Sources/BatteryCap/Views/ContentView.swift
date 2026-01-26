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

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                statusRow(title: "电量", value: chargeText, useMonospacedDigits: true)
                statusRow(title: "供电", value: powerSourceText, useMonospacedDigits: false)
                statusRow(title: "状态", value: chargeStateText, useMonospacedDigits: false)
                statusRow(title: "循环次数", value: cycleText, useMonospacedDigits: true)
                statusRow(title: "更新时间", value: lastUpdatedText, useMonospacedDigits: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Toggle("供电旁路", isOn: Binding(
                    get: { viewModel.isLimitControlEnabled },
                    set: { viewModel.updateLimitControlEnabled($0) }
                ))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("充电上限")
                        Spacer()
                        Text("\(viewModel.chargeLimit)%")
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.chargeLimit) },
                            set: { viewModel.updateChargeLimit(Int($0.rounded())) }
                        ),
                        in: Double(BatteryConstants.minChargeLimit)...Double(BatteryConstants.maxChargeLimit),
                        step: 1
                    )
                    .disabled(!viewModel.isLimitControlEnabled)
                }

                Button("立即刷新") {
                    viewModel.refreshNow()
                }
                .disabled(viewModel.isRefreshing)
            }

            if !viewModel.isControlSupported {
                Text("提示：当前版本未启用 SMC 写入，设置仅保存到本地，不会影响充电行为。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("启用后，电量达到上限将自动进入旁路模式。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            viewModel.start()
        }
        .alert("操作失败", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
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

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
