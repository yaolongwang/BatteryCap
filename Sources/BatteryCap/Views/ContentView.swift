import SwiftUI

/// 主视图：显示电池状态和控制面板
/// 包含：
/// 1. 电池信息（电量、循环次数、充电状态）
/// 2. 充电上限开关和滑块
struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BatteryCap")
                .font(.headline)
                .padding(.bottom, 4)

            Divider()

            // TODO: 待实现 - 显示电池状态
            Text("电量: --%")
                .font(.body)

            // TODO: 待实现 - 供电旁路开关
            Text("开关: (待实现)")

            // TODO: 待实现 - 充电上限滑块
            Text("上限设置: (待实现)")
        }
        .padding()
        .frame(width: 280)
    }
}
