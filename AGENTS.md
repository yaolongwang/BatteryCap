# BatteryCap - AGENTS 指南（给 AI）

本文件是 AI 修改代码时必须遵循的“隐性规则”与项目约束；README 是给人类用户的使用说明。

## 1) 项目目标与边界

**BatteryCap** 是一个 macOS 菜单栏应用：通过 SMC + 特权 Helper 管理充电开关，实现电量锁定与上限控制。

当前目标平台与形态：

- Apple Silicon (M1/M2/M3/M4...)
- macOS 26 (Tahoe)+
- Menu Bar App

Phase 1 目标能力：

1. 图形化控制（电量锁定开关 + 上限滑块）
2. 状态可视化（电量、供电、充电状态、循环次数）
3. 阈值滞回（减少频繁切换）
4. 设置聚合（开机自启动、退出行为、恢复默认、Helper 安装/卸载、退出）

Phase 2 规划（保留）：

1. 一键暂停充电

## 2) 文档分工（必须遵守）

- README：给人看，讲“是什么、怎么跑、怎么用”。
- AGENTS：给 AI 看，讲“怎么安全改、不能做什么、改完必须验证什么”。

修改文档时，保持这个边界，不要把 AI 规则写进 README，也不要把用户上手说明塞进 AGENTS。

## 3) 环境与命令

开发环境：

- Swift 6.2+
- Swift Package Manager
- macOS 26+

已验证环境：Mac16,13 / macOS 26.2 (25C56)

- `CHTE` 存在并可读取
- 特权 Helper 写入链路可用

核心命令：

| 动作           | 命令                                           | 说明                  |
| -------------- | ---------------------------------------------- | --------------------- |
| 构建 (Debug)   | `swift build`                                  | 编译调试版本          |
| 构建 (Release) | `swift build -c release`                       | 编译优化发布版本      |
| 运行           | `swift run`                                    | 运行主程序            |
| 运行 (Release) | `swift run -c release`                         | 运行发布构建          |
| 测试           | `swift test`                                   | 执行测试              |
| 单测运行       | `swift test --filter <TestClass>/<testMethod>` | 执行指定测试          |
| 清理           | `swift package clean`                          | 清除构建产物          |
| 更新依赖       | `swift package update`                         | 更新 SPM 依赖         |
| 格式化         | `swift format . -i`                            | 需安装 `swift-format` |

分发脚本（当前）：

- `scripts/package-dist.sh app`：生成 `dist/BatteryCap.app`
- `scripts/package-dist.sh dmg`：生成 `dist/BatteryCap.app` + `dist/BatteryCap.dmg`
- `scripts/batterycap-service.sh`：开发态服务入口（转发到资源脚本）

## 4) 代码风格与安全规则

基础原则：

- 遵循 Swift API Design Guidelines
- 清晰优于简洁
- 优先现代 Swift（`async/await`）

命名与格式：

- 类型：`UpperCamelCase`
- 变量/函数：`lowerCamelCase`
- 缩进 4 空格、行宽软限制 120
- import 顺序：系统 -> 第三方 -> 内部

类型安全与错误处理：

- 禁止 `!` 与 `try!`（测试 setup 或编译期常量除外）
- 优先 `guard let`
- 使用 `throw` + `do-catch`
- SMC/IOKit 指针操作必须保证资源释放（`defer`）

硬件安全：

- 任何写入 SMC 的修改都要复核 key 与数据类型
- 禁止引入“魔法数字”，SMC key/常量集中定义

## 5) 文件结构与关键路径

- `Package.swift`: 主包配置
- `scripts/`: 人工可执行脚本
  - `package-dist.sh`
  - `compile-app-icon.sh`
  - `batterycap-service.sh`（开发态转发入口）
- `Sources/BatteryCap/`
  - `App.swift`: 主入口 + 诊断/维护分流
  - `Views/`: UI
  - `Logic/`: 策略与状态管理
  - `Core/`: SMC/IOKit、特权调用与诊断
  - `Resources/`: 分发内置脚本与 plist
    - `batterycap-service.sh`（真实执行脚本）
    - `com.batterycap.helper.plist`
- `Subpackages/BatteryCapHelper/`: 特权 Helper 子包
- `Tests/`: 单测

## 6) 测试与验证（AI 必做）

每次修改后至少执行：

1. `swift build`
2. `swift test`
3. 若改到分发脚本，执行对应脚本（如 `scripts/package-dist.sh app` 或 `dmg`）

测试策略：

- 业务逻辑优先单测
- 硬件相关逻辑优先通过 `BatteryControllerProtocol` + Mock 测试
- 测试命名：`testMethodName_Condition_ExpectedResult`

## 7) Git 与工作流

- Commit message 用 Conventional Commits
- 依赖优先 SPM

## 8) AI 特别规则（强制）

1. 全程中文交流。
2. 不确定 SMC 行为时先查现有实现，再改。
3. 优先最小改动，不做无关重构。
4. 每次改动后必须编译（至少 `swift build`）。
5. 涉及脚本改动时必须做 `bash -n` 语法检查。

## 9) 历史需求记录（保留信息，不作为 README 主体）

状态栏动态图标需求记录：

- 电量锁定开为实心、关为空心
- 充电状态图标：
  - 正在充电：闪电
  - 充电暂停：空白
  - 放电中：减加
- 6 种组合：
  - 锁定开 + 正在充电：`bolt.batteryblock.fill`
  - 锁定关 + 正在充电：`bolt.batteryblock`
  - 锁定开 + 充电暂停：`batteryblock.fill`
  - 锁定关 + 充电暂停：`batteryblock`
  - 锁定开 + 放电中：`minus.plus.batteryblock.fill`
  - 锁定关 + 放电中：`minus.plus.batteryblock`
