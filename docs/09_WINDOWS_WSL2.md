# 09 - 在 Windows 10/11 中安装并打开 Ubuntu（WSL2）

## 先理解：Ubuntu 在哪里运行

WSL2 是 Windows 内置的 Linux 虚拟化环境。安装后，你不需要重启到另一个操作系统，也不需要准备一台 Linux 电脑：

```text
Windows 桌面
├─ Windows 版 VS Code（界面仍然运行在 Windows）
├─ PowerShell
└─ Ubuntu / WSL2（运行 Skynet、Lua、GDB）
```

官方 Skynet v1.8.0 没有原生 Windows build target，所以本项目不使用非官方 Windows fork。现在通过 WSL2 调试和以后部署到真正的 Linux，使用的是同一套 Skynet Runtime。

## 第一步：检查 Ubuntu 是否已经安装

打开开始菜单，搜索 `PowerShell` 或 `终端`，普通权限执行：

```powershell
wsl --list --verbose
```

如果看到类似下面的内容，说明 Ubuntu 已安装：

```text
  NAME      STATE           VERSION
* Ubuntu    Stopped         2
```

此时直接跳到“第三步：打开 Ubuntu”。如果只显示帮助、没有 distribution，或者提示没有已安装的 distribution，就继续安装。

## 第二步：安装 Ubuntu

在开始菜单搜索 `PowerShell`，右键选择“以管理员身份运行”，执行：

```powershell
wsl --install -d Ubuntu
```

命令完成后按提示重启 Windows。重启是安装虚拟化组件的一部分，不要在重启前继续配置工程。

重启后 Ubuntu 通常会自动弹出；如果没有，按下一节手动打开。第一次启动会出现：

```text
Enter new UNIX username:
New password:
Retype new password:
```

这里创建的是 Ubuntu 用户，不是 Windows 账户：

1. 用户名建议使用小写英文，例如 `simbi`。
2. 输入密码时屏幕不会显示星号或字符，这是 Linux 的正常安全行为。
3. 输入完成后按 Enter，再输入一次确认。
4. 记住这个密码，后面执行 `sudo` 会使用它。

## 第三步：打开 Ubuntu

下面四种方式任选一种。

### 方法 A：开始菜单

按 Windows 键，搜索 `Ubuntu`，点击 Ubuntu 应用。看到类似下面的提示符就表示已经进入 Linux：

```text
simbi@computer:~$
```

### 方法 B：Windows Terminal

打开“终端”，点击标签页旁的下拉箭头，选择 `Ubuntu`。

### 方法 C：PowerShell 命令

在任意 PowerShell 窗口执行：

```powershell
wsl -d Ubuntu
```

### 方法 D：直接进入当前工程

在当前工程的 PowerShell 窗口执行：

```powershell
wsl -d Ubuntu
```

进入 Ubuntu 后切换到工程目录：

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
pwd
ls
```

Windows 的 `G:\simbi\dev\skynet-mmo-learning` 在 WSL2 中对应 `/mnt/g/simbi/dev/skynet-mmo-learning`。`/mnt/c`、`/mnt/d`、`/mnt/g` 分别对应 Windows 的 `C:`、`D:`、`G:` 盘。

## 第四步：确认使用 WSL2

退出 Ubuntu 回到 PowerShell：

```bash
exit
```

再检查版本：

```powershell
wsl --list --verbose
```

`VERSION` 应为 `2`。如果是 `1`，执行：

```powershell
wsl --set-version Ubuntu 2
wsl --set-default-version 2
```

## 第五步：在 Ubuntu 安装开发工具

重新打开 Ubuntu，然后执行：

```bash
sudo apt update
sudo apt install -y build-essential autoconf git gdb netcat-openbsd rlwrap
```

逐项验证：

```bash
gcc --version
git --version
gdb --version
nc -h
```

`sudo` 要求输入的就是首次启动 Ubuntu 时创建的密码；输入过程中仍然不会显示字符。

## 第六步：用 Windows 版 VS Code 打开 WSL 工程

先在 Windows 安装 VS Code，再从 extension 市场安装 `WSL`（Microsoft 发布）。推荐使用以下方式打开工程：

1. 打开 Ubuntu。
2. 进入工程目录。
3. 执行 `code .`。

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
code .
```

首次执行时 VS Code 会在 Ubuntu 内安装一个小型 VS Code Server，等待它完成即可。新窗口左下角应显示 `WSL: Ubuntu`。

如果提示 `code: command not found`：

1. 打开 Windows 版 VS Code。
2. 按 `Ctrl+Shift+P`。
3. 执行 `WSL: Connect to WSL`。
4. 连接后选择“文件 → 打开文件夹”。
5. 输入 `/mnt/g/simbi/dev/skynet-mmo-learning`。

## 第七步：构建和运行工程

在 `WSL: Ubuntu` 的 VS Code 窗口中，按 `Ctrl+Shift+P`，执行 `Tasks: Run Task`，依次选择：

1. `Skynet MMO：拉取 v1.8.0`
2. `Skynet MMO：构建`
3. `Skynet MMO：完整测试`
4. `Skynet MMO：启动服务器`

当前工程位于 Windows `G:` 盘，对应 WSL 的 DrvFs mount。部分 DrvFs 配置不允许 WSL Git 执行 `chmod`；拉取 task 会自动转交 Windows Git，得到的仍是官方固定 `v1.8.0` tag，后续 build/test 仍在 Ubuntu 中运行。若手动执行脚本，也会走同一检测逻辑。

也可以在 Ubuntu terminal 中直接执行：

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
./scripts/bootstrap_skynet.sh
./scripts/linux/build.sh
./scripts/linux/test.sh
./scripts/linux/run_server.sh
```

打开第二个 Ubuntu terminal 启动客户端：

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
./scripts/linux/run_client.sh
```

打开第三个 Ubuntu terminal 连接调试控制台：

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
./scripts/linux/debug_console.sh
```

## 也可以继续从 PowerShell 启动

仓库中的 Windows wrapper 会自动把 Windows 路径转换为 WSL 路径：

```powershell
.\scripts\windows\bootstrap.ps1
.\scripts\windows\build.ps1
.\scripts\windows\test.ps1
.\scripts\windows\run_server.ps1
```

另开 PowerShell 运行客户端或 Debug Console：

```powershell
.\scripts\windows\run_client.ps1
.\scripts\windows\debug_console.ps1
```

## 常见问题

### `wsl --install -d Ubuntu` 一直停在 0%

刚开始的 5～10 分钟可能仍在初始化 Windows component 或等待下载，不要同时打开多个安装命令。如果超过 10 分钟仍为 0%，按下面顺序处理：

1. 在当前安装窗口按 `Ctrl+C`，确认旧安装命令已经结束。
2. 打开“任务管理器 → 性能 → CPU”，确认右下角显示“虚拟化：已启用”。如果是“已禁用”，先进入 BIOS/UEFI 打开 Intel VT-x、Intel Virtualization Technology、AMD-V 或 SVM Mode；具体名称由主板厂商决定。
3. 以管理员身份打开一个新的 PowerShell，分别启用两个 Windows component：

```powershell
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

4. 重启 Windows，不能只关闭 PowerShell。
5. 重启后用管理员 PowerShell 绕过 Microsoft Store 下载通道重新安装：

```powershell
wsl --install --web-download -d Ubuntu
```

6. 安装后确认：

```powershell
wsl --list --verbose
```

不要在旧安装进程仍运行时同时执行 `--web-download`，两个安装过程可能争用同一个 component/package 状态。

### 开始菜单搜不到 Ubuntu

先执行 `wsl --list --verbose`。如果没有 Ubuntu，说明安装尚未完成；重新以管理员身份执行 `wsl --install -d Ubuntu` 并重启。

### 安装时 Microsoft Store 下载失败

可以尝试绕过 Store 下载：

```powershell
wsl --install --web-download -d Ubuntu
```

### 出现 `0x80370102` 或虚拟机无法启动

通常表示硬件虚拟化或 Windows 的 Virtual Machine Platform 未启用。先在任务管理器“性能 → CPU”确认“虚拟化：已启用”；若未启用，需要进入 BIOS/UEFI 打开 Intel VT-x 或 AMD-V。然后重新运行 WSL 安装命令。

### Ubuntu 卡住或状态异常

先关闭所有 Ubuntu terminal，然后在 PowerShell 执行：

```powershell
wsl --shutdown
wsl -d Ubuntu
```

`wsl --shutdown` 会停止 WSL 中正在运行的服务器，使用前要确认没有未保存的任务。

### `/mnt/g` 不存在

先确认 Windows 中确实存在 `G:` 盘，然后在 PowerShell 执行 `wsl --shutdown` 并重新进入 Ubuntu。如果工程位于其他盘，把命令中的盘符改成对应的小写路径，例如 `D:` 对应 `/mnt/d`。

完整的 Lua Service 调试、Debug Console 和 GDB 操作见 `docs/16_DEBUGGING.md`。Microsoft 官方安装说明见 `https://learn.microsoft.com/windows/wsl/install`。
