# BatteryCap

macOS 菜单栏电池管理工具：支持电量锁定、充电上限与状态监控。

## 运行（开发）
```bash
swift run
```

## 本地安装写入组件（必须）
```bash
scripts/install-helper.sh
```
安装过程中会弹出管理员授权，请输入密码。

## SMC 诊断（命令行）
```bash
swift run BatteryCap -- --diagnose
```
如提示 Helper 诊断接口不可用，请重新运行 `scripts/install-helper.sh` 以更新特权组件。

## 工作原理（简述）
- 优先使用 `BCLM`（若机型支持）写入充电上限。
- 若 `BCLM` 不存在，则使用“充电开关键”控制充电开/关：
  - Tahoe 固件：`CHTE`（4 字节）
  - 旧固件：`CH0B` + `CH0C`（各 1 字节）
- 当“电量锁定”开启且电量达到上限时，会暂停充电；电量低于上限时再恢复充电。

## 已验证环境（2026-01-28）
设备：Mac16,13 / macOS 26.2 (Build 25C56)

- SMC Key 列表中不包含 `BCLM`
- `CHTE` 存在并可读取
- 通过特权 Helper 写入充电开关路径可用

## SIP 状态（建议保持开启）
本项目运行**不需要关闭 SIP**。建议保持 `System Integrity Protection: enabled`。

如需确认或恢复：
```bash
csrutil status
```

恢复默认（进入恢复模式后执行）：
```bash
csrutil enable
```

## 常见问题
1. **提示“权限不足”**  
   - 先运行 `scripts/install-helper.sh` 重新安装 Helper  
   - 运行 `swift run BatteryCap -- --diagnose`，确认 `SMC 状态: 已启用特权写入`
2. **锁定无效/无响应**  
   - 确认设备处于外接电源  
   - 将上限设置为低于当前电量，再开启“电量锁定”验证
