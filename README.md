# 修复 DSH 无头 shell：pwsh 与 python 的 0xC0000135 排障全记录

> 在 Windows 上，DeepSeek Harness（DSH）桌面应用的无头 shell 完全不可用，`pwsh` 与 `python` 均以退出码 `0xC0000135`（`STATUS_DLL_NOT_FOUND`）失败。本文完整记录定位与修复过程，含可直接复用的 PowerShell 脚本。

## 问题现象

DSH 桌面应用（`D:\Program Files\dsh`）的无头 shell 不可用：

- `pwsh` 启动失败，退出码 `0xC0000135`
- `python` 启动失败，退出码 `0xC0000135`
- `0xC0000135` = `STATUS_DLL_NOT_FOUND`（十进制 `3221225781`）

## 环境背景

| 组件 | 路径 | 状态 |
|---|---|---|
| DSH 桌面应用 | `D:\Program Files\dsh` | 正常 |
| PowerShell 7.6.6 | `D:\Program Files\PowerShell-7\pwsh.exe` | **非标准安装位置**，不在 PATH |
| DSH 自带 Python 3.12.14 | `C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe` | 可用，但不在 PATH |
| 系统 PATH 上的 Python 管理器 | `C:\Program Files\PyManager\python.exe` | 会遮蔽用户 PATH 中的 python |

## 根因分析

### 1. pwsh 解析器找不到 PowerShell 7

DSH 的 `pwsh` 工具通过 `@deepseek-ai/dsh-pwsh-local` 的 `resolvePwshPath()` 解析 shell 路径，查找顺序为：

1. `C:\Program Files\PowerShell\7\pwsh.exe`（标准位置）
2. `PATH` 中各目录下的 `pwsh.exe`
3. `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`（Windows PowerShell 5.1 回退）

本机 PowerShell 7 装在**非标准位置** `D:\Program Files\PowerShell-7`，既不在标准位置、也不在 PATH 上，因此解析器静默回退到 Windows PowerShell 5.1——表面能跑，但并非预期的 `pwsh`。

### 2. python 不在 PATH，且用户级添加被系统级遮蔽

`python` 完全不在 PATH 上，无法解析。更隐蔽的是：Windows 合并环境变量时**系统 PATH 优先于用户 PATH**，因此即使把 python 目录加入用户 PATH（`HKCU\Environment`），系统 PATH 上的 `C:\Program Files\PyManager\python.exe`（Python 版本管理器）仍会抢先解析——用户级修复**不会真正生效**。

### 3. 0xC0000135 的语义

`0xC0000135`（`STATUS_DLL_NOT_FOUND`）表示进程已找到、但依赖的动态链接库缺失。在本例中，pwsh / python 均未被正确解析到完整可用的安装，导致启动阶段即失败。

## 修复方案

### 1. pwsh 7.6.6 加入系统 PATH

把 `D:\Program Files\PowerShell-7` 前置写入**系统 PATH**：

```
HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment
  → Path（前置，保留原值类型 REG_SZ）
```

同时写入用户 PATH，双保险。

### 2. python 加入系统 PATH（排在 PyManager 之前）

把 DSH 自带 python 目录前置写入**系统 PATH**，使其排在 `C:\Program Files\PyManager\` 之前，确保 `python` 解析到 DSH 的 3.12.14 而非 PyManager。

### 3. 广播环境变更

调用 `WM_SETTINGCHANGE` 广播，让运行中的进程重新读取环境变量。

## 验证

在 `C:\Windows` 目录下（模拟“其他目录调用”），用注册表构建的“系统 + 用户”有效 PATH 验证：

| 命令 | 解析路径 | 版本 | 退出码 |
|---|---|---|---|
| `pwsh.exe` | `D:\Program Files\PowerShell-7\pwsh.exe` | 7.6.6 | `0` |
| `python.exe` | `...\dependencies\python\python.exe` | 3.12.14 | `0` |

注册表回读确认两个目录均已持久化。

## 注意事项

- 当前已运行的 DSH 进程缓存了旧环境，**需重启 DSH** 后其 shell 工具才使用新解析结果；新启动的进程 / 终端立即生效。
- PyManager 未受影响：仍保留在 PATH 中（位于 DSH python 之后），可通过 `py` 命令使用；只是不再作为默认 `python`。
- 用户级 PATH 添加（`HKCU\Environment`）对 `python` 不足以胜出（系统 PATH 优先），故 python 必须写入系统 PATH 并前置。
- PowerShell 7 建议安装到标准位置 `C:\Program Files\PowerShell\7`，或确保安装目录在 PATH 上。

## 脚本

| 脚本 | 作用 |
|---|---|
| `scripts/add-pwsh-user-path.ps1` | 将 `D:\Program Files\PowerShell-7` 加入用户 PATH 并验证 |
| `scripts/add-pwsh-system-path.ps1` | 将 `D:\Program Files\PowerShell-7` 加入系统 PATH 并验证 |
| `scripts/add-python-user-path.ps1` | 将 DSH python 目录加入用户 PATH 并验证 |
| `scripts/add-python-system-path.ps1` | 将 DSH python 目录前置写入系统 PATH 并验证 |

## 版权与许可

MIT License，见 [LICENSE](LICENSE)。
