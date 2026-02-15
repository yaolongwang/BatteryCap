# BatteryCap

BatteryCap 是一个 macOS 菜单栏电池管理工具：通过“电量锁定 + 充电上限”减少长期满充，保护电池健康。

## 功能概览

- 菜单栏常驻：显示电量、供电来源、充电状态、循环次数与更新时间
- 电量锁定与上限控制：达到上限后暂停充电，低于阈值后恢复
- 立即刷新：手动刷新电池信息和控制状态
- SMC 写入状态提示：未授权时可直接触发“授权写入”
- 设置面板：开机自启动、退出行为、Helper 安装/卸载、恢复系统默认、退出

## 充电逻辑

- 上限范围：50%~100%，默认 80%
- 逻辑只影响“停充/允充”，不会强制放电
- 设备未接外部电源时，不改变放电行为

设当前电量为 `current`，上限为 `limit`：

- 电量锁定关闭：不干预，系统默认策略
- 电量锁定开启：使用 ±1% 滞回
  - `current >= limit + 1`：停止充电
  - `current <= limit - 1`：允许充电
  - 中间区间：保持上一次状态

示例：上限 80%，当前 90%，插电时会立即停止充电，随后自然回落到阈值附近再恢复。

## 卸载应用（无残留）

手动流程：

1. 在 BatteryCap 设置里关闭“开机自启动”。
2. 在设置里的“Helper 服务”区域点击“卸载 Helper 服务”（会先关闭电量锁定）。
3. 删除 `/Applications/BatteryCap.app`。

一键流程：

```bash
sudo "/Applications/BatteryCap.app/Contents/Resources/batterycap-service.sh" full-uninstall
```

如果你的 App 不在 `/Applications`，可先定位脚本：

1. 在 Finder 中右键 `BatteryCap.app`，选择“显示包内容”。
2. 进入 `Contents/Resources/`，找到 `batterycap-service.sh`。
3. 把该脚本拖入终端，再在后面补上 `full-uninstall` 执行。

说明：

- 系统级 Helper 文件位于：
  - `/Library/PrivilegedHelperTools/com.batterycap.helper`
  - `/Library/LaunchDaemons/com.batterycap.helper.plist`
- 用户设置文件位于：`~/Library/Preferences/com.batterycap.app.plist`
- 也可使用 Pearcleaner 等卸载工具做进一步清理。

## 开机自启动

- 使用 `SMAppService.mainApp` 注册登录项
- 可能需要在“系统设置 → 登录项”中手动允许
- 若提示“请将应用放入应用程序文件夹后重试”，请先将 App 移动到“应用程序”

## 常见问题

1. 提示“权限不足”
   - 运行 `sudo "/Applications/BatteryCap.app/Contents/Resources/batterycap-service.sh" install` 重新安装 Helper
   - 或在应用内点击“授权写入”
   - 再执行诊断确认 `SMC 状态: 已启用特权写入`
2. 锁定无效 / 无响应
   - 确认设备处于外接电源
   - 将上限设置为低于当前电量后再开启“电量锁定”验证
3. 开机自启动未生效
   - 确认应用位于“应用程序”目录
   - 在“系统设置 → 登录项”中允许 BatteryCap

## 平台与环境

- 目标平台：Apple Silicon（M1/M2/M3/M4/M5...）
- 系统要求：macOS 26 (Tahoe) 及以上
- 运行形态：Menu Bar App（无 Dock 图标）

## 快速开始（开发）

- `swift run`：本地启动应用（开发调试）
- `swift build`：构建 Debug 版本
- `swift build -c release`：构建 Release 版本
- `swift test`：运行测试

## 脚本说明

- `scripts/package-dist.sh`：打包分发产物（子命令：`app`、`dmg`）
- `scripts/compile-app-icon.sh`：编译并写入应用图标资源
- `scripts/batterycap-service.sh`：本地服务脚本入口（子命令：`install`、`uninstall`、`purge-config`、`full-uninstall`）

## Helper 安装与卸载

安装 Helper：

```bash
scripts/batterycap-service.sh install
```

仅卸载 Helper：

```bash
scripts/batterycap-service.sh uninstall
```

仅清理用户配置：

```bash
scripts/batterycap-service.sh purge-config
```

完整卸载（卸载 Helper + 删除 App + 清理用户配置）：

```bash
scripts/batterycap-service.sh full-uninstall
```

帮助：

```bash
scripts/batterycap-service.sh -h
```


## 打包分发

仅打包 `.app`：

```bash
scripts/package-dist.sh app
```

打包 `.app` + `.dmg`：

```bash
scripts/package-dist.sh dmg
```

默认子命令是 `app`，可用 `scripts/package-dist.sh -h` 查看帮助。

生成的 `dist/BatteryCap.app` 内置：

- `batterycap-service.sh`
- `com.batterycap.helper.plist`
- `BatteryCapHelper`

建议分发流程：

1. 将 `BatteryCap.app` 拷贝到“应用程序”目录。
2. 首次打开按系统提示放行（未知来源应用）。
3. 在设置面板点击“安装 Helper 服务”。

## SMC 诊断

```bash
swift run BatteryCap -- --diagnose
swift run BatteryCap -- --smc-diagnose
BATTERYCAP_DIAG=1 swift run
```

如果提示 Helper 诊断接口不可用，请先执行：

```bash
scripts/batterycap-service.sh install
```
