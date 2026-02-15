import AppKit
import SwiftUI

/// 主视图：显示电池状态和控制面板
struct ContentView: View {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

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
        return Self.timeFormatter.string(from: lastUpdated)
    }

    private var canAdjustChargeControl: Bool {
        viewModel.isHelperServiceInstalled
    }

    // MARK: - Bindings

    private var limitControlBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isLimitControlEnabled },
            set: { viewModel.updateLimitControlEnabled($0) }
        )
    }

    private var chargeLimitBinding: Binding<Double> {
        Binding(
            get: { Double(viewModel.chargeLimit) },
            set: { viewModel.updateChargeLimit(Int($0.rounded())) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isLaunchAtLoginEnabled },
            set: { viewModel.updateLaunchAtLoginEnabled($0) }
        )
    }

    private var keepStateOnQuitBinding: Binding<Bool> {
        Binding(
            get: { viewModel.keepStateOnQuit },
            set: { viewModel.updateKeepStateOnQuit($0) }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: {
                if !$0 {
                    viewModel.clearError()
                }
            }
        )
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BatteryCap")
                .font(.headline)

            statusSection
            controlSection
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
        .alert("操作失败", isPresented: errorAlertBinding) {
            Button("退出应用") {
                terminateFromErrorAlert()
            }
            Button("好的", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Main Sections

    private var statusSection: some View {
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
            sectionTitle("状态")
        }
    }

    private var controlSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                limitControlRow
                chargeLimitSection
                controlActionsRow
            }
            .frame(maxWidth: .infinity)
        } label: {
            sectionTitle("控制")
        }
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置")
                .font(.headline)

            launchAtLoginRow
            launchAtLoginMessageView

            keepStateOnQuitRow
            keepStateHintView

            Divider()
            helperServiceSection

            Divider()
            settingsActionsRow
        }
        .padding(16)
        .frame(width: 300)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Control Subviews

    private var limitControlRow: some View {
        HStack {
            Text("电量锁定")
            Spacer()
            Toggle("", isOn: limitControlBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!canAdjustChargeControl)
        }
    }

    private var chargeLimitSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("最高电量")
                Spacer()
                Text("\(viewModel.chargeLimit)%")
                    .monospacedDigit()
            }

            Slider(
                value: chargeLimitBinding,
                in: BatteryConstants.chargeLimitSliderRange,
                step: 1
            )
            .disabled(!canAdjustChargeControl || !viewModel.isLimitControlEnabled)
        }
    }

    private var controlActionsRow: some View {
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

    // MARK: - Settings Subviews

    private var launchAtLoginRow: some View {
        HStack {
            Text("开机自启动")
            Spacer()
            Toggle("", isOn: launchAtLoginBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .focusable(false)
        }
    }

    @ViewBuilder
    private var launchAtLoginMessageView: some View {
        if let message = viewModel.launchAtLoginMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var keepStateOnQuitRow: some View {
        HStack {
            Text("退出时保持当前状态")
            Spacer()
            Toggle("", isOn: keepStateOnQuitBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .focusable(false)
        }
    }

    private var keepStateHintView: some View {
        Text(viewModel.keepStateOnQuit ? "关闭应用后将保持当前充电状态。" : "关闭应用后会恢复系统默认充电。")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var helperServiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Helper 服务")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                helperServiceActionButton
            }

            helperServiceStatusRow
            helperServiceScriptHint
        }
    }

    @ViewBuilder
    private var helperServiceActionButton: some View {
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

    private var helperServiceStatusRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(viewModel.isHelperServiceInstalled ? "当前状态：已安装" : "当前状态：未安装")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Text(viewModel.isHelperServiceInstalled ? "卸载需要系统管理员权限" : "安装需要系统管理员权限")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var helperServiceScriptHint: some View {
        if !viewModel.canInstallHelperService && !viewModel.canUninstallHelperService {
            Text("未找到安装/卸载脚本，请检查应用资源或项目脚本目录。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var settingsActionsRow: some View {
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

    // MARK: - Shared Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
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

    private func terminateFromErrorAlert() {
        viewModel.clearError()
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) {
            if !NSRunningApplication.current.isTerminated {
                exit(EXIT_SUCCESS)
            }
        }
    }

    @ViewBuilder
    private var smcHintView: some View {
        if let message = viewModel.smcStatus.hintMessage {
            let hintMessage =
                viewModel.smcStatus.needsPrivilege
                ? "SMC写入不可用，请打开设置安装helper服务"
                : message
            VStack(alignment: .leading, spacing: 6) {
                Text("提示：\(hintMessage)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
