# 修复 DSH 无头 shell：pwsh 与 python 的 0xC0000135 排障全记录

> 用 DeepSeek Harness 改版网站时，无头 shell 突然完全不可用：`pwsh` 和 `python` 都启动失败，退出码都是 `0xC0000135`。这篇把完整的定位思路、根因和修复方法讲清楚，文末附可复用的 PowerShell 脚本与开源仓库。

---

## 一、问题：命令一个都跑不了

那天我在 DeepSeek Harness（DSH）的改版网站上用智能体干活，突然发现 shell 完全瘫痪：

- `pwsh` 启动失败
- `python` 启动失败
- 两条命令的退出码一模一样：`0xC0000135`

一个命令都执行不了，等于所有自动化都停摆。查了资料才知道，`0xC0000135` 的十进制是 `3221225781`，对应的系统错误码是 **`STATUS_DLL_NOT_FOUND`**——进程本身找到了，但启动时依赖的动态链接库缺失。

可 PowerShell 和 Python 明明是装好的啊。问题到底出在哪？

## 二、环境盘点：装是装了，但找不到

先把本机环境摸清楚：

| 组件 | 实际位置 | 问题 |
|---|---|---|
| PowerShell 7.6.6 | `D:\Program Files\PowerShell-7\pwsh.exe` | 装在**非标准位置**，既不在标准目录、也不在 PATH 上 |
| DSH 自带 Python 3.12.14 | `C:\Users\Administrator\.dsh\...\dependencies\python\python.exe` | 完全不在 PATH 上 |
| Python 版本管理器 | `C:\Program Files\PyManager\python.exe` | 在系统 PATH 上，会“抢走” `python` |

也就是说：**程序本身都是好的，但操作系统“看不见”它们**。这通常不是程序坏了，而是路径解析出了问题。

## 三、根因：三个隐蔽的坑

### 坑 1：DSH 的 pwsh 解析器只在几个固定地方找

DSH 的 `pwsh` 工具靠 `@deepseek-ai/dsh-pwsh-local` 的 `resolvePwshPath()` 决定用哪个 shell，查找顺序是：

1. `C:\Program Files\PowerShell\7\pwsh.exe`（PowerShell 的标准安装位置）
2. `PATH` 里各个目录下的 `pwsh.exe`
3. `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`（Windows PowerShell 5.1 回退）

本机 PowerShell 7 装在 `D:\Program Files\PowerShell-7`——**既不是标准位置，也不在 PATH 上**。于是解析器“老老实实”退回了 PowerShell 5.1。表面能跑，但根本不是我们想要的 `pwsh` 7。

### 坑 2：用户 PATH 加得再多，也干不过系统 PATH

`python` 更隐蔽。即使把 python 目录加进**用户 PATH**（`HKCU\Environment`），Windows 合并环境变量时**系统 PATH 永远排在用户 PATH 前面**。而系统 PATH 上恰好有 `C:\Program Files\PyManager\python.exe`（一个 Python 版本管理器），于是 `python` 被它抢先解析——用户级修复形同虚设。

### 坑 3：0xC0000135 的误导性

`0xC0000135` 容易让人以为是“缺 DLL、程序坏了”，但真正的坑在**解析层**：shell 解析到了错误/不完整的入口，启动阶段才以 DLL 缺失的形式暴露出来。所以修复的关键不是修程序，而是**修正路径解析**。

## 四、修复：把 pwsh 和 python 放进系统 PATH

### 1. pwsh 7.6.6 进系统 PATH

把 `D:\Program Files\PowerShell-7` **前置写入系统 PATH**：

```
HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment
  → Path（前置，保留原值类型 REG_SZ）
```

同时写一份到用户 PATH，双保险。

### 2. python 进系统 PATH，且排在 PyManager 之前

把 DSH 自带的 python 目录**前置写入系统 PATH**，使其排在 `C:\Program Files\PyManager\` 之前。这样 `python` 才解析到 DSH 的 3.12.14，而不是被 PyManager 拦截。

### 3. 广播环境变更

改完注册表还要**广播 `WM_SETTINGCHANGE`**，让运行中的进程重新读取环境变量，否则已经打开的终端不会立刻感知到变化。

## 五、验证与复盘

在 `C:\Windows` 目录下，用注册表构建的“系统 + 用户”有效 PATH 实测：

| 命令 | 解析路径 | 版本 | 退出码 |
|---|---|---|---|
| `pwsh.exe` | `D:\Program Files\PowerShell-7\pwsh.exe` | 7.6.6 | `0` |
| `python.exe` | `...\dependencies\python\python.exe` | 3.12.14 | `0` |

两条命令都从“别的目录”成功启动，退出码 `0`。注册表回读也确认两个目录已持久化。

**几个值得记住的复盘要点：**

- **系统 PATH 优先于用户 PATH**：想让某个解释器成为默认，必须进系统 PATH，而且要靠前。
- **非标准安装位置**是“看起来装了、实际用不了”的高发原因；能装回标准位置最好，否则必须上 PATH。
- **改注册表 PATH 要广播 `WM_SETTINGCHANGE`**，并重启依赖旧环境的进程（如 DSH），才能彻底生效。
- PyManager 没有被破坏：它还在 PATH 里（在 DSH python 之后），要用它依然可以用 `py` 命令。

## 六、可复用的脚本

| 脚本 | 作用 |
|---|---|
| `scripts/add-pwsh-user-path.ps1` | 将 `D:\Program Files\PowerShell-7` 加入用户 PATH 并验证 |
| `scripts/add-pwsh-system-path.ps1` | 将 `D:\Program Files\PowerShell-7` 加入系统 PATH 并验证 |
| `scripts/add-python-user-path.ps1` | 将 DSH python 目录加入用户 PATH 并验证 |
| `scripts/add-python-system-path.ps1` | 将 DSH python 目录前置写入系统 PATH 并验证 |

每个脚本都会在修改后自动广播环境变更、从 `C:\Windows` 实测解析路径和版本，并回读注册表确认持久化——改完就能看到结果，不用猜。

---

**开源仓库**：[zseagate/dsh-shell-0xC0000135-fix](https://github.com/zseagate/dsh-shell-0xC0000135-fix)（MIT License，含完整 README 与全部脚本）

如果你也遇到过“程序明明装了却跑不起来”，希望这篇能帮你少踩几个坑。遇到类似问题，先把**路径解析**和**系统 PATH 优先级**查一遍，往往就能找到答案。
