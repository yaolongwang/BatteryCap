# BatteryCap

## 运行（开发）
```bash
swift run
```

## SMC 诊断（命令行）
```bash
swift run BatteryCap -- --diagnose
```
如提示 Helper 诊断接口不可用，请重新运行 `scripts/install-helper.sh` 以更新特权组件。

## 已验证结论（2026-01-27）
设备：Mac16,13（M4 Air） / macOS 26.2

- SMC Key 列表中不包含 `BCLM`
- `BCLM` 的 KeyInfo 返回 `size=0` → 键不存在/不可写
- 读取到的候选键仅为只读状态类（`CH0*` / `PBAT` / `UBAT`），无可写充电上限键
- `CH0J` 即使特权读取仍返回 `kIOReturnNotPrivileged`

结论：当前机型 + 系统组合下，SMC 充电上限控制不可用（系统层面限制）。

## 本地安装写入组件（不需要开发者账号）
```bash
scripts/install-helper.sh
```
安装过程中会弹出管理员授权，请输入密码。

## 部分关闭 SIP（高风险，仅用于尝试）
注意：这会显著降低系统安全性，可能影响系统稳定性与更新。即便部分关闭 SIP，也**不保证**能开启 SMC 写入。

**Apple Silicon 进入恢复模式：**
1. 关机
2. 长按电源键，直到出现“启动选项”
3. 选择“选项”→“继续”，进入恢复模式
4. 菜单栏「实用工具」→「终端」

**执行命令（部分关闭 SIP）：**
```bash
csrutil enable --without debug --without fs --without nvram
```

**重启：**
```bash
reboot
```

**回到系统后检查状态：**
```bash
csrutil status
```

**恢复默认（重新开启 SIP）：**
进入恢复模式后执行：
```bash
csrutil enable
```
