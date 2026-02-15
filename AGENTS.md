# BatteryCap - AGENTS 指南

本文件仅定义 AI 修改仓库时的规则。README 面向用户，不在此重复用户使用说明。

## 1) 文档边界（强制）

- `README.md`：面向用户，说明产品用途、安装使用、常见问题。
- `AGENTS.md`：面向 AI，说明改码约束、验证流程、关键路径。
- 不在 `README.md` 写 AI 行为规范；不在 `AGENTS.md` 写用户操作手册。

## 2) 开发环境

- Swift 6.2+
- Swift Package Manager
- macOS 26+

常用命令（按需执行）：

- `swift build`
- `swift test`
- `swift run`
- `swift build -c release`
- `swift test --filter <TestClass>/<testMethod>`

脚本入口：

- `scripts/batterycap-service.sh`（开发态入口，转发到 `Sources/BatteryCap/Resources/batterycap-service.sh`）
- `scripts/package-dist.sh app|dmg`

## 3) 代码风格与安全

- 遵循 Swift API Design Guidelines，优先可读性与最小改动。
- 类型 `UpperCamelCase`，变量/函数 `lowerCamelCase`。
- 缩进 4 空格，行宽软限制 120。
- `import` 顺序：系统 -> 第三方 -> 内部。

类型与错误处理：

- 禁止 `!` 与 `try!`（测试 setup 或编译期常量除外）。
- 优先 `guard let`。
- 使用 `throw` + `do-catch`，禁止吞错。
- SMC/IOKit 指针操作必须配套 `defer` 释放资源。

硬件相关：

- 涉及 SMC 写入时，必须复核 key、数据类型与字节长度。
- 禁止魔法数字；SMC 常量集中维护并复用。

## 4) 关键路径速查

- `Package.swift`：主包与测试目标配置
- `scripts/`：开发与分发脚本：
  - `scripts/batterycap-service.sh`：开发态服务入口（转发到资源脚本）
  - `scripts/compile-app-icon.sh`：编译并写入应用图标资源（.icon文件每次修改后需执行）
  - `scripts/package-dist.sh`：打包分发产物（`app`、`dmg`）
- `Sources/BatteryCap/App.swift`：主入口（app/diagnose/maintenance 分流）
- `Sources/BatteryCap/Core/`：SMC、IOKit、Helper 客户端、诊断
- `Sources/BatteryCap/Logic/`：策略与状态管理
- `Sources/BatteryCap/Views/`：UI
- `Sources/BatteryCap/Resources/`：内置脚本与 plist
- `Subpackages/BatteryCapHelper/`：特权 Helper 子包
- `Tests/`：单元测试

## 5) 变更后验证（必做）

每次改动后至少执行：

1. `swift build`
2. `swift test`
3. 若改动了 shell 脚本：`bash -n <script>`
4. 若改动了分发脚本：执行对应打包命令（`scripts/package-dist.sh app` 或 `scripts/package-dist.sh dmg`）

测试约定：

- 业务逻辑优先单测。
- 硬件相关逻辑优先通过 `BatteryControllerProtocol` + Mock 测试。
- 命名建议：`testMethodName_Condition_ExpectedResult`。

## 6) Git 与协作约束

- Commit message 使用 Conventional Commits。
- 优先通过 SPM 管理依赖。

## 7) AI 执行规则（强制）

1. 全程中文交流。
2. 不确定 SMC 行为时，先查现有实现再改。
3. 以最小改动完成目标。
4. 不得跳过验证步骤。
