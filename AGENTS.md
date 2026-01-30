# BatteryCap - AI Agent 开发指南

## 1. 项目概览
**BatteryCap** 是一个 macOS 菜单栏应用程序（GUI），旨在限制 MacBook 的电池充电上限，保护电池健康。
它通过与系统的 SMC (System Management Controller) 交互来管理电源流向。

### 功能清单

#### Phase 1: 核心功能 (GUI MVP)
**目标平台**: Apple Silicon (M1/M2/M3/M4...)
**系统要求**: macOS 26 (Tahoe) 及以上
**形式**: macOS 菜单栏应用 (Menu Bar App)

1.  **图形化控制界面**
    - **供电旁路开关 (Toggle)**:
        - **开启**: 锁定当前电量。Mac 完全使用外部电源供电，电池处于“闲置状态”（不充电也不放电）。
        - **关闭**: 恢复正常行为，电池开始充电直到充满 (100%)。
    - **充电上限设置 (Slider)**: 设置具体的充电百分比限制（配合开关使用，当达到限制时自动进入旁路模式）。
2.  **状态可视化**
    - 显示当前电池电量百分比。
    - 显示供电状态（电池供电 / 适配器供电 / 充电中 / 已暂停）。
    - 显示电池循环次数。
3.  **充电控制体验增强（轻量级）**
    - **电池状态清晰化**：显示“正在充电 / 充电暂停 / 放电中”。
    - **阈值滞回**：引入上下限区间，减少频繁切换。
    - **一键暂停充电**：立即停充并锁定当前电量。
4.  **设置菜单聚合**
    - 主界面提供“设置”入口，集中管理开机自启动、退出行为、恢复默认与退出。

#### Phase 2: 未来规划 (目前先不做)
1.  **开机自启动**: 登录时自动启动并应用设置。
2.  **MagSafe 指示灯控制**: 充电限制生效时改变指示灯颜色。

## 2. 环境与构建命令

### 开发环境
- **语言**: Swift 6.2+
- **平台**: macOS 26+ (Target)
- **工具链**: Swift Package Manager (SPM)

### 核心命令
| 动作 | 命令 | 说明 |
|--------|---------|------|
| **构建 (Debug)** | `swift build` | 编译调试版本 |
| **构建 (Release)** | `swift build -c release` | 编译优化后的发布版本 |
| **运行** | `swift run` | 编译并执行主入口程序 |
| **运行 (Release)** | `swift run -c release` | |
| **测试** | `swift test` | *注意：需要在 Package.swift 中添加测试目标* |
| **单测运行** | `swift test --filter <TestClass>/<testMethod>` | 运行指定的测试用例 |
| **清理** | `swift package clean` | 清除构建产物 |
| **更新依赖** | `swift package update` | 更新 SPM 依赖包 |
| **格式化** | `swift format . -i` | 需要安装 `swift-format` |

## 3. 代码风格与规范

### 基本原则
- **Swift API 设计指南**: 严格遵循 Apple 官方设计指南。
- **清晰优于简洁**: 方法名应具有描述性（例如用 `setChargeLimit(to:)` 而不是 `setLimit()`）。
- **现代 Swift**: 尽可能使用 Swift 6 特性（如结构化并发 `async/await`）。除非为了兼容旧 API，否则避免使用 GCD/DispatchQueue。

### 命名规范
- **类型/类/结构体**: `UpperCamelCase` (大驼峰，如 `BatteryManager`)。
- **函数/变量**: `lowerCamelCase` (小驼峰，如 `currentChargeLevel`)。
- **常量**: `lowerCamelCase` (static let)，通常定义在相关类型内部。
- **缩写**: 视为单词处理（例如 `SmcKey`，而不是 `SMCKey`）。

### 格式化
- **缩进**: 4 个空格。
- **行宽**: 软限制 120 字符。
- **大括号**: K&R 风格（左大括号不换行）。
- **引用 (Imports)**:
    1. 系统框架 (`import Foundation`, `import IOKit`)
    2. 第三方库
    3. 内部模块
    (组内按字母顺序排列)

### 类型安全与错误处理
- **强制解包**: **禁止**。严禁使用 `!` (强制解包) 或 `try!`。
    - *例外*: 单元测试的 setup 或编译期显而易见的安全常量。
- **可选值绑定**: 推荐使用 `guard let` 提前退出，局部作用域使用 `if let`。
- **错误处理**: 使用 `throw` 和 `do-catch` 块。定义自定义枚举 `enum BatteryError: Error`。
- **SMC/IOKit 交互**: 本项目涉及 `UnsafePointer` 操作。必须小心手动管理内存。使用 `defer` 确保资源（如 IOObjectRelease）被释放。

### 文档注释
- 使用 `///` 进行文档注释 (DocC 格式)。
- 必须为所有公开方法（尤其是涉及硬件交互的方法）编写文档。
- 明确标注硬件风险（例如：“此函数会写入 SMC 键值...”）。

## 4. 测试指南
- **单元测试**: 针对不接触硬件的逻辑（例如数值解析、CLI 参数处理）。
- **集成/Mock**: 由于无法在 CI 或所有机器上测试 SMC 写入，必须创建 `BatteryControllerProtocol` 和 `MockBatteryController` 用于测试。
- **测试命名**: `testMethodName_Condition_ExpectedResult` (测试方法名_条件_预期结果)。

## 5. 文件结构建议
- `Sources/BatteryCap/`: 源代码目录。
    - `Main.swift`: 程序入口 (`@main`)。
    - `Core/`: 底层 SMC/IOKit 封装代码。
    - `Logic/`: 业务逻辑（阈值判断、守护进程）。
    - `CLI/`: 参数解析与用户交互。
- `Tests/`: (待添加) 单元测试目录。

## 6. Git 与工作流
- **提交信息**: 使用 Conventional Commits 规范 (例如: `feat: add SMC reader`, `fix: correct percentage calc`)。
- **依赖管理**: 优先使用 Swift Package Manager。如果需要系统工具，假设使用 Homebrew。

## 7. 给 AI Agent 的特别规则
1. **中文交流**: 无论是回答用户提问还是进行内部推理，**必须使用中文**。不要使用英文回复用户。
2. **安全第一**: 编写与 SMC 交互的代码时，必须反复核对键值（Key）。向 SMC 写入错误的值可能导致硬件损坏。
3. **Mock 优先**: 总是建议为硬件交互创建 Protocol 抽象，以便安全测试。
4. **拒绝魔法数字**: 将 SMC 键值和常量定义在专门的 `Constants` 或 `SMCKeys` 结构体中。
