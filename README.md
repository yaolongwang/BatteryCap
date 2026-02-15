# BatteryCap

BatteryCap 是一个轻量级 MacBook 菜单栏电池管理工具，通过“电量锁定 + 充电上限”减少长期满充，延缓电池衰减。

## 功能概览

- 菜单栏实时显示：电量、供电来源、充电状态、循环次数与更新时间。
- 电量锁定与上限控制：达到上限后停充，低于阈值后恢复。
- 立即刷新：手动同步电池信息与控制状态。
- 设置中心：开机自启动、退出时保持当前状态、Helper 安装/卸载、恢复系统默认、退出。

## 运行要求

- Apple Silicon Mac
- macOS 26 及以上
- MacBook 笔记本
- 运行形态：Menu Bar App

## 充电控制逻辑

- 上限范围：50%~100%，默认 80%
- 仅控制“停充/允充”，不会主动放电
- 未接外部电源时不干预

设当前电量为 `current`，上限为 `limit`：

- 关闭电量锁定：不干预，交由系统策略
- 开启电量锁定：使用 ±1% 滞回
  - `current >= limit + 1`：停止充电
  - `current <= limit - 1`：允许充电
  - 中间区间：保持上一次状态

## 安装与使用

1. 打开`BatteryCap.dmg`，将 `BatteryCap.app` 拖入`Applications`目录。
2. 首次打开按系统提示放行。
3. 在`设置`中**安装 Helper 服务**。
4. 开启电量锁定。

## 常见问题

1. 提示“权限不足”
   - 在`主界面`->`设置`点击`安装Helper服务`按钮，或执行：
   - `sudo "/Applications/BatteryCap.app/Contents/Resources/batterycap-service.sh" install`
2. 锁定无效 / 无响应
   - 确认设备处于外接电源
   - 将上限设置为低于当前电量后再开启“电量锁定”验证
3. 开机自启动未生效
   - 确认应用位于“应用程序”目录
   - 在“系统设置 -> 登录项”中允许 BatteryCap

## 卸载

一键卸载命令（推荐）：

```bash
sudo "/Applications/BatteryCap.app/Contents/Resources/batterycap-service.sh" full-uninstall
```

手动卸载：

1. 在 BatteryCap 设置里关闭“开机自启动”。
2. 在设置里的“Helper 服务”区域点击“卸载 Helper 服务”（会先关闭电量锁定）。
3. 删除 `/Applications/BatteryCap.app`。
4. 删除用户设置文件，位于：`~/Library/Preferences/com.batterycap.app.plist`

## 开发（简要）

- `swift run`：本地启动应用（开发调试）
- `swift build`：构建 Debug 版本
- `swift build -c release`：构建 Release 版本
- `swift test`：运行测试

常用脚本：

- `scripts/batterycap-service.sh`：开发态 Helper 安装/卸载入口
- `scripts/package-dist.sh app`：构建 `dist/BatteryCap.app`
- `scripts/package-dist.sh dmg`：构建 `dist/BatteryCap.app` 与 `dist/BatteryCap.dmg`

### SMC 诊断

```bash
swift run BatteryCap -- --diagnose
swift run BatteryCap -- --smc-diagnose
BATTERYCAP_DIAG=1 swift run
```

如果提示 Helper 诊断接口不可用，请先执行：

```bash
scripts/batterycap-service.sh install
```
