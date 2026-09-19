# Skynet 第一课实操：从空目录写出可登录的 MMO ARPG Server

第一课从 Windows 和 Windows 版 VS Code 已经安装的状态开始。WSL、Ubuntu、Linux 工具链、Skynet、LuaPanda、服务器工程和测试 Client 都由你按照本文安装或编写。完成后要交付一个从空目录逐步写出来、能够处理真实 TCP Login Request 的 Skynet MMO ARPG Server；只运行参考仓库不能通过验收。

本课只实现登录垂直链路：

```text
Test Client
  -> TCP + 2-byte big-endian frame
  -> official gate Service
  -> Watchdog
  -> Auth
  -> PlayerMgr
  -> PlayerAgent
  -> Memory Storage
  -> Login Response
  -> Test Client
```

Scene、Move、AOI、Monster 和 Combat 留到下一阶段。第一课形成的 Service 边界和工程目录会继续使用，不写一次性 Demo。

## 1. 完成标准与固定路径

本机固定使用：

```text
课程文档和旧参考仓库：
G:\simbi\dev\skynet-mmo-learning

新 Ubuntu 虚拟磁盘：
G:\WSL\Ubuntu

本课从空目录创建的新工程：
~/workspace/skynet-mmo-arpg
```

旧参考仓库不能复制到新工程。它只用于阅读本文和在遇到问题时对照。新工程中的脚本、配置、Service、Client 和 Test 都由你按本文创建。

第一课通过验收时，应能拿出以下证据：

- Ubuntu 运行在 WSL2，`ext4.vhdx` 位于 G 盘；
- Windows VS Code 打开的是 `~/workspace/skynet-mmo-arpg`；
- 官方 Skynet v1.8.0 可以从脚本下载并构建；
- 正确 Token 登录返回玩家数据，错误 Token 返回 `AUTH_FAILED`；
- E2E 脚本通过真实端口完成两类登录测试；
- Debug Console 能找到动态创建的 PlayerAgent；
- LuaPanda 能命中 Watchdog 和 PlayerAgent 的业务断点；
- GDB 能停在 `main`、`skynet_start`、`skynet_context_new` 和 `snlua_create`；
- 能顺着一条 Login Request 说明调用方、接收方、yield、恢复位置和状态所有者。

本文固定使用下面三个终端名称。窗口标题和颜色可能不同，判断依据是命令提示符和 `pwd`，不要只凭窗口外观判断：

| 本文名称 | 从哪里打开 | 典型提示符 | 用途 |
|---|---|---|---|
| **终端 A：Windows PowerShell** | Windows Terminal 新建 PowerShell Tab | `PS C:\Users\Administrator>` | 安装和管理 WSL、检查 G 盘；需要时以管理员身份打开 |
| **终端 B：Windows Terminal 的 Ubuntu Shell** | Windows Terminal 新建 Ubuntu Tab；也可以在终端 A 执行 `wsl -d Ubuntu` 后进入 | `simbi@主机名:~$` | Ubuntu 首次初始化、创建工程，并执行一次 `code .` |
| **终端 C：VS Code 的 WSL 集成终端** | 已显示 `WSL: Ubuntu` 的 VS Code 窗口中，选择“终端 → 新建终端” | `simbi@主机名:~/workspace/skynet-mmo-arpg$` | 后续 Git、编译、Server、Client、Test、GDB 和扩展安装 |

终端 B 和终端 C 都在同一个 Ubuntu Distribution 中执行 Bash，看到的是同一套 Linux 文件。区别只是承载它们的界面：终端 B 属于 Windows Terminal，终端 C 位于 VS Code 底部。为了让操作现场可复现，本文在打开工程前使用终端 B，`code .` 打开 WSL Workspace 后统一使用终端 C。

VS Code 也可能在底部打开本地 PowerShell。如果提示符以 `PS` 开头，或者 `pwd` 返回 `C:\...`，它不是终端 C，不要在那里执行本文的 Linux 命令。

## 2. 清点并删除旧 Ubuntu

在**终端 A：Windows PowerShell**检查当前现场：

```powershell
wsl --version
wsl --status
wsl --list --verbose
Get-PSDrive -PSProvider FileSystem
```

记录 Distribution 的准确名称。本文假定它叫 `Ubuntu`；如果现场显示 `Ubuntu-24.04`，后面的命令必须替换成真实名称。

G 盘建议至少保留数十 GB。`ext4.vhdx` 会随着 APT Package、源码、编译产物、Core Dump 和数据库增长，不能按刚安装后的文件大小估算长期空间。

确认旧参考仓库已经 Push。下面命令在仍可使用的**终端 B：Ubuntu Shell**，或者已经连接旧 Ubuntu 的**终端 C：VS Code WSL 集成终端**中执行：

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
git status --short
git remote -v
git log -1 --oneline
```

`git status --short` 应没有输出。若有未提交内容，先停下处理。然后从 PowerShell 检查旧 Ubuntu Home：

如果按 SVN 经验理解这三个 Git 命令：

- `git status` 接近 `svn status`，都用来检查工作副本；Git 还会区分“只在 Working Tree 修改”和“已经进入 Staging Area、等待下次 Commit”的内容。`--short` 使用紧凑格式。
- `git remote -v` 查看远程仓库别名和 URL。SVN Working Copy 天生绑定一个 Repository URL；Git 的本地 Repository 可以配置多个 Remote，惯例把主要远程命名为 `origin`。
- `git log` 查看 Commit History。SVN Log 通常查询服务器；Git Log 默认读取本地 `.git` 中已经拥有的完整历史，不要求连接远程。

```powershell
wsl -d Ubuntu -- bash -lc "du -sh ~; find ~ -maxdepth 2 -type f | head -n 100"
```

确认 `/home` 中没有唯一副本的 SSH Key、未 Push 仓库、数据库或其他需要保留的数据。下面的 `--unregister` 会永久删除该 Distribution 的整个 Linux 文件系统。

关闭所有 Ubuntu Shell 和显示 `WSL: Ubuntu` 的 VS Code 窗口。以管理员身份打开**终端 A：Windows PowerShell**：

```powershell
wsl --shutdown
wsl --unregister Ubuntu
wsl --list --verbose
```

最后一条命令中不应再出现 Ubuntu。不要对未经确认的 Distribution 名称执行注销。

## 3. 准备 WSL2，把 Ubuntu 安装到 G 盘

仍在管理员权限的**终端 A：Windows PowerShell**中执行：

```powershell
wsl --update
wsl --set-default-version 2
```

当前机器已经启用过 WSL，更新平台后重新安装 Ubuntu 即可。一台从未安装 WSL 的 Windows 使用：

```powershell
wsl --install --no-distribution
```

该命令可能要求重启。出现重启提示时先重启 Windows，不要继续安装 Distribution。

如果安装卡在 0%，检查任务管理器“性能 → CPU → 虚拟化”是否为“已启用”，确认没有第二个安装进程，并尝试：

```powershell
wsl --update --web-download
```

硬件虚拟化关闭时，需要在 BIOS/UEFI 打开 Intel VT-x、Intel Virtualization Technology、AMD-V 或 SVM Mode。

检查目标位置：

```powershell
Test-Path -LiteralPath G:\WSL\Ubuntu
```

首次安装应返回 `False`。若返回 `True`，先检查目录内容，不要直接删除：

```powershell
Get-ChildItem -LiteralPath G:\WSL\Ubuntu -Force
```

创建父目录并查看在线 Distribution：

```powershell
New-Item -ItemType Directory -Path G:\WSL -Force
wsl --list --online
```

安装：

```powershell
wsl --install -d Ubuntu --location G:\WSL\Ubuntu --web-download --no-launch
```

参数说明：

- `-d Ubuntu` 选择 Distribution；
- `--location` 指定 VHD 所在目录；
- `--web-download` 避开 Microsoft Store 下载通道；
- `--no-launch` 先安装，稍后再手动完成用户初始化。

验证：

```powershell
wsl --list --verbose
Get-ChildItem -LiteralPath G:\WSL\Ubuntu -Force -Recurse -Filter *.vhdx
```

Ubuntu 的 `VERSION` 应为 `2`，VHDX 应位于 G 盘。如果 `--location` 不被识别，先更新 WSL，不要退回默认安装到 C 盘。

## 4. 初始化 Ubuntu，安装工具链

在普通权限的**终端 A：Windows PowerShell**中启动 Ubuntu：

```powershell
wsl -d Ubuntu
```

执行后不会另开窗口；当前 Tab 会从 PowerShell 切换成 Ubuntu Bash。看到类似下面的提示符后，这个 Tab 就是本文所说的**终端 B：Windows Terminal 的 Ubuntu Shell**：

```text
simbi@MS-WRTLBOKDIUFS:~$
```

如果提示符仍是 `PS C:\...>`，说明还在 PowerShell。后面的 `whoami`、`apt`、`mkdir` 等 Linux 命令都不要在 PowerShell 提示符下执行。

第一次启动会要求：

```text
Enter new UNIX username:
New password:
Retype new password:
```

用户名建议使用小写英文。Linux 输入密码时没有字符或星号回显，输入完成后直接按 Enter。

在刚刚进入的**终端 B**中检查：

```bash
whoami
pwd
uname -a
cat /etc/os-release
df -h /
```

`pwd` 应为 `/home/<你的用户名>`。安装本课工具：

```bash
sudo apt update
sudo apt install -y \
    build-essential \
    autoconf \
    git \
    gdb \
    netcat-openbsd \
    rlwrap \
    curl \
    ca-certificates \
    pkg-config \
    file \
    binutils \
    gh
```

用途如下：

| 工具 | 本课用途 |
|---|---|
| GCC/Make | 编译 Skynet、Bundled Lua 和 LuaSocket |
| Git | 初始化新工程并拉取固定版本的第三方源码 |
| GDB | 调试 Skynet C Runtime |
| Netcat | 连接 Skynet Debug Console |
| rlwrap | 给 Netcat 增加历史和行编辑 |
| file/ldd/binutils | 检查 ELF、动态库和符号 |
| GitHub CLI (`gh`) | 登录 GitHub，为 WSL Git 配置 HTTPS 凭据 |

检查安装结果：

```bash
gcc --version | head -n 1
make --version | head -n 1
git --version
gh --version | head -n 1
gdb --version | head -n 1
nc -h 2>&1 | head -n 2
file --version | head -n 1
```

任何一项出现 `command not found` 都应先修复，不能带着不完整工具链继续。

## 5. 连接 Windows VS Code 与 WSL

在 Windows 版 VS Code 中按 `Ctrl+Shift+X`，安装 Microsoft 发布的 `WSL` 扩展，ID 是：

```text
ms-vscode-remote.remote-wsl
```

这里操作的是 Windows VS Code 的扩展界面，不在任何命令行中输入扩展 ID。

回到**终端 B：Windows Terminal 的 Ubuntu Shell**。你现在看到的提示符应以 `$` 结尾，例如：

```text
simbi@MS-WRTLBOKDIUFS:/mnt/c/Users/Administrator$
```

`/mnt/c/Users/Administrator` 说明当前 Ubuntu Shell 是从 Windows 用户目录进入的，Shell 本身没有问题，但工程不能建在这里。在**终端 B**逐条执行：

```bash
mkdir -p ~/workspace/skynet-mmo-arpg
cd ~/workspace/skynet-mmo-arpg
git init -b main
pwd
ls -la
```

`pwd` 必须输出：

```text
/home/simbi/workspace/skynet-mmo-arpg
```

用户名不是 `simbi` 时，路径中的用户名以实际输出为准。确认路径后，仍在**终端 B**执行：

```bash
code .
```

`git init -b main` 在当前空目录创建本地 Git Repository，并把初始 Branch 命名为 `main`。它只创建 `.git` 元数据，不访问 GitHub。对比 SVN，`svn checkout` 通常同时取得远程内容并建立 Working Copy；`git init` 只是把当前目录变成本地 Repository，远程关系稍后单独配置。

此时工程中只应有 `.git`。第一次执行 `code .` 会在 Ubuntu 中安装 VS Code Server，并打开一个新的 Windows VS Code 窗口。后续操作切换到这个新窗口，终端 B 可以保留，但暂时不再使用。

新 VS Code 窗口左下角必须显示：

```text
WSL: Ubuntu
```

在这个显示 `WSL: Ubuntu` 的 VS Code 窗口中，选择顶部菜单“终端 → 新建终端”，或者按 ``Ctrl+` ``。底部出现的命令行就是**终端 C：VS Code 的 WSL 集成终端**。

先在**终端 C**执行：

```bash
pwd
df -T .
uname -a
```

`pwd` 必须是 `/home/<用户>/workspace/skynet-mmo-arpg`，不能是 `/mnt/c/...` 或 `/mnt/g/...`；`uname -a` 必须输出 Linux 信息。满足这两个条件，才能确认终端 C 的 Shell 和工作目录都正确。源码逻辑上位于 Linux Home，实际存储在 `G:\WSL\Ubuntu\ext4.vhdx` 中。

现在就在**终端 C，也就是 VS Code 底部这个终端**中执行扩展安装命令：

```bash
code --install-extension ms-vscode.cpptools
code --install-extension sumneko.lua
code --install-extension stuartwang.luapanda@3.3.1 --force
code --list-extensions --show-versions
```

不要在终端 A 的 PowerShell 中执行这四条命令，也不需要回到终端 B。此处从终端 C 调用的 `code` CLI 会把扩展安装到当前 WSL Remote 环境。

三者分别负责 C/GDB、Lua Language Server 和 Lua Runtime Debug。最后一条命令应包含类似输出：

```text
ms-vscode.cpptools@...
sumneko.lua@...
stuartwang.luapanda@3.3.1
```

再按 `Ctrl+Shift+X` 打开 VS Code Extensions 面板，相关扩展应位于 `WSL: Ubuntu - 已安装` 分组。Windows 本地安装状态不能替代 WSL 侧安装。

### 5.1 配置这个项目使用的 Git 身份和换行策略

以下配置继续在**终端 C：VS Code 的 WSL 集成终端**中执行。姓名和邮箱替换成你准备写入 Commit 的真实信息：

```bash
cd ~/workspace/skynet-mmo-arpg
git config user.name "你的名字"
git config user.email "你的邮箱"
git config core.autocrlf input
git config core.filemode true
git config --local --list
```

这里不使用 `--global`，避免课程练习无意修改其他仓库。`core.autocrlf=input` 允许提交时把 CRLF 规范为 LF；Shell Script 在 Linux 中必须保持 LF。`core.filemode=true` 让 Git 记录脚本的执行位，后续 `chmod +x` 才能随 Commit 保存。

`git config` 修改 Git 配置。SVN 的用户名通常由访问服务器时的认证决定；Git Commit Author 写入每个本地 Commit，所以即使尚未连接 GitHub，也要先配置 `user.name` 和 `user.email`。`--local` 表示配置只写入当前工程的 `.git/config`。

当前仓库还没有 Commit：

```bash
git status
git log --oneline
```

`git status` 应显示空 Working Tree 中没有可提交文件；`git log` 会提示当前 Branch 还没有 Commit。这不是错误。

## 6. 创建工程骨架

后文没有特别注明时，所有 Linux 命令都在**终端 C：VS Code 的 WSL 集成终端**执行，路径从 `~/workspace/skynet-mmo-arpg` 开始。先创建目录：

```bash
cd ~/workspace/skynet-mmo-arpg
mkdir -p \
    .vscode \
    config \
    scripts/linux \
    service/protocol \
    service/auth \
    service/gateway \
    service/player \
    service/storage \
    lualib/protocol \
    lualib/debug \
    client \
    tests/integration \
    tests/tooling \
    third_party
```

使用 VS Code Explorer 新建下述文件。不要用 Word 或富文本编辑器；Shell Script 必须保存为 UTF-8/LF。

### 6.1 `.gitignore`

完整路径：`.gitignore`

```gitignore
third_party/skynet/
third_party/luapanda/
third_party/luasocket/
third_party/luapanda-runtime/
*.log
core
core.*
```

第三方源码由固定版本脚本恢复，不提交进自己的业务仓库。`.vscode` 不忽略，因为 Task、Launch 和 Lua 搜索路径属于工程配置。

### 6.2 `.gitattributes`

完整路径：`.gitattributes`

```gitattributes
* text=auto
*.sh text eol=lf
Makefile text eol=lf
*.lua text eol=lf
*.json text eol=lf
*.md text eol=lf
```

该文件把跨 Windows/WSL 最容易出问题的脚本换行固定为 LF。若 Shell Script 被保存成 CRLF，常见报错是 `/usr/bin/env: 'bash\r': No such file or directory`。

### 6.3 `README.md` 第一版

完整路径：`README.md`

```markdown
# Skynet MMO ARPG

从空目录逐步实现的 Skynet MMO ARPG Server。

第一阶段目标：通过真实 TCP、2-byte big-endian framing 和 Sproto 完成 Login。
```

### 6.4 `Makefile`

完整路径：`Makefile`

```makefile
.PHONY: bootstrap build test server client debug-console build-luapanda

bootstrap:
	./scripts/bootstrap_skynet.sh

build:
	./scripts/linux/build.sh

test:
	./scripts/linux/test.sh

server:
	./scripts/linux/run_server.sh

client:
	./scripts/linux/run_client.sh

debug-console:
	./scripts/linux/debug_console.sh

build-luapanda:
	./scripts/linux/build_luapanda.sh
```

Recipe 前面必须是 Tab。Makefile 只是稳定入口，具体逻辑放进脚本，Terminal、CI 和 VS Code Task 可以共用同一实现。

### 6.5 建立第一个 Commit

查看刚才创建的文件：

```bash
git status --short
git diff -- .gitignore .gitattributes README.md Makefile
```

Untracked File 不会出现在普通 `git diff` 的内容中，所以还要结合 `git status`。选择性加入暂时已经写完的四个文件：

`git diff` 显示 Working Tree 相对 Staging Area 的文本变化，作用接近 `svn diff`，但 Git 的比较基准会受 Staging Area 影响。这里的新文件尚未被 Track，所以普通 Diff 不显示其正文。

```bash
git add .gitignore .gitattributes README.md Makefile
git status --short
git diff --cached
```

`git add` 只更新 Staging Area，没有提交。`git diff --cached` 检查下一次 Commit 的准确内容。确认后提交：

`git add` 与 `svn add` 名称相同，语义不完全相同。`svn add` 主要把新路径纳入版本控制；`git add` 还会把当前文件内容复制到 Staging Area。已经 Track 的文件修改后也要再次 `git add`，才能把这一版内容放入下一次 Commit。`git diff --cached` 显示 Staging Area 相对当前 `HEAD` 的变化，相当于检查“现在 Commit 会提交什么”。

```bash
git commit -m "chore: initialize skynet mmo arpg project"
git log --oneline --decorate -n 3
```

课程后续不用无脑执行 `git add .`。显式列出文件能避免把日志、临时配置或错误产物混进 Commit。

`git commit` 把 Staging Area 写成一个本地 Commit。这里与 SVN 差异很大：`svn commit` 通常直接写中央服务器；`git commit` 完成后改动仍然只在本机 `.git` 中，直到后面执行 `git push`。`-m` 提供 Commit Message；`git log --oneline --decorate` 用紧凑形式查看 Commit 和 Branch/Tag 指针。

### 6.6 连接远程仓库并完成第一次 Push

本课远程仓库固定为：

```text
https://github.com/simbiwu/SkynetMMOServerTest.git
```

先在 WSL 中登录 GitHub：

```bash
gh auth login
```

交互选项选择 `GitHub.com`、`HTTPS`，使用浏览器登录；当它询问是否为 Git 配置认证时选择同意。完成后执行：

```bash
gh auth status
gh auth setup-git
```

给当前本地仓库增加 Remote：

```bash
git remote add origin https://github.com/simbiwu/SkynetMMOServerTest.git
git remote -v
git ls-remote --heads origin
```

`git remote add origin URL` 给远程 URL 取别名 `origin`，不会下载或上传内容。`git ls-remote --heads origin` 直接查询远程有哪些 Branch Reference，作用类似先查看 SVN Repository 上已有的目录/版本，避免把一个非空远程误当空仓库。

如果最后一条命令没有输出，说明远程尚无 Branch，可以首次 Push：

```bash
git push -u origin main
```

`-u` 建立本地 `main` 与 `origin/main` 的 Upstream 关系，后续在 `main` 上可以直接运行 `git push` 和 `git pull --ff-only`。

`git push` 才把本地 Commit 发送到远程。可以把它理解为 Git 把 SVN 的一次 `commit` 拆成了“本地 `git commit`”和“远程 `git push`”两个动作。`-u` 记录跟踪关系。以后提到的 `git pull --ff-only` 会先取得远程 Commit，再只允许 Fast-forward 更新本地 Branch；它拒绝自动生成意外 Merge Commit。

如果 `git ls-remote --heads origin` 已显示 `refs/heads/main`，不要 Force Push。先执行：

```bash
git fetch origin
git log --oneline --decorate --graph --all -n 20
```

确认远程是否由 GitHub 自动创建了 README、License 或其他有效内容，再决定合并。本文不使用 `--force` 覆盖一个未经检查的远程仓库。

`git fetch origin` 只把远程对象和 `origin/*` Reference 下载到本地，不修改当前 Working Tree。它比 `svn update` 更保守；检查完远程历史后，再决定 Merge、Rebase 或保持不动。

## 7. 写 Skynet 获取与构建脚本

本教程中的脚本注释按“文件内第一次出现”处理：一个 Bash Option、特殊变量、重定向或命令在当前脚本中第一次使用时详细解释；同一脚本后面重复使用时不再解释。不同脚本都是可以独立执行的入口，因此各自保留 Shebang、严格模式和工作目录切换说明，单独打开任何一个文件都能判断它的运行条件。

### 7.1 `scripts/bootstrap_skynet.sh`

```bash
#!/usr/bin/env bash

# 上面的 Shebang 必须位于文件第一行。
# 直接执行 ./scripts/bootstrap_skynet.sh 时，Linux 会通过 /usr/bin/env
# 从当前 PATH 中找到 bash，并用它解释这个文件。

# 打开 Bash 严格模式：
# -e：普通命令返回非 0 时停止脚本；
# -u：读取未定义变量时报错；
# -o pipefail：管道中任意一个命令失败，整条管道都算失败。
set -euo pipefail

# $0 是当前脚本的启动路径。
# dirname "$0" 取得脚本所在目录。
# $(...) 先执行括号内的命令，再把输出替换到当前位置。
# 本脚本位于 scripts/，所以再进入上一级目录就是仓库根目录。
# 使用双引号，避免路径中包含空格时被 Bash 拆成多个参数。
cd "$(dirname "$0")/.."

# 第三方依赖必须固定版本。升级 Skynet 时应显式修改这里并完成回归测试，
# 不能在每次运行脚本时跟随上游 Branch。
# Bash 变量赋值时等号两侧不能有空格；读取变量时使用 "$变量名"。
VERSION="v1.8.0"
DEST="third_party/skynet"

# Makefile 存在时把目录视为已经下载，但仍检查它是否恰好位于目标 Tag。
# [[ ... ]] 是 Bash 条件表达式，-f 判断路径是否为普通文件。
if [[ -f "$DEST/Makefile" ]]; then
    # git -C "$DEST" 表示在目标目录中执行 Git，不改变当前 Shell 目录。
    # 2>/dev/null 把 Standard Error 丢弃；|| 表示左侧失败才执行右侧。
    # describe 失败时执行 true，把这一条复合命令变成成功，让脚本自行诊断版本。
    actual="$(git -C "$DEST" describe --tags --exact-match 2>/dev/null || true)"

    # != 做字符串不等比较。变量全部加双引号，避免空值或空格破坏参数边界。
    if [[ "$actual" != "$VERSION" ]]; then
        # ${actual:-unknown} 表示 actual 未定义或为空时使用 unknown。
        # >&2 把消息写到 Standard Error；exit 1 用非 0 状态结束脚本。
        echo "Skynet 目录存在，但版本不是 $VERSION：${actual:-unknown}" >&2
        exit 1
    fi

    # 版本正确说明 Bootstrap 已完成。exit 0 明确以成功状态结束，不再 Clone。
    echo "Skynet $VERSION already exists at $DEST"
    exit 0
fi

# 目标路径存在却没有 Makefile，可能是中断下载或人工放入的其他文件。
# 脚本拒绝自动覆盖或删除，保留现场给开发者检查。
# -e 判断任意类型的路径是否存在，包括目录、普通文件和 Symbolic Link。
if [[ -e "$DEST" ]]; then
    echo "$DEST 已存在但不是完整 Skynet 源码；请检查后处理，脚本不会覆盖" >&2
    exit 1
fi

# 只取得 v1.8.0 当前 Commit 的浅历史，并初始化 Skynet 记录的 Submodule。
# 行尾反斜杠表示当前命令尚未结束，下一物理行仍属于同一条 git clone。
git clone --recursive --branch "$VERSION" --depth 1 \
    https://github.com/cloudwu/skynet.git "$DEST"

# 再做一次显式恢复，使脚本的依赖条件清楚；若 Clone 期间某个 Submodule
# 没有完成，这里会失败并阻止后续构建。
git -C "$DEST" submodule update --init --recursive

echo "SKYNET_BOOTSTRAP_OK version=$VERSION"
```

关键点：

- `set -euo pipefail` 让错误立即暴露；
- 脚本总是切回工程根目录，避免相对路径依赖当前 Shell；
- 版本固定为 v1.8.0；
- 已存在但不完整或版本错误时停止，不用宽泛删除掩盖现场；
- `--recursive` 获取 Skynet 子模块。

这里首次出现的 Git 用法按 SVN 经验理解：

- `git clone URL DEST` 接近 `svn checkout URL DEST`，都会取得远程内容并创建工作目录；Git 还会在 `DEST/.git` 保存本地 Repository 和 Branch History。
- `git -C <目录> ...` 只是先把 Git 的工作目录切到指定路径再执行子命令，等价于 Shell 先 `cd`，不产生新的 Repository。
- `git describe --tags --exact-match` 检查当前 Commit 是否正好带有目标 Tag。本课用它阻止已有的错误 Skynet 版本蒙混过关。
- `git submodule update --init --recursive` 恢复主 Repository 记录的嵌套依赖。可以类比 SVN External，但 Git Submodule 记录的是另一个 Repository 的精确 Commit；`--init` 建立本地配置，`--recursive` 继续处理嵌套 Submodule。

赋予执行权限并运行：

```bash
chmod +x scripts/bootstrap_skynet.sh
./scripts/bootstrap_skynet.sh
git -C third_party/skynet describe --tags --exact-match
git -C third_party/skynet submodule status
```

最后应显示 `v1.8.0`。

### 7.2 `scripts/linux/build.sh`

```bash
#!/usr/bin/env bash

# 上面的 Shebang 让 Linux 从 PATH 中查找 bash 来解释本文件；它必须是第一行。

# 打开 Bash 严格模式：
# -e：普通命令返回非 0 时停止脚本，编译失败后不会继续打印 BUILD_OK；
# -u：读取未定义变量时报错；
# -o pipefail：管道中任意一个命令失败，整条管道都算失败。
set -euo pipefail

# $0 是当前脚本的启动路径，dirname "$0" 取得 scripts/linux。
# $(...) 是 Command Substitution，把 dirname 的输出放回 cd 命令。
# 本脚本位于 scripts/linux/，所以 /../.. 向上两级回到仓库根目录。
# 整个路径放在双引号中，防止目录名中的空格触发参数拆分。
cd "$(dirname "$0")/../.."

# 新 Clone 中没有 third_party/skynet；先调用 Bootstrap 恢复固定版本源码。
# [[ ... ]] 是 Bash 条件表达式，! 表示取反，-f 判断普通文件是否存在。
# 已有 Makefile 时条件为 False，跳过下载，使日常增量编译保持快速。
if [[ ! -f third_party/skynet/Makefile ]]; then
    ./scripts/bootstrap_skynet.sh
fi

# 使用 Skynet 官方 Makefile 的 linux Target，编译 Runtime、Bundled Lua、
# C Service 和 Lua C Module。-C 只切换 Make 的工作目录，不改变当前 Shell。
make -C third_party/skynet linux

# 只有前面的 Make 成功时才会执行到这里，供人工和 CI 判断构建完成。
echo "BUILD_OK"
```

运行：

```bash
chmod +x scripts/linux/build.sh
./scripts/linux/build.sh
```

`make -C third_party/skynet linux` 使用官方 Linux Target，构建 Skynet Runtime、Bundled Lua、C Service 和 Lua C Module。看到 `BUILD_OK` 后检查：

```bash
file third_party/skynet/skynet
file third_party/skynet/cservice/snlua.so
file third_party/skynet/luaclib/skynet.so
ldd third_party/skynet/skynet
./third_party/skynet/3rd/lua/lua -v
```

三个关键产物：

| 文件 | 加载方 | 用途 |
|---|---|---|
| `third_party/skynet/skynet` | Shell/GDB | Linux ELF 主程序 |
| `third_party/skynet/cservice/snlua.so` | Skynet Module Loader | 创建持有 Lua State 的 snlua Service |
| `third_party/skynet/luaclib/skynet.so` | Lua `require` | 把 Lua API 接到 Skynet Core |

本课 Client 和 Test 也使用 `third_party/skynet/3rd/lua/lua`，不依赖 Ubuntu System Lua。

## 8. 写第一个最小 Skynet Service

这一节只打通一条启动链：Shell 启动 Skynet ELF，ELF 读取配置，C Runtime 创建官方 Bootstrap Service，Bootstrap 再创建我们编写的 Main Service。暂时没有监听端口，也没有 Login 业务。验收依据是 Main Service 的日志确实经过 Skynet Logger 输出，并且你能解释该日志产生前后发生了什么。

### 8.1 检查当前操作现场

下面命令在**终端 C：VS Code 的 WSL 集成终端**执行。先确认终端、目录、Branch 和构建产物：

```bash
cd ~/workspace/skynet-mmo-arpg
pwd
uname -a
git branch --show-current
test -x third_party/skynet/skynet && echo "SKYNET_BINARY_OK"
test -f third_party/skynet/cservice/snlua.so && echo "SNLUA_OK"
test -f third_party/skynet/luaclib/skynet.so && echo "LUA_API_OK"
```

此时应满足：

```text
pwd                         /home/simbi/workspace/skynet-mmo-arpg
uname -a                    输出 Linux/WSL2 信息
git branch --show-current   main
三个产物检查                全部输出 *_OK
```

只要有一项不符合，就先回到前面的环境或构建步骤。特别是 `pwd`：本节所有配置都使用相对路径，Server Process 的 Current Working Directory 错了，后面的 `./service/?.lua` 和 `./third_party/skynet/...` 会一起失效。

在 VS Code 左侧按 `Ctrl+Shift+E` 打开 Explorer。最上方根目录应是 `skynet-mmo-arpg`，其中已经存在 `config`、`service` 和 `scripts/linux`。接下来通过 Explorer 创建文件；每个文件都要确认保存为 UTF-8、LF。

### 8.2 写 Runtime 配置 `config/game.lua`

在 Explorer 中右键 `config` 目录，选择“新建文件”，输入：

```text
game.lua
```

完整仓库路径：`config/game.lua`

填入下面内容并按 `Ctrl+S` 保存：

```lua
-- 所有相对路径都以 Skynet Process 的 Current Working Directory 为起点。
-- scripts/linux/run_server.sh 会先切回仓库根目录，再启动 ELF。
root = "./"
skynet_root = root .. "third_party/skynet/"

-- snlua Loader 用 luaservice 查找一个 Service 的 Lua 入口文件。
-- 项目目录放前面，因此 "main" 会先命中 ./service/main.lua；
-- 项目没有的 "bootstrap" 会继续命中官方 service/bootstrap.lua。
luaservice = root .. "service/?.lua;"
    .. skynet_root .. "service/?.lua"

-- 每个 snlua Service 创建自己的 Lua State 后，都由这个官方 Loader
-- 根据 Service Name 搜索并执行对应的入口文件。
lualoader = skynet_root .. "lualib/loader.lua"

-- 普通 Lua Module 的搜索路径，例如 require "skynet"。
lua_path = root .. "lualib/?.lua;"
    .. root .. "lualib/?/init.lua;"
    .. skynet_root .. "lualib/?.lua;"
    .. skynet_root .. "lualib/?/init.lua"

-- Lua require 加载的 Native Module，例如 require "skynet.core"。
lua_cpath = skynet_root .. "luaclib/?.so"

-- Skynet C Service Module 的搜索路径。snlua 属于这一类。
cpath = skynet_root .. "cservice/?.so"

-- 创建 8 个业务 Worker Thread。Monitor、Timer、Socket Thread 不计入此数。
thread = 8

-- 本课使用单节点模式，不启用旧 Harbor 多节点组件。
harbor = 0

-- C Runtime 的第一个 Service：加载 snlua.so，并把 "bootstrap" 作为参数。
bootstrap = "snlua bootstrap"

-- 官方 bootstrap.lua 读取 start，再创建项目的 Main Service。
start = "main"

-- 后续章节使用的业务配置。当前最小 Main 尚未读取这些字段。
gate_host = "127.0.0.1"
gate_port = 8888
max_client = 1024
debug_console_port = 8000
storage_pool = 2
```

这个文件虽然使用 Lua 语法，但它不在任何业务 Service 的 Lua State 中执行。`third_party/skynet/skynet-src/skynet_main.c::main` 创建一个临时配置 Lua State，执行内嵌的 `load_config`，再用它读取 `config/game.lua`。`_init_env` 遍历配置 Table，把值转成 Skynet Environment String，随后 `lua_close` 立即销毁配置 State。以后业务代码调用 `skynet.getenv("gate_port")` 得到的是字符串 `"8888"`，不是这里原来的 Lua Number。

四种搜索路径解决不同的加载问题：

| 配置项 | 谁使用 | 当前会加载的例子 |
|---|---|---|
| `cpath` | Skynet C Module Loader | `cservice/snlua.so` |
| `luaservice` | `lualib/loader.lua` | 官方 `service/bootstrap.lua`、项目 `service/main.lua` |
| `lua_path` | Lua `require` | `lualib/skynet.lua` |
| `lua_cpath` | Lua `require` | `luaclib/skynet.so`，模块名是 `skynet.core` |

`?` 是待替换的 Module 或 Service Name，分号分隔多个候选 Pattern。搜索顺序有实际影响：项目 `service/?.lua` 放在官方路径前面，所以不要在项目中随意创建 `service/bootstrap.lua`，否则它会遮蔽官方 Bootstrap。

保存后在**终端 C**检查文件确实位于预期路径：

```bash
realpath config/game.lua
file config/game.lua
sed -n '1,80p' config/game.lua
```

`realpath` 应位于 `/home/simbi/workspace/skynet-mmo-arpg/config/game.lua`，`file` 不应报告 `with CRLF line terminators`。

### 8.3 写 Main Service `service/main.lua`

在 Explorer 中右键 `service` 目录，选择“新建文件”，输入：

```text
main.lua
```

完整仓库路径：`service/main.lua`

填入并保存：

```lua
local skynet = require "skynet"

skynet.start(function()
    skynet.error("[Main] minimal bootstrap reached")
    skynet.exit()
end)
```

执行到这个文件时，Runtime 已经为 Main 创建了独立的 snlua Service、Service Handle、Mailbox 和 Lua State。代码按下面的顺序发生：

1. `local skynet = require "skynet"` 在 Main 的 Lua State 中加载 `third_party/skynet/lualib/skynet.lua`。该 Module 随后加载 `skynet.core`，通过 `lua_cpath` 命中 `third_party/skynet/luaclib/skynet.so`，Lua 代码由此接入 C Runtime。
2. `skynet.start(function() ... end)` 注册这个 Service 的消息回调，并安排一个 0 Tick Timer。当前 Lua 文件加载完成后，Runtime 才在 Main 的初始化 coroutine 中调用传入的函数。这里不能把 `skynet.start` 理解成新建 OS Thread。
3. `skynet.error(...)` 把日志消息发给 Skynet Logger Service。它没有直接调用 Lua `print`；日志前面的 Service Address 由 Logger 路径附加。
4. `skynet.exit()` 注销当前 Main Service，清理它等待或持有的 coroutine，并通知 `.launcher` 删除该 Service 的生命周期记录。

第四步只退出 Main Service，不会自动关闭整个 Skynet Process。官方 `bootstrap.lua` 在创建 Main 之前已经创建 `.launcher`、`.cslave`、`DATACENTER` 和 `service_mgr` 等基础 Service；它们仍然存活，所以本节运行后进程会继续停留在前台。这一点和传统 C++ `main()` Return 后整个进程结束不同。

当前 Main 不持有业务状态，也没有 `skynet.call`，因此没有业务 yield 后状态失效的问题。它的初始化函数由一个 coroutine 执行；`skynet.exit()` 最终会让该 coroutine 以 `QUIT` 原因交回 Runtime。

### 8.4 写统一启动脚本 `scripts/linux/run_server.sh`

在 Explorer 中右键 `scripts/linux`，新建：

```text
run_server.sh
```

完整仓库路径：`scripts/linux/run_server.sh`

填入并保存：

```bash
#!/usr/bin/env bash

# 上面的 Shebang 必须位于第一行；直接执行脚本时，Linux 会从 PATH 中
# 找到 bash，并用它解释本文件。

# 打开 Bash 严格模式：
# -e：普通命令返回非 0 时停止脚本；
# -u：读取未定义变量时报错；
# -o pipefail：管道中任意一个命令失败，整条管道都算失败。
set -euo pipefail

# $0 是当前脚本的启动路径，dirname "$0" 取得 scripts/linux。
# $(...) 会先执行 dirname，再把输出替换进 cd 的参数。
# 本脚本位于 scripts/linux/，/../.. 向上两级就是仓库根目录。
# 双引号保护整个路径，避免路径中的空格被 Bash 拆成多个参数。
cd "$(dirname "$0")/../.."

# $1 是第一个位置参数。
# ${1:-config/game.lua} 表示 $1 未提供或为空时使用右侧默认值。
# 未传参数时使用开发配置；以后也可以显式传入 config/test.lua。
CONFIG="${1:-config/game.lua}"

# exec 用 Skynet Process 替换当前 Shell Script Process，不额外保留一层 Bash；
# Process PID 不变，退出码和 Ctrl+C 等 Signal 可以直接传递。
# "$CONFIG" 保证配置路径即使含有空格也作为一个完整参数传给 Skynet。
exec ./third_party/skynet/skynet "$CONFIG"
```

这里的 `cd` 解决了前面配置中相对路径的起点问题。`dirname "$0"` 得到脚本所在的 `scripts/linux`，再经过 `../..` 回到仓库根目录。如果没有这一步，从 `~/workspace` 调用脚本时，`root = "./"` 会错误地指向 `~/workspace`。

`set -euo pipefail` 分别要求命令失败时停止、未定义变量时报错、Pipeline 中任一命令失败都算失败。`exec` 不再额外保留一个等待 Skynet 的 Bash Process，因此在 VS Code Terminal 按 `Ctrl+C` 时，SIGINT 直接到达 Skynet。

在**终端 C**检查 Shell Syntax、换行和执行权限：

```bash
bash -n scripts/linux/run_server.sh
file scripts/linux/run_server.sh
chmod +x scripts/linux/run_server.sh
test -x scripts/linux/run_server.sh && echo "RUN_SCRIPT_OK"
```

`bash -n` 没有输出表示 Syntax Check 通过；它不会真正启动 Server。`RUN_SCRIPT_OK` 表示 Linux Executable Bit 已设置。

### 8.5 第一次运行并确认 Process 没有意外退出

把当前 VS Code 集成终端重命名为 `MINI-SERVER`，在其中执行：

```bash
cd ~/workspace/skynet-mmo-arpg
./scripts/linux/run_server.sh
```

日志中至少应出现：

```text
[Main] minimal bootstrap reached
```

终端随后仍被 Skynet 占用，没有重新出现 `$` 提示符，这是预期行为。Main Service 已经退出，但基础 Service 仍使 Process 存活。

在同一个 VS Code WSL Workspace 中选择“终端 → 新建终端”，把新终端命名为 `INSPECT`，执行：

```bash
cd ~/workspace/skynet-mmo-arpg
ps -ef | grep '[t]hird_party/skynet/skynet'
```

应看到参数中带有 `config/game.lua` 的 Skynet Process。回到 `MINI-SERVER` 按 `Ctrl+C`，再在 `INSPECT` 中执行相同的 `ps` 命令，此时不应再看到该 Process。

如果运行后直接返回 `$`，先看退出前的最后一条错误，不要只重复启动。常见分层如下：

| 错误特征 | 失败层 | 检查位置 |
|---|---|---|
| `Need a config file` | ELF 参数 | `run_server.sh` 是否传入 `config/game.lua` |
| `config/game.lua: No such file` | Current Working Directory | 脚本的 `cd .../../..` |
| 无法加载 `snlua` | C Service Module | `cpath` 和 `cservice/snlua.so` |
| 无法加载 `loader.lua` | snlua 初始化 | `lualoader` |
| 找不到 `bootstrap.lua` 或 `main.lua` | Service Loader | `luaservice` 的两个 Pattern 和顺序 |
| `module 'skynet' not found` | Lua Module | `lua_path` |
| `module 'skynet.core' not found` | Lua Native Module | `lua_cpath` 和 `luaclib/skynet.so` |

### 8.6 沿源码还原这条最小启动链

这次运行实际经过以下对象：

```text
MINI-SERVER Bash
  exec third_party/skynet/skynet config/game.lua

Skynet Process / 主线程
  third_party/skynet/skynet-src/skynet_main.c::main
  创建临时配置 Lua State
  执行 config/game.lua
  _init_env 写入 Skynet Environment
  lua_close 销毁配置 State
  调用 third_party/skynet/skynet-src/skynet_start.c::skynet_start

Skynet Runtime
  初始化 Handle、Global Queue、Timer、Socket 和 Worker Thread
  skynet_context_new("snlua", "bootstrap")

Bootstrap snlua Service / 独立 Lua State
  third_party/skynet/service-src/service_snlua.c::snlua_create
  third_party/skynet/service-src/service_snlua.c::init_cb
  third_party/skynet/lualib/loader.lua
  third_party/skynet/service/bootstrap.lua
  创建基础 Service，再请求创建 start="main"

Main snlua Service / 另一个独立 Lua State
  再次执行 third_party/skynet/lualib/loader.lua
  命中项目 service/main.lua
  require "skynet"
  skynet.start 的初始化 coroutine 输出日志
  skynet.exit 只注销 Main Service
```

配置 State、Bootstrap State 和 Main State 是三个不同的 `lua_State`。普通 Global/Table 不会在它们之间共享。`start = "main"` 也不是 Lua `require "main"`：它是官方 Bootstrap 发起一次 Service 创建，最后得到一个新的 Service Handle、Mailbox 和 Lua State。

Worker Thread 与 Main Service 没有永久绑定关系。初始化 coroutine 被某个 Worker 调度；它如果发生 yield，恢复时可能由另一个 Worker 继续执行。当前代码只有初始化和退出，没有共享业务状态，但从这一节开始就应把 Process、Worker、Service、Lua State 和 coroutine 分开观察。

### 8.7 用 GDB确认 C Runtime 入口

先确认 `MINI-SERVER` 已停止。下面命令仍在**终端 C**执行：

```bash
cd ~/workspace/skynet-mmo-arpg
gdb --args ./third_party/skynet/skynet config/game.lua
```

进入 `(gdb)` 后输入：

```gdb
set pagination off
break main
break skynet_start
run
```

停在 `main` 后检查 ELF 收到的配置参数：

```gdb
print argc
print argv[1]
continue
```

`argv[1]` 应指向 `config/game.lua`。停在 `skynet_start` 后执行：

```gdb
print config->thread
print config->module_path
print config->bootstrap
continue
```

应分别观察到 `8`、`./third_party/skynet/cservice/?.so` 和 `snlua bootstrap`。看到 Main 日志后按 `Ctrl+C` 回到 GDB，结束本次 Process：

```gdb
kill
quit
```

这里先验证配置进入 C Runtime 的边界。`snlua_create`、动态库 Pending Breakpoint 和各线程调用栈会在第 22 节继续处理；LuaPanda 也暂时不介入最小启动链。

### 8.8 检查差异并提交可运行基线

在**终端 C**执行：

```bash
git status --short
git diff
git add config/game.lua service/main.lua \
    scripts/bootstrap_skynet.sh scripts/linux/build.sh scripts/linux/run_server.sh
git diff --cached
git commit -m "build: bootstrap minimal skynet service"
git log --oneline --decorate --graph -n 5
```

提交前的 `git diff --cached` 中应只有本节三个文件和前一节两个构建脚本，不应出现 `third_party/skynet`。第三方源码被 `.gitignore` 排除；Commit 保存固定版本和恢复方法，不保存本机编译目录。

现在为 Login 垂直链路建立独立 Branch：

```bash
git switch -c feature/login
git branch --show-current
git push -u origin feature/login
```

后续协议、Storage、Player、Gateway 和 Test Commit 都进入 `feature/login`。测试通过前不合并到 `main`。

`git switch -c feature/login` 从当前 Commit 创建并切换到新 Branch。Git Branch 是指向 Commit 的轻量 Reference，和传统 SVN 中通过复制目录形成 Branch 的实现不同。`git branch --show-current` 只打印当前 Branch 名称，用来防止把 Login 开发误提交到 `main`。

## 9. 定义 Login 协议和 TCP Frame

本课使用 Sproto。TCP 是 Byte Stream，一次 `send` 与一次 `recv` 没有消息边界，所以每个 Sproto Payload 前放置 2-byte big-endian 长度。官方 Gate 按同样的 `s2` 形式切包，Client 也必须使用相同规则。

先把网络上的三层数据分开。后面抓包或移植 Unity/H5 Client 时，不能把三层的长度、端序和职责混在一起：

```text
TCP Frame
  [2-byte big-endian payload length]
    ↓ payload
Sproto RPC Envelope（.package）
  [type][session]
    ↓ request/response body
业务结构
  login.request 或 login.response
```

最外层两字节由本工程与官方 Gate 的 Netpack 约定，用大端序表示 TCP Frame 长度。拆包代码位于 `third_party/skynet/lualib-src/lua-netpack.c` 的 `read_size` 和 `filter_data_`。Sproto 自己的 16/32/64 位字段、字符串长度和数组长度使用小端序，编码实现位于 `third_party/skynet/lualib-src/sproto/sproto.c` 的 `sproto_encode`、`sproto_decode`、`encode_array` 和 `decode_array`。一个 Packet 同时出现两种端序是正常结果：外层 Frame 属于 Transport，内层字段属于 Sproto Wire Format。

### 9.1 `lualib/protocol/schema.lua`

```lua
-- 当前 Lua Client 与 Server 读取同一份 Sproto Schema 源定义。
-- [[...]] 是 Lua Long String Literal，不是注释；--[[...]] 才是 Lua Block Comment。
-- Long String 内部按 Sproto Grammar 解析，行注释使用 #，不能使用 Lua 的 --。
local M = {}

M.c2s = [[
# Sproto Package Header：type 标识协议，session 关联 Request 与 Response。
.package {
    type 0 : integer
    session 1 : integer
}

# 第一阶段的 Client -> Server 登录协议，协议 ID 为 1。
login 1 {
    request {
        player_id 0 : integer
        token 1 : string
    }
    response {
        code 0 : integer
        message 1 : string
        player_id 2 : integer
        name 3 : string
        level 4 : integer
        gold 5 : integer
    }
}
]]

-- 第一阶段没有 Server Push，但仍建立独立 S2C Schema，后续 AOI、Chat、
-- Kick 等 Push 直接增加在这里，不改变 Client host/attach 方向。
M.s2c = [[
# S2C 使用独立 Package，后续 Server Push 都在这个 Schema 中定义。
.package {
    type 0 : integer
    session 1 : integer
}
]]

return M
```

这里有两层 Parser，注释语法由当前处理这一层文本的 Parser 决定：

```text
Lua Parser
  读取 lualib/protocol/schema.lua
  把 [[...]] 构造成普通 Lua String
  此时 String 内的 # 和 -- 都只是字符

Sproto Parser
  sprotoparser.parse(schema.c2s)
  按 Sproto Grammar 解析这段 String
  只把 # 到行尾识别为注释
```

Lua 的两种写法不要混淆：

```lua
-- 这是 Lua 单行注释

--[[
这是 Lua 块注释
]]

local text = [[
这是一段 Lua Long String，不是注释
]]
```

`[[...]]` 在整个 Lua 5.x 系列中都可用，Lua 5.0 已经支持这种写法。本工程使用 Skynet Bundled Modified Lua 5.4.7。Lua 5.1 开始还可以使用带等号层级的 Long Bracket，例如 `[=[...]=]`、`[==[...]==]`；当字符串正文自身包含 `]]` 时，用更高层级可以避免提前结束字符串：

```lua
local text = [=[
正文可以包含普通的 ]]
只有 ]=] 才会结束当前 Long String
]=]
```

选择 Long String 是因为 Sproto Schema 本身是多行 DSL。使用 `[[...]]` 可以保留换行，也不需要给每一行加引号和 `\n`。Lua 完成这一层解析后，`M.c2s` 就是一个普通字符串，稍后由 `service/protocol/protoloader.lua` 传给 `sprotoparser.parse`。

下面写法会失败：

```lua
M.c2s = [[
-- 这里不是 Lua 注释；两个减号会原样进入 Sproto Parser
.package {
    type 0 : integer
    session 1 : integer
}
]]
```

原因是 Lua Parser 不会进入 Long String 内部寻找注释。Sproto Parser 收到 `-- 这里不是 Lua 注释`，而它的 Grammar 不接受以 `-` 开头的 Token，最终报告 Syntax Error。

正确的 Sproto 注释写法是：

```sproto
# 这一行由 Sproto Parser 忽略
.package {
    type 0 : integer   # Inline Comment 也使用井号
    session 1 : integer
}
```

这不是课程自行约定的格式。`third_party/skynet/lualib/sprotoparser.lua` 中的 `line_comment` 明确定义为从 `#` 开始，一直读取到换行或文件结尾；`sparser.parse` 使用这套 Grammar 解析传入字符串。

`.package` 的 `type` 标识协议编号，`session` 把 Response 对回 Request。`login 1` 中的 `1` 是 C2S 协议 ID。字段后面的数字是 Sproto Field Tag；上线协议不能随意复用或改变已有 Tag。

这里说的“共用”只适用于本课的 Lua Test Client：它和 Server 都能 `require "protocol.schema"`。Unity 或 H5 无法加载这个 Lua Module。商业工程通常保留一份权威 `.sproto` 源定义，再由构建工具为各端生成产物：

```text
protocol/*.sproto（唯一权威源）
  ├─ Skynet Server：解析或加载编译后的 Schema
  ├─ Unity Client：生成 C# 类型和静态 Codec
  └─ H5 Client：生成 TypeScript 类型和静态 Codec
```

各端必须共享协议 ID、Field Tag、字段类型和兼容规则，不要求共享同一种源码语言。已经发布的 Field Tag 不修改、不复用；删除字段后仍保留该 Tag；新增字段按可缺省字段处理。旧 Decoder 应能跳过自己不认识的新增字段。

### 9.2 `lualib/protocol/frame.lua`

```lua
local socket = require "skynet.socket"

local M = {}

function M.pack(payload)
    assert(type(payload) == "string", "payload must be a string")
    assert(#payload <= 0xffff, "packet exceeds 2-byte frame limit")
    return string.pack(">s2", payload)
end

function M.write(fd, payload)
    return socket.write(fd, M.pack(payload))
end

return M
```

`>s2` 表示 big-endian、2-byte Length Prefix。Server 输出 Response 时必须加这个 Header。Gate 收包时已经去掉 Header，Watchdog 的 `SOCKET.data(fd, msg)` 得到的是纯 Sproto Payload，所以不能再次去头。

两字节无符号长度的上限是 `65535`。`M.pack` 在写 Socket 前拒绝更大的 Payload，避免长度截断。正式业务里的场景快照、邮件列表或批量同步接近这个上限时，应拆分消息并限制单次元素数量，不能只把断言删除。

Sproto 还提供 `sproto.pack`/`sproto.unpack`，它们按 8 字节分组压缩大量零字节，实现在 `third_party/skynet/lualib-src/sproto/sproto.c` 的同名函数中。本课没有调用这两个函数，线上格式就是：

```text
[2-byte big-endian length][原始 Sproto payload]
```

如果以后启用 `sproto.pack`，Client 与 Server 必须同时修改并通过互通测试，不能根据 Packet 内容猜测是否压缩。`pack/unpack` 也不能替代 TCP Length Prefix；一个处理内容压缩，一个处理 Byte Stream 的消息边界。

### 9.3 `service/protocol/protoloader.lua`

```lua
local skynet = require "skynet"
local sprotoparser = require "sprotoparser"
local sprotoloader = require "sprotoloader"
local schema = require "protocol.schema"

skynet.start(function()
    local c2s = sprotoparser.parse(schema.c2s)
    local s2c = sprotoparser.parse(schema.s2c)

    sprotoloader.save(c2s, 1)
    sprotoloader.save(s2c, 2)

    skynet.error("[ProtocolLoader] schemas ready slots=1/2")

    -- 不退出。sprotoloader Slot 依赖持有编译结果的 Service 继续存活。
end)
```

Slot 约定是：

```text
1 = Client -> Server
2 = Server -> Client
```

Watchdog 和 PlayerAgent 通过 `sprotoloader.load(1)` 取得相同的 C2S Schema。ProtocolLoader 必须在 Gate 开放端口前启动，避免 Client 已经发包而 Slot 尚未初始化。

### 9.4 暂时把 ProtocolLoader 接入 Main

把 `service/main.lua` 改为：

```lua
local skynet = require "skynet"

skynet.start(function()
    skynet.error("[Main] starting protocol")
    skynet.uniqueservice("protocol/protoloader")
    skynet.error("[Main] protocol ready")

    -- 后面还要继续创建 Storage、Player、Auth 和 Gate，暂时退出。
    skynet.exit()
end)
```

运行：

```bash
./scripts/linux/run_server.sh
```

应该依次看到 ProtocolLoader 和 Main 日志。进程这次不会立即退出，因为 ProtocolLoader 按设计继续存活。按 `Ctrl+C` 停止。

检查并提交：

```bash
git status --short
git diff
git add lualib/protocol/schema.lua lualib/protocol/frame.lua \
    service/protocol/protoloader.lua service/main.lua
git diff --cached
git commit -m "feat: define login sproto protocol"
```

## 10. 写内存 Storage

第一阶段不引入 MySQL，但 PlayerAgent 不直接构造玩家。Storage 的 RPC Surface 以后可以换成数据库 Worker，登录调用链不需要改写。

### 10.1 `service/storage/memory_worker.lua`

```lua
local skynet = require "skynet"

local CMD = {}
local players = {}

local function clone_player(p)
    if not p then
        return nil
    end
    return {
        player_id = p.player_id,
        name = p.name,
        level = p.level,
        gold = p.gold,
    }
end

function CMD.start(conf, worker_index)
    local seed = {
        [10001] = {
            player_id = 10001,
            name = "Knight10001",
            level = 10,
            gold = 10000,
        },
        [10002] = {
            player_id = 10002,
            name = "Mage10002",
            level = 8,
            gold = 8000,
        },
    }

    for player_id, player in pairs(seed) do
        if (player_id % conf.pool) + 1 == worker_index then
            players[player_id] = clone_player(player)
        end
    end

    skynet.error("[MemoryWorker] started index=", worker_index)
    return true
end

function CMD.load_player(player_id)
    local player = players[player_id]
    if not player then
        return false, "PLAYER_NOT_FOUND"
    end
    return true, clone_player(player)
end

function CMD.save_player(player)
    players[player.player_id] = clone_player(player)
    return true
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command],
            "unknown memory command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
```

`players` 只存在于这个 MemoryWorker 的 Lua State。`clone_player` 很重要：虽然跨 Service 消息会序列化参数，返回独立数据仍然把 Storage 的接口语义写清楚，避免以后把同进程 Module Table 或其他共享对象误当成可交给调用方修改的记录。

Dispatcher 中：

- `session ~= 0` 表示调用方使用 `skynet.call` 并等待 Response；
- `skynet.retpack` 把多个 Lua 返回值编码回调用方；
- `source` 是发送方 Service Address，本例不用于授权。

### 10.2 `service/storage/storage_mgr.lua`

```lua
local skynet = require "skynet"

local CMD = {}
local workers = {}

local function get_worker(player_id)
    assert(#workers > 0, "storage pool is not started")
    return workers[(player_id % #workers) + 1]
end

function CMD.start(conf)
    assert(conf.pool and conf.pool > 0, "storage pool must be > 0")

    for index = 1, conf.pool do
        local worker = skynet.newservice("storage/memory_worker")
        skynet.call(worker, "lua", "start", conf, index)
        workers[index] = worker
    end

    skynet.error("[StorageMgr] workers=", #workers)
    return true
end

function CMD.load_player(player_id)
    return skynet.call(get_worker(player_id), "lua", "load_player", player_id)
end

function CMD.save_player(player)
    return skynet.call(get_worker(player.player_id), "lua", "save_player", player)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command],
            "unknown storage manager command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
```

StorageMgr 只负责按 `player_id` 选 Worker。一次 `load_player` 会经过：

```text
PlayerAgent coroutine
  -> call StorageMgr，PlayerAgent yield
  -> StorageMgr handler
  -> call MemoryWorker，StorageMgr yield
  -> MemoryWorker 返回
  -> StorageMgr 恢复并转发返回值
  -> PlayerAgent 恢复
```

这是一个两层同步 RPC。当前登录是低频路径，教学阶段可以接受；后续如果 Profile 显示 Manager 成为热点，可以在 Agent 创建时缓存 Worker Address，不能只凭“多一跳”就提前改架构。

### 10.3 把 Storage 接入 Main

`service/main.lua` 暂时改为：

```lua
local skynet = require "skynet"

local function getenv_int(name, default)
    local value = skynet.getenv(name)
    return assert(tonumber(value or tostring(default)))
end

skynet.start(function()
    skynet.error("[Main] starting services")

    skynet.uniqueservice("protocol/protoloader")

    local storage_mgr = skynet.uniqueservice("storage/storage_mgr")
    skynet.call(storage_mgr, "lua", "start", {
        pool = getenv_int("storage_pool", 2),
    })

    skynet.error("[Main] storage ready")
    skynet.exit()
end)
```

运行后应该看到两个 MemoryWorker。停止服务器并提交：

```bash
git add service/storage/memory_worker.lua \
    service/storage/storage_mgr.lua service/main.lua
git diff --cached
git commit -m "feat: add in-memory player storage"
```

## 11. 写开发期 Auth Service

完整路径：`service/auth/auth.lua`

```lua
local skynet = require "skynet"

local CMD = {}

function CMD.verify(player_id, token)
    if not math.tointeger(player_id) then
        return false
    end
    return token == "dev:" .. tostring(player_id)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command],
            "unknown auth command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
```

开发 Token 规则是：

```text
player_id=10001
token=dev:10001
```

它只用于把 Login 链路跑通，不代表商业服认证方案。生产中通常由 Login/Account 服务签发一次性凭证，Game Server 校验并消费；客户端自报的 `player_id` 不能独立作为身份依据。

先提交 Auth：

```bash
git add service/auth/auth.lua
git diff --cached
git commit -m "feat: add development login authentication"
```

## 12. 写 PlayerAgent：玩家数据的在线所有者

第一阶段每个在线玩家对应一个 PlayerAgent Service。它持有从 Storage 加载的玩家快照和当前连接标识。Scene 尚未加入，所以 PlayerAgent 暂时只完成 Load、Bind 和 Offline。

完整路径：`service/player/player_agent.lua`

```lua
local skynet = require "skynet"

local CMD = {}

local STATE_LOADING = "LOADING"
local STATE_LOADED = "LOADED"
local STATE_ONLINE = "ONLINE"
local STATE_CLOSING = "CLOSING"

local state = STATE_LOADING
local player
local storage_mgr
local player_mgr
local client_fd
local client_connection_id

local function login_info()
    return {
        player_id = player.player_id,
        name = player.name,
        level = player.level,
        gold = player.gold,
    }
end

function CMD.load(conf)
    assert(state == STATE_LOADING, "player agent already loaded")

    storage_mgr = assert(conf.storage_mgr)
    player_mgr = assert(conf.player_mgr)

    local ok, result = skynet.call(
        storage_mgr,
        "lua",
        "load_player",
        conf.player_id
    )
    if not ok then
        return false, result
    end

    player = result
    state = STATE_LOADED
    skynet.error("[PlayerAgent] loaded player=", player.player_id)
    return true
end

function CMD.bind_client(conf)
    if state == STATE_ONLINE then
        return false, "ALREADY_ONLINE"
    end
    if state ~= STATE_LOADED then
        return false, "INVALID_AGENT_STATE"
    end

    client_fd = assert(conf.fd)
    client_connection_id = assert(conf.connection_id)
    state = STATE_ONLINE

    return true, login_info()
end

function CMD.client_closed(fd, connection_id)
    -- fd 会被 OS 复用；fd 与逻辑 connection_id 同时匹配，才能关闭当前绑定。
    if fd ~= client_fd or connection_id ~= client_connection_id then
        return false
    end

    state = STATE_CLOSING
    client_fd = nil
    client_connection_id = nil

    local player_id = player.player_id
    skynet.call(player_mgr, "lua", "remove", player_id, skynet.self())
    skynet.error("[PlayerAgent] offline player=", player_id)
    skynet.exit()
end

function CMD.abort_if_unbound()
    if state == STATE_ONLINE then
        return false
    end

    state = STATE_CLOSING
    local player_id = player and player.player_id
    if player_id then
        skynet.call(player_mgr, "lua", "remove", player_id, skynet.self())
    end
    skynet.exit()
end

function CMD.shutdown()
    skynet.exit()
end

-- Login 成功后 Gate 会把后续 Client Packet 直接转发给 PlayerAgent。
-- 第一阶段没有登录后业务协议，收到 Packet 时只记录；下一阶段会在这里接入
-- Sproto REQUEST dispatcher。
skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
    unpack = function(msg, sz)
        return skynet.tostring(msg, sz)
    end,
    dispatch = function(fd, source, payload)
        skynet.ignoreret()
        if fd ~= client_fd then
            skynet.error("[PlayerAgent] stale client packet fd=", fd)
            return
        end
        skynet.error("[PlayerAgent] post-login packet is not implemented size=", #payload)
    end,
}

skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command],
            "unknown player agent command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
```

### 12.1 `CMD.load` 的执行现场

`CMD.load` 在 PlayerAgent 自己的消息 coroutine 中执行。调用 StorageMgr 时发生 yield：

```lua
local ok, result = skynet.call(storage_mgr, ...)
```

恢复后才能写入 `player` 并把状态改为 `LOADED`。第一阶段创建期间没有其他来源能拿到 Agent Address，所以不会有业务命令抢先进入；PlayerMgr 只有 Load 成功后才发布 `players[player_id] = agent`。

### 12.2 为什么不能用 `player = nil` 表示销毁 Agent

`player` 是 Agent Lua State 中的业务变量。把它设为 nil 只会移除一个 Lua 引用，不会注销 Service Handle、Mailbox 或等待中的 coroutine。正常退出由 Agent 自己在完成路由清理后调用 `skynet.exit()`。

### 12.3 `client_closed` 的代际检查

fd 是 OS Descriptor，关闭后可能被重新使用。`connection_id` 由 Watchdog 单调递增，代表逻辑连接代际。迟到的旧连接关闭消息若只有相同 fd，可能误删新连接；两个字段同时匹配才接受。

本阶段没有断线重连。关闭后执行：

```text
Agent 标记 CLOSING
  -> PlayerMgr.remove(player_id, self)
  -> Agent skynet.exit()
```

下一阶段加入业务 Request 后，下线清理还必须进入该玩家的 `skynet.queue`，等待正在执行的业务临界区排空。

## 13. 写 PlayerMgr：创建和路由 PlayerAgent

完整路径：`service/player/player_mgr.lua`

```lua
local skynet = require "skynet"
local queue = require "skynet.queue"

local CMD = {}
local players = {}
local login_locks = {}
local storage_mgr

for index = 1, 64 do
    login_locks[index] = queue()
end

local function player_lock(player_id)
    return login_locks[(player_id % #login_locks) + 1]
end

function CMD.init(conf)
    storage_mgr = assert(conf.storage_mgr)
    return true
end

function CMD.login(player_id)
    player_id = assert(math.tointeger(player_id),
        "player_id must be integer")

    return player_lock(player_id)(function()
        local existing = players[player_id]
        if existing then
            return existing, false
        end

        local agent = skynet.newservice("player/player_agent")
        local ok, err = skynet.call(agent, "lua", "load", {
            player_id = player_id,
            storage_mgr = storage_mgr,
            player_mgr = skynet.self(),
        })
        if not ok then
            skynet.send(agent, "lua", "shutdown")
            return nil, false, err
        end

        players[player_id] = agent
        return agent, true
    end)
end

function CMD.remove(player_id, agent)
    if players[player_id] ~= agent then
        return false
    end
    players[player_id] = nil
    return true
end

function CMD.get(player_id)
    return players[player_id]
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command],
            "unknown player manager command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
```

PlayerMgr 的 `players` 是 `player_id -> Service Address` 路由表。Address 是 Skynet Handle，不是 PlayerAgent Lua Table。

`skynet.newservice` 和随后对 Agent 的 `skynet.call` 都可能 yield。同一玩家的两个 Login coroutine 如果不串行化，可能同时看到 `players[player_id] == nil`，各自创建一个 Agent。64 个 `skynet.queue` 按 player_id 分片，只让相同分片内的创建顺序执行；数量固定，避免为历史上每个 player_id 永久保留一个 Queue。

`CMD.remove` 必须比较 Agent Address。旧 Agent 的迟到退出消息不能删除已经替换成新 Agent 的路由。

检查并提交：

```bash
git add service/player/player_agent.lua service/player/player_mgr.lua
git diff --cached
git commit -m "feat: add player agent lifecycle"
```

## 14. 写 Watchdog，接入官方 Gate

Watchdog 持有连接表和 Login 状态机。Gate 负责 Socket 收发与 Frame 拆包，不持有玩家数据。

完整路径：`service/gateway/watchdog.lua`

```lua
local skynet = require "skynet"
local sprotoloader = require "sprotoloader"
local frame = require "protocol.frame"

local CMD = {}
local SOCKET = {}

local gate
local player_mgr
local auth_service
local host
local connections = {}
local next_connection_id = 0

local function new_connection_id()
    next_connection_id = next_connection_id + 1
    return next_connection_id
end

local function alive(fd, connection)
    return connections[fd] == connection
end

local function close_later(fd, connection_id)
    skynet.timeout(10, function()
        local connection = connections[fd]
        if connection and connection.id == connection_id then
            skynet.call(gate, "lua", "kick", fd)
        end
    end)
end

function SOCKET.open(fd, addr)
    local connection = {
        id = new_connection_id(),
        fd = fd,
        addr = addr,
        state = "CONNECTED",
        agent = nil,
    }
    connections[fd] = connection

    skynet.error("[Watchdog] open fd=", fd,
        " conn=", connection.id, " addr=", addr)

    -- Gate 接受 Socket 后默认尚未读取 Client 数据；accept/openclient 后才开始。
    skynet.call(gate, "lua", "accept", fd)
end

local function on_close(fd)
    local connection = connections[fd]
    if not connection then
        return
    end

    connections[fd] = nil
    if connection.agent then
        skynet.send(connection.agent, "lua", "client_closed",
            fd, connection.id)
    end

    skynet.error("[Watchdog] close fd=", fd,
        " conn=", connection.id)
end

function SOCKET.close(fd)
    on_close(fd)
end

function SOCKET.error(fd, msg)
    skynet.error("[Watchdog] socket error fd=", fd, " msg=", msg)
    on_close(fd)
end

function SOCKET.warning(fd, size)
    skynet.error("[Watchdog] send buffer warning fd=", fd,
        " size_kb=", size)
end

function SOCKET.data(fd, msg)
    local connection = connections[fd]
    if not connection or connection.state ~= "CONNECTED" then
        return
    end

    local dispatch_ok, protocol_type, name, args, response = pcall(function()
        return host:dispatch(msg)
    end)
    if not dispatch_ok or protocol_type ~= "REQUEST" or name ~= "login" then
        skynet.error("[Watchdog] first packet must be login fd=", fd)
        connection.state = "CLOSING"
        close_later(fd, connection.id)
        return
    end

    -- 必须在第一个 yield 前改变状态。否则处理 Auth 时，第二个 Packet 可能
    -- 进入另一个 data coroutine，再次开始 Login。
    connection.state = "AUTHING"

    local player_id = math.tointeger(args.player_id)
    local token = args.token
    local auth_ok = player_id
        and skynet.call(auth_service, "lua", "verify", player_id, token)

    -- skynet.call 期间 Socket 可能已经关闭，恢复后不能继续使用旧 connection。
    if not alive(fd, connection) then
        return
    end

    if not auth_ok then
        if response then
            frame.write(fd, response {
                code = 1,
                message = "AUTH_FAILED",
            })
        end
        connection.state = "CLOSING"
        close_later(fd, connection.id)
        return
    end

    local agent, is_new, load_error = skynet.call(
        player_mgr, "lua", "login", player_id)

    if not alive(fd, connection) then
        if is_new and agent then
            skynet.send(agent, "lua", "abort_if_unbound")
        end
        return
    end

    if not agent then
        if response then
            frame.write(fd, response {
                code = 2,
                message = load_error or "LOAD_PLAYER_FAILED",
            })
        end
        connection.state = "CLOSING"
        close_later(fd, connection.id)
        return
    end

    connection.agent = agent
    local bind_ok, player_info = skynet.call(agent, "lua", "bind_client", {
        fd = fd,
        connection_id = connection.id,
    })

    if not alive(fd, connection) then
        return
    end

    if not bind_ok then
        connection.agent = nil
        if response then
            frame.write(fd, response {
                code = 3,
                message = player_info or "BIND_FAILED",
            })
        end
        connection.state = "CLOSING"
        close_later(fd, connection.id)
        return
    end

    -- future Client Packet 不再绕行 Watchdog，而是由 Gate 直接 redirect 到 Agent。
    skynet.call(gate, "lua", "forward", fd, 0, agent)
    if not alive(fd, connection) then
        return
    end
    connection.state = "PLAYING"

    if response then
        frame.write(fd, response {
            code = 0,
            message = "OK",
            player_id = player_info.player_id,
            name = player_info.name,
            level = player_info.level,
            gold = player_info.gold,
        })
    end

    skynet.error("[Watchdog] login success player=", player_id,
        " fd=", fd, " agent=", skynet.address(agent))
end

function CMD.start(conf)
    player_mgr = assert(conf.player_mgr)
    auth_service = assert(conf.auth_service)

    gate = skynet.newservice("gate")
    return skynet.call(gate, "lua", "open", {
        address = conf.address,
        port = conf.port,
        maxclient = conf.maxclient,
        nodelay = true,
        watchdog = skynet.self(),
    })
end

skynet.start(function()
    host = sprotoloader.load(1):host "package"

    skynet.dispatch("lua", function(session, source, command, subcommand, ...)
        if command == "socket" then
            local fn = assert(SOCKET[subcommand],
                "unknown socket event: " .. tostring(subcommand))
            fn(...)
            return
        end

        local fn = assert(CMD[command],
            "unknown watchdog command: " .. tostring(command))
        local result = { fn(subcommand, ...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
```

### 14.1 一条 Login 在 Watchdog 中在哪里挂起

`SOCKET.data` 至少有四个同步 RPC：

```text
call Auth.verify
call PlayerMgr.login
call PlayerAgent.bind_client
call Gate.forward
```

每次 `call` 都让当前 Watchdog coroutine yield。同一 Service 的 Socket Close 消息可以由另一个 coroutine 处理并删除 `connections[fd]`。因此每次恢复后都调用 `alive(fd, connection)`，检查表中保存的还是同一个 Lua connection Table。

只比较 fd 不够。fd 复用时，新连接可能占用相同整数；`connection.id` 与 Table Identity 共同区分代际。

### 14.2 为什么先改 `AUTHING` 再调用 Auth

Gate 可能已经把第二个完整 Packet 放入 Watchdog Mailbox。若第一个 Login 在 `skynet.call(auth_service, ...)` 前没有改状态，第二个 Handler 会再次看到 `CONNECTED`，同一连接会并行执行两次登录。状态必须在第一个 yield 前提交。

### 14.3 为什么 `gate.forward` 不经过 PlayerMgr

PlayerMgr 只负责登录期的生命周期和路由查询。登录完成后的高频 Packet 由 Gate 直接转发到 Agent，避免每个业务请求都经过中心 Manager。

### 14.4 解码失败和业务参数校验是两层检查

`SOCKET.data` 用 `pcall` 包住 `host:dispatch(msg)`。截断的 Sproto Payload、错误 Field Length 或无法识别的 RPC Envelope 会走解码失败分支，连接进入 `CLOSING`，而不是让一次恶意 Packet 终止 Watchdog Service。

成功解码只证明字节符合 Sproto Wire Format，不证明参数可以进入业务。`player_id` 仍要用 `math.tointeger` 检查；生产登录还应限制 Token/String 长度、协议状态和单位时间请求数。数组元素上限、嵌套深度和各业务字段范围也应在对应入口校验，不能因为外层 Frame 已限制为 `65535` 字节就省略。

当前失败路径延迟一个 Tick 调用 Gate `kick`，让已经写入的拒绝 Response 有机会进入发送路径。`socket.write` 成功也不代表 Client 必然收到数据，断线和重试语义要由后续登录/重连协议处理。

提交 Watchdog：

```bash
git add service/gateway/watchdog.lua
git diff --cached
git commit -m "feat: implement login watchdog and gate handoff"
```

## 15. 完成业务 Main

用下面内容替换 `service/main.lua`：

```lua
local skynet = require "skynet"

local function getenv(name, default)
    local value = skynet.getenv(name)
    if value == nil or value == "" then
        return default
    end
    return value
end

local function getenv_int(name, default)
    return assert(tonumber(getenv(name, tostring(default))))
end

skynet.start(function()
    skynet.error("========== Skynet MMO ARPG ==========")

    skynet.uniqueservice("protocol/protoloader")

    local storage_mgr = skynet.uniqueservice("storage/storage_mgr")
    skynet.call(storage_mgr, "lua", "start", {
        pool = getenv_int("storage_pool", 2),
    })

    local player_mgr = skynet.uniqueservice("player/player_mgr")
    skynet.call(player_mgr, "lua", "init", {
        storage_mgr = storage_mgr,
    })

    local auth_service = skynet.uniqueservice("auth/auth")
    local watchdog = skynet.uniqueservice("gateway/watchdog")
    local address, port = skynet.call(watchdog, "lua", "start", {
        address = getenv("gate_host", "127.0.0.1"),
        port = getenv_int("gate_port", 8888),
        maxclient = getenv_int("max_client", 1024),
        player_mgr = player_mgr,
        auth_service = auth_service,
    })

    local debug_port = getenv_int("debug_console_port", 8000)
    if debug_port > 0 then
        skynet.newservice("debug_console", debug_port)
    end

    skynet.error("[Main] gate listening at ", address, ":", port)
    skynet.error("[Main] startup complete")
    skynet.exit()
end)
```

启动顺序由依赖决定：Protocol Slot、Storage 和 PlayerMgr 准备好以后才开放 Gate。Main 完成装配后退出，不成为所有业务消息的中央代理。

启动服务器：

```bash
./scripts/linux/run_server.sh
```

等待：

```text
[Main] gate listening at 127.0.0.1:8888
[Main] startup complete
```

在 VS Code 中再新建一个**终端 C**实例：

```bash
ss -ltnp | grep -E ':8888|:8000'
```

现在还没有 Client，但 Gate 和 Debug Console 已监听。停止服务器，提交 Main：

```bash
git add service/main.lua
git diff --cached
git commit -m "feat: assemble login server services"
```

把当前 Feature Branch 推到远程：

```bash
git push
git status -sb
```

`git status -sb` 应显示本地 `feature/login` 与 `origin/feature/login` 没有 Ahead/Behind 差异。

## 16. 写真实 TCP Login Client

Client 直接使用 Skynet Bundled Lua 和 `client.socket`。它不会绕过 Gate 调用 Service，因此可以验证 Frame、Sproto、Socket 和完整 Login 链路。

### 16.1 `client/login_client.lua`

```lua
package.cpath = "./third_party/skynet/luaclib/?.so"
package.path = "./third_party/skynet/lualib/?.lua;"
    .. "./lualib/?.lua;"
    .. package.path

assert(_VERSION == "Lua 5.4", "use Skynet bundled Lua 5.4")

local socket = require "client.socket"
local sproto = require "sproto"
local sprotoparser = require "sprotoparser"
local schema = require "protocol.schema"

local options = {
    host = "127.0.0.1",
    port = 8888,
    player = 10001,
    token = nil,
    expect_code = 0,
    hold_ms = 0,
}

for _, value in ipairs(arg or {}) do
    local key, text = value:match("^%-%-([%w_]+)=(.+)$")
    if key == "host" then
        options.host = text
    elseif key == "port" then
        options.port = assert(tonumber(text))
    elseif key == "player" then
        options.player = assert(tonumber(text))
    elseif key == "token" then
        options.token = text
    elseif key == "expect_code" then
        options.expect_code = assert(tonumber(text))
    elseif key == "hold_ms" then
        options.hold_ms = assert(tonumber(text))
    end
end

options.token = options.token or ("dev:" .. tostring(options.player))

local host = sproto.new(sprotoparser.parse(schema.s2c)):host "package"
local request = host:attach(sproto.new(sprotoparser.parse(schema.c2s)))

local fd = assert(socket.connect(options.host, options.port))
print(string.format("[Client] connected %s:%d fd=%d",
    options.host, options.port, fd))

local function send_frame(payload)
    assert(#payload <= 0xffff)
    socket.send(fd, string.pack(">s2", payload))
end

local buffer = ""

local function unpack_one()
    if #buffer < 2 then
        return nil
    end

    local size = buffer:byte(1) * 256 + buffer:byte(2)
    if #buffer < size + 2 then
        return nil
    end

    local payload = buffer:sub(3, size + 2)
    buffer = buffer:sub(size + 3)
    return payload
end

local function receive_frame()
    while true do
        local payload = unpack_one()
        if payload then
            return payload
        end

        local data = socket.recv(fd)
        if data == "" then
            error("server closed before login response")
        elseif data then
            buffer = buffer .. data
        else
            socket.usleep(1000)
        end
    end
end

local session = 1
send_frame(request("login", {
    player_id = options.player,
    token = options.token,
}, session))

local protocol_type, response_session, result = host:dispatch(receive_frame())
assert(protocol_type == "RESPONSE", "expected login response")
assert(response_session == session, "response session mismatch")
assert(result.code == options.expect_code,
    string.format("expected code=%d actual=%s message=%s",
        options.expect_code, tostring(result.code), tostring(result.message)))

if result.code == 0 then
    assert(result.player_id == options.player, "player_id mismatch")
    assert(type(result.name) == "string" and result.name ~= "", "missing name")
    assert(type(result.level) == "number", "missing level")
    assert(type(result.gold) == "number", "missing gold")

    print(string.format(
        "LOGIN_OK player_id=%d name=%s level=%d gold=%d",
        result.player_id, result.name, result.level, result.gold))
else
    print(string.format("LOGIN_REJECTED code=%d message=%s",
        result.code, tostring(result.message)))
end

if options.hold_ms > 0 then
    print(string.format("[Client] holding connection for %d ms", options.hold_ms))
    socket.usleep(options.hold_ms * 1000)
end

socket.close(fd)
os.exit(0, true)
```

`host` 和 `attach` 的方向容易写反。Client 先用 S2C Schema 创建 `host`，因为它接收并解码 Server 发来的 Response 或 Push；再把 C2S Schema attach 到这个 Host，得到 Request Encoder：

```text
s2c schema
  └─ host:dispatch(Server Packet)

c2s schema
  └─ host:attach(...)
       └─ request("login", args, session)
```

Server 侧正好相反。`service/gateway/watchdog.lua` 用 C2S Schema 创建 Host，`host:dispatch(msg)` 解码 Client Request；返回的 `response` Closure 已经记住协议类型和 session，调用 `response { ... }` 才得到对应的 Sproto Response Payload。`frame.write` 随后只增加 TCP Length Prefix，不再改动 RPC Envelope。

`receive_frame` 必须允许一次 `recv` 只拿到 Header 的一部分、Payload 的一部分，或者同时拿到多个 Frame。第一课只接收一个 Response，但 Buffer 写法保留了正确的 Stream 语义。

`os.exit(0, true)` 用于这个一次性 Test Client。官方 `client.socket` 加载后会建立 stdin pthread；如果只让 Lua Chunk Return，非交互运行环境可能仍等待 stdin Thread。正式交互 Client 会使用它提供的 `readstdin()` Queue，不能同时用 `io.read()` 竞争 stdin。

### 16.2 `scripts/linux/run_client.sh`

```bash
#!/usr/bin/env bash

# 上面的 Shebang 必须位于第一行；直接执行脚本时，Linux 会从 PATH 中
# 找到 bash，并用它解释本文件。

# 打开 Bash 严格模式：
# -e：Client 启动命令返回非 0 时停止脚本，E2E 能收到失败退出码；
# -u：读取未定义变量时报错；
# -o pipefail：管道中任意一个命令失败，整条管道都算失败。
set -euo pipefail

# $0 是当前脚本的启动路径，dirname "$0" 取得 scripts/linux。
# $(...) 是 Command Substitution，把 dirname 的输出放回 cd 命令。
# /../.. 从 scripts/linux 向上两级回到仓库根目录，保证 Lua 相对路径正确。
# 双引号避免路径中存在空格时被 Bash 拆成多个参数。
cd "$(dirname "$0")/../.."

# 使用 Skynet 自带的 Lua 5.4，而不是 Ubuntu System Lua。
# $@ 表示传给当前脚本的全部位置参数；写成 "$@" 时，每个原始参数
# 仍保持独立，参数内容中的空格也不会被再次拆分。
# exec 用 Lua Process 替换当前 Script Process，PID 不变，退出码和 Signal
# 可以直接传给 E2E Script 或当前 Terminal。
exec ./third_party/skynet/3rd/lua/lua client/login_client.lua "$@"
```

赋予执行权限：

```bash
chmod +x scripts/linux/run_client.sh
```

### 16.3 第一次手工 Login

在当前 WSL Workspace 中建立两个**终端 C**实例，并重命名为 `SERVER` 和 `CLIENT`。两者都应是 Ubuntu Bash，`pwd` 都应位于工程根目录。

`SERVER`：

```bash
cd ~/workspace/skynet-mmo-arpg
./scripts/linux/run_server.sh
```

等待 `[Main] startup complete`。`CLIENT`：

```bash
cd ~/workspace/skynet-mmo-arpg
./scripts/linux/run_client.sh --player=10001
```

预期：

```text
[Client] connected 127.0.0.1:8888 fd=...
LOGIN_OK player_id=10001 name=Knight10001 level=10 gold=10000
```

错误 Token：

```bash
./scripts/linux/run_client.sh \
    --player=10001 \
    --token=wrong-token \
    --expect_code=1
```

预期：

```text
LOGIN_REJECTED code=1 message=AUTH_FAILED
```

如果 Client 报 `connection refused`，先看 Server 是否仍在运行、是否出现 `startup complete`，再检查：

```bash
ss -ltnp | grep ':8888'
```

如果 Server 报 `Address already in use`，不要重复启动；找到旧的 `SERVER` 集成终端并用 `Ctrl+C` 停止。

### 16.4 64 位整数经过各端时怎样保持精确

当前 Server 使用 Skynet Bundled Modified Lua 5.4.7。`third_party/skynet/3rd/lua/luaconf.h` 将默认 `LUA_INTEGER` 配置为 `long long`，在本课 Linux/WSL2 构建中是有符号 64 位；Sproto `integer` 也允许编码 signed 64-bit。`player_id=10001` 没有触及边界，正式项目的 Player ID、Guild ID 和订单流水需要逐段检查：

```text
Database BIGINT
  → Lua 5.4 integer
  → Sproto signed 64-bit integer
  → Unity long 或 H5 BigInt/String
  → UI、日志、JSON、LocalStorage
```

Unity C# 使用 `long` 可以保持 Sproto signed 64-bit 值。不要生成超过 `long.MaxValue` 的 `ulong` ID 后再交给 Lua；本工程的 Sproto Schema 没有单独的 `uint64` 类型。

JavaScript `Number` 只能精确表示 `-(2^53-1)` 到 `2^53-1` 范围内的整数。H5 Decoder 应把大整数保存为 `BigInt`，或者从协议边界开始就把标识类字段定义为十进制字符串。下面的转换会静默丢失低位：

```javascript
const playerId = Number("9223372036854775806");
```

`BigInt` 不能直接交给普通 `JSON.stringify`，进入 JSON、浏览器存储或日志 SDK 前要明确转换规则。订单号等只比较和传递、不参与算术的外部标识，直接使用字符串通常更稳妥。

本课保留 `player_id : integer`，便于观察 Sproto 整数的真实编码。后续制作 Unity/H5 Client 时应增加至少四组互通值：`2^31-1`、`2^31`、`2^53-1` 和 `math.maxinteger`，由 Lua 编码后让 Client 解码，再由 Client 编码回 Lua。只验证 `10001` 不能证明 64 位链路正确。

### 16.5 Lua Test Client 与正式游戏 Client 的边界

`client/login_client.lua` 是协议参考实现和 E2E Driver，不承担正式客户端框架的职责。不同前端接入同一 Server 时，Transport 会有差异：

| Client | Transport | 消息边界 | Sproto Codec |
|---|---|---|---|
| 本课 Lua Test Client | TCP | 2-byte big-endian Length | Skynet 自带 Lua/C 实现 |
| Unity Windows/Android/iOS | TCP | 2-byte big-endian Length | C# 静态 Codec |
| H5 | WSS WebSocket | 一个 Binary Message | TypeScript Codec |
| Unity WebGL | WSS WebSocket | 一个 Binary Message | WebGL 可用的 C#/JS Codec |

浏览器不能直接连接本课的 Raw TCP Gate。H5 和 Unity WebGL 需要 WebSocket Gateway；Skynet 已提供 `third_party/skynet/lualib/http/websocket.lua`，示例在 `third_party/skynet/examples/simplewebsocket.lua`。WebSocket 自身保留消息边界，通常让一个 Binary Message 直接携带一个 Sproto Payload，不再重复增加两字节 TCP Header。Gateway 收到 Binary Message 后，把 Payload 交给与 TCP 入口相同的 Sproto 分发层。

前端没有必须引用的第三方 Sproto Runtime。项目可以维护小型 `SprotoReader`、`SprotoWriter`、RPC Envelope 和 Session Manager，再根据权威 `.sproto` 文件生成每条消息的 C#/TypeScript 静态 Codec。业务协议不应逐条手写；Schema 增加字段后，手写 Codec 很容易漏掉编码、解码或未知字段兼容分支。

自有 Codec 要以 Skynet 自带的 Lua/C Sproto 为参考实现，CI 至少执行：

```text
Lua encode → C# decode
C# encode  → Lua decode
Lua encode → TypeScript decode
TypeScript encode → Lua decode
```

样本覆盖缺省字段、未知字段、空 String/Binary、嵌套结构、空数组、32/64 位整数、负数、截断数据和伪造长度。第三方实现可以用于阅读和交叉验证，不必成为产品的 Runtime 依赖。

本阶段不实现 Unity/H5 Client。第一课的验收仍以 Lua Test Client 打通真实 TCP Login 为准；这里先固定跨语言边界，防止当前协议只能被 Lua Client 正确解释。

### 16.6 从字节观察一次 Login

这一步临时打印 Client 编码结果，确认代码中的三层数据与网络字节能对应起来。在 `client/login_client.lua` 的 `local session = 1` 前加入：

```lua
-- 仓库路径：client/login_client.lua
-- 把 Binary String 中的每个 Byte 转为两位十六进制，只用于本节观察协议。
local function to_hex(data)
    return (data:gsub(".", function(byte)
        return string.format("%02X ", string.byte(byte))
    end))
end
```

把原来的直接发送改成先保存 Payload，再构造完整 Frame：

```lua
-- 仓库路径：client/login_client.lua
local session = 1
local payload = request("login", {
    player_id = options.player,
    token = options.token,
}, session)

local packet = string.pack(">s2", payload)
print("SPROTO_PAYLOAD " .. to_hex(payload))
print("TCP_PACKET     " .. to_hex(packet))
socket.send(fd, packet)
```

运行一次：

```bash
./scripts/linux/run_client.sh --player=10001
```

检查 `TCP_PACKET` 的前两个 Byte。把它们按大端序合并后，数值应等于 `SPROTO_PAYLOAD` 的 Byte 数：

```text
payload_size = first_byte * 256 + second_byte
```

`TCP_PACKET` 从第三个 Byte 开始应与 `SPROTO_PAYLOAD` 完全相同。`third_party/skynet/lualib/snax/gateserver.lua` 调用 `netpack.filter`，实际拆包发生在 `third_party/skynet/lualib-src/lua-netpack.c::filter_data_`。`third_party/skynet/service/gate.lua::handler.message` 得到完整 Payload 后再交给 Watchdog，所以 `service/gateway/watchdog.lua::SOCKET.data(fd, msg)` 收到的内容从第三个 Byte 开始。随后 `host:dispatch(msg)` 从 Sproto `.package` 取出 `type` 和 `session`，再解码 `login.request`。

这个观察代码不进入正式 Client。实验完成后执行：

```bash
git diff -- client/login_client.lua
git restore client/login_client.lua
```

`git restore` 丢弃指定文件尚未 Stage 的修改，可类比 SVN 的 Revert。执行前必须先看 `git diff`，确认文件中只有本节临时打印，避免连同需要保留的代码一起撤销。

停止 Server 后提交：

```bash
git add client/login_client.lua scripts/linux/run_client.sh
git diff --cached
git commit -m "feat: add sproto login test client"
git push
```

## 17. 写可重复的 Login E2E Test

手工看到成功日志只能证明一次现场。E2E 脚本必须自行启动隔离端口的 Server、等待 Ready、运行成功/失败用例，并保证失败时清理进程。

### 17.1 `config/test.lua`

```lua
include "game.lua"

thread = 4
gate_host = "127.0.0.1"
gate_port = 18888
max_client = 64
debug_console_port = 0
storage_pool = 2
```

测试使用 18888，避免与手工开发服务器 8888 冲突；Debug Console 关闭，避免自动测试暴露管理端口。

### 17.2 `tests/integration/login_smoke.sh`

```bash
#!/usr/bin/env bash

# 上面的 Shebang 必须位于第一行；直接执行脚本时，Linux 会从 PATH 中
# 找到 bash，并用它解释本文件。

# 打开 Bash 严格模式：
# -e：任意普通测试命令返回非 0 时停止脚本；
# -u：读取未定义变量时报错；
# -o pipefail：管道中任意一个命令失败，整条管道都算失败。
set -euo pipefail

# $0 是当前脚本的启动路径，dirname "$0" 取得 tests/integration。
# $(...) 先执行 dirname，再把输出替换进 cd 的参数。
# 本脚本位于 tests/integration/，/../.. 向上两级回到仓库根目录。
# 双引号保护包含空格的路径，保证 cd 只接收一个完整参数。
cd "$(dirname "$0")/../.."

# $$ 是当前 Test Shell 的 PID。变量出现在双引号中仍会展开。
# 把 PID 加入文件名，可避免两个并行测试相互覆盖日志。
# 测试成功后删除这些文件；失败时保留，便于还原现场。
SERVER_LOG="/tmp/skynet_mmo_arpg_server_$$.log"
SUCCESS_LOG="/tmp/skynet_mmo_arpg_login_success_$$.log"
REJECT_LOG="/tmp/skynet_mmo_arpg_login_reject_$$.log"

# function_name() { ...; } 定义 Bash Function。这里只定义清理逻辑，
# 当前执行流不会立刻进入函数体，直到后面的 trap 触发它。
cleanup() {
    # SERVER_PID 在 Server 成功启动前可能尚未赋值，${SERVER_PID:-} 可在 -u
    # 模式下安全读取。[[ -n ... ]] 判断字符串非空，&& 要求左右条件都成功。
    # kill -0 只检查该 PID 是否仍存活，不发送终止信号。
    # 2>/dev/null 丢弃检查过程的 Standard Error。
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        # 只停止本脚本亲自启动的 PID，不使用 killall 误伤开发服务器。
        # || true 表示即使 Process 已在检查后自行退出，也不要让清理失败
        # 覆盖测试原本的退出原因。
        kill "$SERVER_PID" 2>/dev/null || true

        # wait 等待并回收后台子进程，避免留下 Zombie。
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}

# trap 把 cleanup 注册到 EXIT；无论正常结束、命令失败还是收到 Ctrl+C，
# Shell 退出时都会调用该函数。
trap cleanup EXIT

# >"$SERVER_LOG" 把 Standard Output 写入日志并覆盖旧文件；
# 2>&1 再让 Standard Error 指向当前 Standard Output，也进入同一个日志；
# 行尾 & 让 Server 在后台运行，Test Shell 才能继续执行 Client。
# $! 只保存刚刚启动的后台 Process PID。
./third_party/skynet/skynet config/test.lua >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

# $(seq 1 50) 先生成 1 到 50；for 每次取一个值。
# 变量名使用 _，表示循环序号本身不参与业务判断。
# 最多轮询 50 次，每次 0.1 秒，总启动预算约 5 秒。
# 既检查 Process 是否提前退出，也等待业务 Main 的 Ready Log。
ready=false
for _ in $(seq 1 50); do
    # ! 对命令结果取反。kill -0 失败说明 Server PID 已经不存在。
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        # >&2 把诊断写入 Standard Error，cat 随后输出完整 Server Log。
        echo "Server exited during startup" >&2
        cat "$SERVER_LOG"
        exit 1
    fi
    # grep -q 只用退出码表示是否找到文本，不把匹配行重复打印出来。
    if grep -q "startup complete" "$SERVER_LOG"; then
        ready=true
        break
    fi
    sleep 0.1
done

# 超时与 Process 提前退出分开报告；两者都打印 Server Log。
if [[ "$ready" != true ]]; then
    echo "Server startup timeout" >&2
    cat "$SERVER_LOG"
    exit 1
fi

# 成功用例使用真实 TCP 端口。timeout 最多等待 10 秒，超时后返回非 0，
# 防止协议或 Server 故障让 CI 永久挂起。行尾反斜杠连接下一物理行。
timeout 10s ./scripts/linux/run_client.sh \
    --port=18888 \
    --player=10001 >"$SUCCESS_LOG" 2>&1

# cat 回显 Client 现场；grep -q 用精确结果文本完成 Assertion。
cat "$SUCCESS_LOG"
grep -q "LOGIN_OK player_id=10001 name=Knight10001 level=10 gold=10000" \
    "$SUCCESS_LOG"

# 拒绝用例验证 Auth 错误路径；Client 的 expect_code 让预期拒绝仍返回成功退出码。
timeout 10s ./scripts/linux/run_client.sh \
    --port=18888 \
    --player=10001 \
    --token=wrong-token \
    --expect_code=1 >"$REJECT_LOG" 2>&1
cat "$REJECT_LOG"
grep -q "LOGIN_REJECTED code=1 message=AUTH_FAILED" "$REJECT_LOG"

# 只有两个 Assertion 都成功才删除日志并输出完成标记。
rm -f "$SERVER_LOG" "$SUCCESS_LOG" "$REJECT_LOG"
echo "LOGIN_E2E_OK"
```

`trap cleanup EXIT` 保证正常结束、Assertion Failure 或 Ctrl+C 都会尝试停止 Test Server。PID 来自当前脚本刚启动的 Process，不使用 `killall skynet` 误伤其他开发实例。

### 17.3 `scripts/linux/test.sh`

```bash
#!/usr/bin/env bash

# 上面的 Shebang 必须位于第一行；直接执行脚本时，Linux 会从 PATH 中
# 找到 bash，并用它解释本文件。

# 打开 Bash 严格模式：
# -e：Build 或子测试返回非 0 时停止脚本，并把失败传给调用方；
# -u：读取未定义变量时报错；
# -o pipefail：管道中任意一个命令失败，整条管道都算失败。
set -euo pipefail

# $0 是当前脚本的启动路径，dirname "$0" 取得 scripts/linux。
# $(...) 先执行 dirname，再把结果替换进 cd 命令。
# /../.. 从 scripts/linux 向上两级回到仓库根目录。
# 双引号避免路径中的空格触发 Bash Word Splitting。
cd "$(dirname "$0")/../.."

# [[ ... ]] 是 Bash 条件表达式；! 表示取反；-x 检查文件存在且可执行。
# 新 Clone 尚未构建时自动编译；已有可执行 Runtime 时不重复构建。
if [[ ! -x third_party/skynet/skynet ]]; then
    ./scripts/linux/build.sh
fi

# 当前阶段只有 Login E2E。后续 Unit Test、更多 Integration Test
# 继续在这里按顺序加入，形成开发机和 CI 共用的单一入口。
./tests/integration/login_smoke.sh

# 只有所有前置测试成功时才会输出总完成标记。
echo "ALL_TESTS_OK"
```

设置权限并运行：

```bash
chmod +x tests/integration/login_smoke.sh scripts/linux/test.sh
./scripts/linux/test.sh
```

结尾必须是：

```text
LOGIN_E2E_OK
ALL_TESTS_OK
```

如果失败，临时日志路径带有当前 Shell PID。脚本会打印关键 Client/Server 输出；需要继续检查时，可暂时记下路径，但不要把 `/tmp` 日志加入 Git。

提交测试：

```bash
git status --short
git diff
git add config/test.lua tests/integration/login_smoke.sh scripts/linux/test.sh
git diff --cached
git commit -m "test: add login end-to-end smoke test"
git push
```

## 18. 写 Debug Console 脚本，观察 PlayerAgent 生命周期

完整路径：`scripts/linux/debug_console.sh`

```bash
#!/usr/bin/env bash

# 上面的 Shebang 必须位于第一行；直接执行脚本时，Linux 会从 PATH 中
# 找到 bash，并用它解释本文件。

# 打开 Bash 严格模式：
# -e：缺少命令或连接失败时停止脚本，并返回非 0；
# -u：读取未定义变量时报错；
# -o pipefail：管道中任意一个命令失败，整条管道都算失败。
set -euo pipefail

# $0 是当前脚本的启动路径，dirname "$0" 取得 scripts/linux。
# $(...) 先执行 dirname，再把输出替换进 cd 命令。
# /../.. 从 scripts/linux 向上两级回到仓库根目录。
# 使用双引号，避免路径中的空格被拆成多个参数。
cd "$(dirname "$0")/../.."

# $1、$2 是第一、第二个位置参数。
# ${变量:-默认值} 表示变量未提供或为空时使用右侧默认值。
# 因此两个位置参数可以覆盖 Host 和 Port；不传参数时连接本机开发端口。
HOST="${1:-127.0.0.1}"
PORT="${2:-8000}"

# command -v nc 查询 Shell 能否从 PATH 找到 nc；找到时返回 0。
# ! 对返回结果取反，所以找不到时进入 then 分支。
# >/dev/null 丢弃 Standard Output，2>&1 让 Standard Error 也指向 /dev/null。
if ! command -v nc >/dev/null 2>&1; then
    echo "缺少 nc，请安装 netcat-openbsd" >&2
    exit 1
fi

echo "Connecting Debug Console ${HOST}:${PORT}; Ctrl+C exits."

# rlwrap 不是连接必需品；存在时为 nc 增加历史和方向键行编辑。
if command -v rlwrap >/dev/null 2>&1; then
    exec rlwrap nc "$HOST" "$PORT"
fi

# 没有 rlwrap 时直接运行 nc。exec 保证 Ctrl+C 直接交给前台连接进程。
exec nc "$HOST" "$PORT"
```

设置权限并启动普通服务器：

```bash
chmod +x scripts/linux/debug_console.sh
./scripts/linux/run_server.sh
```

在另一个**终端 C**实例中执行：

```bash
./scripts/linux/debug_console.sh
```

登录前执行：

```text
list
service
stat
mem
netstat
```

再运行一个保持连接 30 秒的 Client：

```bash
./scripts/linux/run_client.sh --player=10001 --hold_ms=30000
```

Client 收到 Login Response 后会打印 Hold 提示，30 秒内保持 Socket。此时在 Console 中执行 `list`，可以稳定观察动态 PlayerAgent；等待结束后再次执行 `list`，确认连接关闭通知使 Agent 退出。`hold_ms` 只属于 Test Client，不改变 Server 生命周期。

也可以在 Watchdog 的 Login Success 断点停住后查看 Console，此时 Agent 已经创建。找到实际 Agent Address 后：

```text
info :实际地址
task :实际地址
```

Debug Console 带有 `kill`、`inject` 等高权限能力，只适用于隔离开发环境。生产配置必须关闭或经过网络隔离、认证、审计和能力收缩。

提交脚本：

```bash
git add scripts/linux/debug_console.sh
git diff --cached
git commit -m "chore: add skynet debug console helper"
git push
```

## 19. 准备 LuaPanda Runtime

LuaPanda 有三部分：WSL 侧 VS Code Extension 提供 Debug Adapter；`LuaPanda.lua` 进入目标 Service 的 Lua State；LuaSocket `socket.core` 负责该 Lua State 与 Adapter 的 TCP 连接。只安装扩展不能完成调试。

### 19.1 `scripts/bootstrap_luapanda.sh`

```bash
#!/usr/bin/env bash

# 上面的 Shebang 必须位于文件第一行。
# 直接执行 ./scripts/bootstrap_luapanda.sh 时，Linux 会通过 /usr/bin/env
# 从当前 PATH 中找到 bash，并用它解释这个文件。

# 打开 Bash 严格模式：
# -e：下载、版本检查或清理命令返回非 0 时停止脚本；
# -u：读取未定义变量时报错；
# -o pipefail：管道中任意一个命令失败，整条管道都算失败。
set -euo pipefail

# $0 是当前脚本的启动路径。
# dirname "$0" 取得脚本所在的 scripts 目录。
# $(...) 先执行括号里的命令，再把输出替换进 cd 的参数。
# 本脚本位于 scripts/，所以 /.. 向上一级就是仓库根目录。
# 使用双引号，避免路径中包含空格时被 Bash 拆成多个参数。
cd "$(dirname "$0")/.."

# LuaPanda 使用经过本课程验证的精确 Commit；LuaSocket 使用发布 Tag。
# 不跟随浮动 Branch，避免以后重新搭环境得到行为不同的 Debug Runtime。
# Bash 变量赋值的等号两侧不能有空格。
LUAPANDA_COMMIT="e3ac3d3314f24cf939c36cac5b7dc1f2ed6ee129"
LUASOCKET_TAG="v3.1.0"

# 第三方依赖统一放在被 .gitignore 排除的工程私有目录中。
# mkdir -p 在目录已存在时也返回成功，并按需创建缺失的 Parent Directory。
mkdir -p third_party

# remove_dependency() { ...; } 定义 Function，不会在定义位置立即执行。
remove_dependency() {
    # $1 是调用 Function 时的第一个位置参数。
    # local 把变量限制在本次 Function 调用内，避免覆盖脚本同名变量。
    local target="$1"
    local parent

    # realpath -m 即使目标尚不存在也会消除 .、.. 并得到规范化绝对路径。
    # dirname 再取得目标的 Parent Directory。这里只允许清理 third_party
    # 的直接子目录，防止变量错误把删除范围扩到工程外。
    parent="$(dirname "$(realpath -m "$target")")"

    # [[ ... ]] 是 Bash 条件表达式，!= 对两个字符串做不等比较。
    if [[ "$parent" != "$(realpath third_party)" ]]; then
        echo "拒绝清理非 third_party 直接子目录：$target" >&2
        exit 1
    fi

    # 路径边界已经在上面验证。-- 表示后续内容一定按 Path 处理，
    # 即使 Path 意外以连字符开头，也不会被 rm 当成 Option。
    rm -rf -- "$target"
}

# ! 对判断结果取反，-f 检查目标是否为普通文件。
# Debugger 主文件不存在时重建 LuaPanda 目录。
# 上游仓库较大，这里只 Fetch 指定 Commit，不下载完整历史。
if [[ ! -f third_party/luapanda/Debugger/LuaPanda.lua ]]; then
    remove_dependency third_party/luapanda
    git init third_party/luapanda
    git -C third_party/luapanda remote add origin \
        https://github.com/Tencent/LuaPanda.git
    git -C third_party/luapanda fetch --depth 1 origin "$LUAPANDA_COMMIT"
    git -C third_party/luapanda checkout --detach FETCH_HEAD
fi

# LuaSocket 按发布 Tag 做 Shallow Clone。它稍后会针对 Skynet Bundled Lua
# 的 Header 和 ABI 编译，不能用 Ubuntu System Lua 的预编译 Package 替代。
if [[ ! -f third_party/luasocket/src/makefile ]]; then
    remove_dependency third_party/luasocket
    git clone --branch "$LUASOCKET_TAG" --depth 1 \
        https://github.com/lunarmodules/luasocket.git \
        third_party/luasocket
fi

# 即使目录和关键文件已经存在，也必须核对实际版本，防止复用错误依赖。
actual_luapanda="$(git -C third_party/luapanda rev-parse HEAD)"
actual_luasocket="$(git -C third_party/luasocket describe --tags --exact-match)"

# 两项都采用精确相等比较。版本不符时保留现场，不自动覆盖人工修改。
if [[ "$actual_luapanda" != "$LUAPANDA_COMMIT" ]]; then
    echo "LuaPanda commit mismatch: $actual_luapanda" >&2
    exit 1
fi
if [[ "$actual_luasocket" != "$LUASOCKET_TAG" ]]; then
    echo "LuaSocket tag mismatch: $actual_luasocket" >&2
    exit 1
fi

echo "LUAPANDA_SOURCE_OK commit=$LUAPANDA_COMMIT luasocket=$LUASOCKET_TAG"
```

LuaPanda 固定 Commit，不跟随浮动 Branch。`remove_dependency` 在删除前验证目标 Parent 确实是工程 `third_party`，避免变量或路径错误扩大删除范围。

这段脚本新增了两种 Git 操作：

- `git fetch --depth 1 origin <commit>` 只把指定远程对象取进刚初始化的本地 Repository，不切换 Working Tree。它仍属于前面讲过的 Fetch 语义，`--depth 1` 限制下载历史深度。
- `git checkout --detach FETCH_HEAD` 让 Working Tree 精确落在刚取回的 Commit，并且不创建本地 Branch。可类比 SVN Checkout 到固定 Revision 后只读使用；Detached HEAD 适合固定第三方依赖，不适合日常业务开发。
- `git rev-parse HEAD` 把当前 `HEAD` 解析成完整 Commit Hash，用来做精确版本比较。SVN 常用单个递增 Revision 标识版本；Git Commit ID 是由对象内容和父历史计算出的 Hash。

### 19.2 `scripts/linux/build_luapanda.sh`

```bash
#!/usr/bin/env bash

# 上面的 Shebang 必须位于第一行；直接执行脚本时，Linux 会从 PATH 中
# 找到 bash，并用它解释本文件。

# 打开 Bash 严格模式：
# -e：依赖获取、Native Build、复制或 Runtime Test 失败时停止脚本；
# -u：读取未定义变量时报错；
# -o pipefail：管道中任意一个命令失败，整条管道都算失败。
set -euo pipefail

# $0 是当前脚本的启动路径，dirname "$0" 取得 scripts/linux。
# $(...) 先执行 dirname，再把输出替换进 cd 命令。
# /../.. 从 scripts/linux 向上两级回到仓库根目录。
# 使用双引号，避免路径中的空格触发 Bash 参数拆分。
cd "$(dirname "$0")/../.."

# 恢复并验证固定版本的 LuaPanda 与 LuaSocket 源码。
./scripts/bootstrap_luapanda.sh

# [[ ... ]] 是 Bash 条件表达式；! 表示取反；-f 判断普通文件是否存在。
# LuaSocket 编译需要 Skynet Bundled Lua 的 Header；尚未构建时先构建 Skynet。
if [[ ! -f third_party/skynet/3rd/lua/lua.h ]]; then
    ./scripts/linux/build.sh
fi

# pwd -P 返回消除 Symbolic Link 后的绝对路径。
# $(...) 是前面已经解释过的 Command Substitution；这里把 pwd 输出与后续
# 路径拼接成绝对路径，避免子 Makefile 按自己的工作目录解释相对路径。
LUA_INCLUDE="$(pwd -P)/third_party/skynet/3rd/lua"
RUNTIME_ROOT="$(pwd -P)/third_party/luapanda-runtime"

# make -C 先把 Make 的工作目录切换到 LuaSocket src，不改变当前 Shell。
# 后面的 NAME=value 是传给 Makefile 的变量覆盖：选择 Linux Target、
# Lua 5.4，并指定 Skynet Bundled Lua Header。反斜杠连接下一物理行。
# 这里只构建工程私有产物，不执行会污染系统目录的 make install。
make -C third_party/luasocket/src linux \
    PLAT=linux \
    LUAV=5.4 \
    LUAINC_linux="$LUA_INCLUDE"

# mkdir -p 会创建缺失的多级目录，目录已存在时不报错。
# Lua 的 require "socket.core" 会把 Module Name 映射到 socket/core.so。
# LuaSocket 上游产物名不同，因此复制到 LuaPanda 私有 Runtime 的目标布局。
mkdir -p "$RUNTIME_ROOT/luaclib/socket"
cp third_party/luasocket/src/socket-3.0.0.so \
    "$RUNTIME_ROOT/luaclib/socket/core.so"

# 立即用同一个 Bundled Lua 做加载测试，不能只以编译命令成功作为验收。
./tests/tooling/test_luapanda_runtime.sh
```

这里不能用 Ubuntu 的 `lua-socket` Package。它针对 System Lua 构建，本工程要求模块使用 Skynet Bundled Modified Lua 5.4.7 Header 和 ABI。脚本不执行 LuaSocket 的全局 `make install`，只复制 LuaPanda 实际需要的 `socket.core` 到工程私有目录。

### 19.3 `tests/tooling/test_luapanda_runtime.sh`

```bash
#!/usr/bin/env bash

# 上面的 Shebang 必须位于第一行；直接执行脚本时，Linux 会从 PATH 中
# 找到 bash，并用它解释本文件。

# 打开 Bash 严格模式：
# -e：文件检查、Native Module 加载或 API Assertion 失败时停止脚本；
# -u：读取未定义变量时报错；
# -o pipefail：管道中任意一个命令失败，整条管道都算失败。
set -euo pipefail

# $0 是当前脚本的启动路径，dirname "$0" 取得 tests/tooling。
# $(...) 先执行 dirname，再把输出替换进 cd 命令。
# /../.. 从 tests/tooling 向上两级回到仓库根目录。
# 使用双引号，避免路径中的空格被 Bash 拆成多个参数。
cd "$(dirname "$0")/../.."

# 使用绝对路径，保证测试不会受调用者目录或 Symbolic Link 影响。
RUNTIME_ROOT="$(pwd -P)/third_party/luapanda-runtime"
CORE_MODULE="$RUNTIME_ROOT/luaclib/socket/core.so"

# [[ ... ]] 是 Bash 条件表达式，! 表示取反，-f 判断普通文件是否存在。
# 先给出明确的缺失文件诊断，避免 require 只打印一长串搜索路径。
if [[ ! -f "$CORE_MODULE" ]]; then
    echo "missing LuaPanda runtime: $CORE_MODULE" >&2
    exit 1
fi

# 把 NAME=value 写在单条命令前，只为随后启动的 Lua Process 设置 Environment，
# 不会 export 到当前 Shell，也不会影响下一条命令。
# 只对这个 Test Process 临时设置 LUA_CPATH，不污染用户 Shell。
# 末尾的 ;; 要求 Lua 在这条自定义路径之后继续追加 Default C Path。
# 反斜杠把三行连接成一条命令；Lua 的 -e 直接执行后面的代码字符串。
# assert 使 require 失败或缺少 tcp Constructor 时以非 0 状态退出。
LUA_CPATH="$RUNTIME_ROOT/luaclib/?.so;;" \
    ./third_party/skynet/3rd/lua/lua -e \
    'local s = assert(require "socket.core"); assert(type(s.tcp) == "function")'

echo "LUAPANDA_RUNTIME_OK"
```

设置权限并构建：

```bash
chmod +x scripts/bootstrap_luapanda.sh \
    scripts/linux/build_luapanda.sh \
    tests/tooling/test_luapanda_runtime.sh
./scripts/linux/build_luapanda.sh
```

验证：

```bash
git -C third_party/luapanda rev-parse HEAD
git -C third_party/luasocket describe --tags --exact-match
file third_party/luapanda-runtime/luaclib/socket/core.so
ldd third_party/luapanda-runtime/luaclib/socket/core.so
```

### 19.4 `lualib/debug/luapanda_preload.lua`

```lua
-- 该文件只由 config/debug_luapanda.lua 指定为 LUA_PRELOAD。
-- 必须在 require "skynet" 之前启动 LuaPanda。
local skynet_core = require "skynet.core"

local function getenv(name)
    return skynet_core.command("GETENV", name)
end

local target = assert(getenv("luapanda_service"),
    "missing luapanda_service")
if SERVICE_NAME ~= target then
    return
end

local host = assert(getenv("luapanda_host"), "missing luapanda_host")
local port = assert(tonumber(getenv("luapanda_port")),
    "invalid luapanda_port")

require("LuaPanda").start(host, port)

-- skynet.lua 在加载时缓存 coroutine.create。LuaPanda 必须先包装它，
-- 消息分发 coroutine 才会进入 Debugger 的 Coroutine Pool。
local skynet = require "skynet"
skynet.error(string.format(
    "[LuaPanda] target=%s address=%s adapter=%s:%d coroutine_hook=ready",
    target,
    skynet.address(skynet.self()),
    host,
    port
))
```

如果先 `require "skynet"`，Adapter 仍可能连接，模块顶层断点也可能命中，但后来创建的消息 coroutine 不会被 LuaPanda 跟踪。验收不能停在“红点变实心”，必须触发真实 Login 并命中 `SOCKET.data` 或 `CMD.load`。

### 19.5 `config/debug_luapanda.lua`

```lua
include "game.lua"

preload = root .. "lualib/debug/luapanda_preload.lua"
lua_path = root .. "third_party/luapanda/Debugger/?.lua;" .. lua_path
lua_cpath = root .. "third_party/luapanda-runtime/luaclib/?.so;"
    .. lua_cpath

luapanda_service = "$LUAPANDA_SERVICE"
luapanda_host = "$LUAPANDA_HOST"
luapanda_port = "$LUAPANDA_PORT"
```

正常 `config/game.lua` 和 Test `config/test.lua` 都不加载 Debugger。LuaPanda 只能通过这个显式配置进入进程。

### 19.6 `scripts/linux/run_luapanda_server.sh`

```bash
#!/usr/bin/env bash

# 上面的 Shebang 必须位于第一行；直接执行脚本时，Linux 会从 PATH 中
# 找到 bash，并用它解释本文件。

# 打开 Bash 严格模式：
# -e：Debug 依赖准备或 Server 启动命令失败时停止脚本；
# -u：读取未定义变量时报错；
# -o pipefail：管道中任意一个命令失败，整条管道都算失败。
set -euo pipefail

# $0 是当前脚本的启动路径，dirname "$0" 取得 scripts/linux。
# $(...) 先执行 dirname，再把输出替换进 cd 命令。
# /../.. 从 scripts/linux 向上两级回到仓库根目录。
# 使用双引号，避免路径中的空格被 Bash 拆成多个参数。
cd "$(dirname "$0")/../.."

# $1、$2 是第一、第二个位置参数。
# ${变量:-默认值} 在参数未提供或为空时使用右侧默认值。
# 第一个参数选择唯一接入 LuaPanda 的 Service Name；第二个参数是 Adapter
# Port。默认调试 Watchdog，不让所有 Service 竞争同一端口。
TARGET_SERVICE="${1:-gateway/watchdog}"
TARGET_PORT="${2:-8818}"

# [[ ... ]] 是 Bash 条件表达式；! 对 -f 的文件判断取反；
# || 表示左右任一条件成立就进入 then；反斜杠连接下一物理行。
# Debugger Lua 文件或 socket.core 任一缺失时，恢复并构建完整 Debug Runtime。
if [[ ! -f third_party/luapanda/Debugger/LuaPanda.lua \
    || ! -f third_party/luapanda-runtime/luaclib/socket/core.so ]]; then
    ./scripts/linux/build_luapanda.sh
fi

# export 把 Shell Variable 放入后续 Child Process 的 Environment。
# config/debug_luapanda.lua 使用 $NAME 语法读取这些值。
# 它们只影响本脚本以及随后 exec 出来的 Skynet Process，不写入系统配置。
export LUAPANDA_SERVICE="$TARGET_SERVICE"
export LUAPANDA_HOST="127.0.0.1"
export LUAPANDA_PORT="$TARGET_PORT"

echo "LuaPanda target=$LUAPANDA_SERVICE adapter=$LUAPANDA_HOST:$LUAPANDA_PORT"

# 只有这条显式 Debug 入口使用 debug_luapanda.lua。普通 Server 和 Test
# 仍使用不加载 Debugger 的配置。exec 让 VS Code 直接管理 Skynet Process。
exec ./third_party/skynet/skynet config/debug_luapanda.lua
```

```bash
chmod +x scripts/linux/run_luapanda_server.sh
```

提交的是恢复脚本和接入代码，不提交下载/编译出来的第三方目录：

```bash
git add scripts/bootstrap_luapanda.sh \
    scripts/linux/build_luapanda.sh \
    scripts/linux/run_luapanda_server.sh \
    tests/tooling/test_luapanda_runtime.sh \
    lualib/debug/luapanda_preload.lua \
    config/debug_luapanda.lua
git diff --cached
git commit -m "build: add opt-in luapanda runtime"
git push
```

## 20. 写 VS Code Workspace 配置

### 20.1 `.vscode/extensions.json`

```json
{
  "recommendations": [
    "ms-vscode-remote.remote-wsl",
    "ms-vscode.cpptools",
    "sumneko.lua",
    "stuartwang.luapanda"
  ]
}
```

它只提供推荐，不自动安装扩展。

### 20.2 `.vscode/settings.json`

```json
{
  "files.exclude": {
    "third_party/skynet/.git": true
  },
  "files.associations": {
    "*.lua": "lua"
  },
  "Lua.runtime.version": "Lua 5.4",
  "Lua.runtime.path": [
    "?.lua",
    "?/init.lua",
    "lualib/?.lua",
    "lualib/?/init.lua",
    "third_party/skynet/lualib/?.lua",
    "third_party/skynet/lualib/?/init.lua"
  ],
  "Lua.workspace.library": [
    "${workspaceFolder}/lualib",
    "${workspaceFolder}/third_party/skynet/lualib"
  ],
  "Lua.workspace.checkThirdParty": false,
  "Lua.telemetry.enable": false,
  "lua_analyzer.codeLinting.enable": false
}
```

Lua Language Server 负责补全、跳转和静态检查；LuaPanda 负责运行期断点。关闭 LuaPanda 自带的旧 Lint，避免两套 Analyzer 重复报错。

### 20.3 `.vscode/tasks.json`

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "ARPG：构建 Skynet",
      "type": "shell",
      "command": "./scripts/linux/build.sh",
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "ARPG：Login E2E",
      "type": "shell",
      "command": "./scripts/linux/test.sh",
      "group": { "kind": "test", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "ARPG：准备 LuaPanda",
      "type": "shell",
      "command": "./scripts/linux/build_luapanda.sh",
      "problemMatcher": []
    },
    {
      "label": "ARPG：启动服务器",
      "type": "shell",
      "command": "./scripts/linux/run_server.sh",
      "presentation": { "reveal": "always", "panel": "dedicated" },
      "problemMatcher": []
    },
    {
      "label": "ARPG：Login Client",
      "type": "shell",
      "command": "./scripts/linux/run_client.sh",
      "presentation": { "reveal": "always", "panel": "dedicated" },
      "problemMatcher": []
    },
    {
      "label": "ARPG：Debug Console",
      "type": "shell",
      "command": "./scripts/linux/debug_console.sh",
      "presentation": { "reveal": "always", "panel": "dedicated" },
      "problemMatcher": []
    }
  ]
}
```

这些名称由当前工程定义，不是 VS Code 或 Skynet 内置 Task。WSL Workspace 直接执行 Linux Script。

### 20.4 `.vscode/launch.json`

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "ARPG Lua：Watchdog Login",
      "type": "lua",
      "request": "launch",
      "tag": "normal",
      "cwd": "${workspaceFolder}",
      "program": "${workspaceFolder}/scripts/linux/run_luapanda_server.sh",
      "args": ["gateway/watchdog", "8818"],
      "connectionPort": 8818,
      "stopOnEntry": false,
      "useCHook": false,
      "autoPathMode": true,
      "pathCaseSensitivity": true,
      "isNeedB64EncodeStr": true,
      "autoReconnect": false,
      "logLevel": 1,
      "preLaunchTask": "ARPG：准备 LuaPanda"
    },
    {
      "name": "ARPG Lua：PlayerAgent Load",
      "type": "lua",
      "request": "launch",
      "tag": "normal",
      "cwd": "${workspaceFolder}",
      "program": "${workspaceFolder}/scripts/linux/run_luapanda_server.sh",
      "args": ["player/player_agent", "8818"],
      "connectionPort": 8818,
      "stopOnEntry": false,
      "useCHook": false,
      "autoPathMode": true,
      "pathCaseSensitivity": true,
      "isNeedB64EncodeStr": true,
      "autoReconnect": false,
      "logLevel": 1,
      "preLaunchTask": "ARPG：准备 LuaPanda"
    },
    {
      "name": "ARPG Runtime：GDB",
      "type": "cppdbg",
      "request": "launch",
      "program": "${workspaceFolder}/third_party/skynet/skynet",
      "args": ["config/game.lua"],
      "cwd": "${workspaceFolder}",
      "stopAtEntry": false,
      "externalConsole": false,
      "MIMode": "gdb",
      "miDebuggerPath": "/usr/bin/gdb",
      "setupCommands": [
        {
          "description": "Enable pretty-printing",
          "text": "-enable-pretty-printing",
          "ignoreFailures": true
        }
      ],
      "preLaunchTask": "ARPG：构建 Skynet"
    }
  ]
}
```

`useCHook=false` 避免加载针对未知 Lua ABI 预编译的 C Hook。一次只调试一个明确 Service；多个同名 PlayerAgent 同时连接同一 8818 Port 会互相竞争，本课只启动一个测试玩家。

提交 Workspace 配置：

```bash
git add .vscode/extensions.json .vscode/settings.json \
    .vscode/tasks.json .vscode/launch.json
git diff --cached
git commit -m "chore: add vscode build and debug configuration"
git push
```

## 21. LuaPanda 调试完整 Login 链

调试前先停止普通 Server、Test Server 和旧 Debug Session：

```bash
ss -ltnp | grep -E ':8888|:8818' || true
ps -ef | grep '[s]kynet'
```

优先回到对应的 VS Code WSL 集成终端按 `Ctrl+C`，不要用不限定目标的 `killall`。

### 21.1 Watchdog Login 断点

在 `service/gateway/watchdog.lua::SOCKET.data` 设置三个断点：

```lua
local connection = connections[fd]
```

```lua
local auth_ok = player_id
```

```lua
local agent, is_new, load_error = skynet.call(
```

按 F5，选择：

```text
ARPG Lua：Watchdog Login
```

F5 会先执行 `ARPG：准备 LuaPanda`，再启动 `run_luapanda_server.sh gateway/watchdog 8818`。等待 VS Code 启动的服务器集成终端出现：

```text
[LuaPanda] target=gateway/watchdog ... coroutine_hook=ready
[Main] startup complete
```

在同一个 WSL Workspace 中新建一个**终端 C**实例，并重命名为 `LOGIN-CLIENT`：

```bash
cd ~/workspace/skynet-mmo-arpg
./scripts/linux/run_client.sh --player=10001
```

必须在 `LOGIN-CLIENT` 输入命令。LuaPanda 启动出来的集成终端运行 Server，不接收 Client 命令。

命中第一个断点后检查：

```text
fd                  当前 Gate fd
connection.id       逻辑连接代际
connection.state    CONNECTED
msg                 已去掉 2-byte Header 的 Sproto Payload
```

执行到 `connection.state = "AUTHING"` 后再跨过 `skynet.call(auth_service, ...)`。Call 前当前 Watchdog coroutine 准备发送 Request；Call 后一行只有 Auth Response 返回、该 coroutine 恢复后才会执行。

在 Watch 面板加入：

```text
alive(fd, connection)
connection.state
player_id
auth_ok
```

继续到 PlayerMgr Call，观察 `agent` 从 nil 变成 Skynet Address。最后继续运行，Client 应打印 `LOGIN_OK`。

### 21.2 PlayerAgent 动态创建断点

停止上一轮 Debug Session。在 `service/player/player_agent.lua::CMD.load` 设置断点：

```lua
storage_mgr = assert(conf.storage_mgr)
```

以及 Storage Call 恢复后的：

```lua
player = result
```

按 F5 选择：

```text
ARPG Lua：PlayerAgent Load
```

Server 启动后 LuaPanda 可能显示等待连接。这时 PlayerAgent 尚不存在。运行 `LOGIN-CLIENT` 后，PlayerMgr 才执行：

```lua
skynet.newservice("player/player_agent")
```

目标 Service 的 Preload 随 Loader 执行，随后连接 8818。命中断点后检查：

```text
SERVICE_NAME == "player/player_agent"
conf.player_id == 10001
storage_mgr 是另一个 Service Address
state == "LOADING"
```

跨过 Storage Call 后检查 `result`，继续到 `state = STATE_LOADED`。随后 `CMD.bind_client` 将状态改成 `ONLINE`，Watchdog 才能生成 Login Response。

### 21.3 断点没命中时按现场排查

| 现场 | 检查 |
|---|---|
| 红点为空心 | 目标 Lua State 尚未连接；PlayerAgent 必须由 Login 动态创建 |
| 服务器没有 LuaPanda Ready 日志 | Launch Configuration 的 Service Name 与实际 `newservice` 名称不一致 |
| Adapter 已连接，Handler 不命中 | 检查 Preload 是否在 `require "skynet"` 前启动 LuaPanda |
| 8888 Address Already in Use | 普通 Server 或旧 Debug Server 未停止 |
| 8818 Address Already in Use | 旧 LuaPanda Session 未停止 |
| Client Connection Refused | 等待 Debug Server 输出 `startup complete` |
| Client 卡住 | 查看 VS Code 是否停在断点；继续目标 coroutine 后 Response 才会返回 |

LuaPanda 会改变 coroutine 调度和耗时，只用于个人隔离环境。断点没有复现 Race，不能证明代码没有 Race。

## 22. GDB 调试 Skynet C Runtime

停止 LuaPanda。先用命令行 GDB 看清动态库和函数断点：

```bash
cd ~/workspace/skynet-mmo-arpg
gdb --args ./third_party/skynet/skynet config/game.lua
```

在 `(gdb)` 中输入：

```gdb
set pagination off
set breakpoint pending on
break main
break skynet_start
break skynet_context_new
break snlua_create
break thread_worker
run
```

`snlua_create` 来自稍后加载的 `cservice/snlua.so`，GDB 可能询问是否建立 Pending Breakpoint，输入 `y`。

停在 `main`：

```gdb
print argc
print argv[1]
bt
continue
```

`argv[1]` 应是 `config/game.lua`。

停在 `skynet_start`：

```gdb
print config->thread
print config->module_path
print config->bootstrap
continue
```

应看到 `8`、`./third_party/skynet/cservice/?.so` 和 `snlua bootstrap`。

`skynet_context_new` 会多次命中。检查：

```gdb
print name
print param
bt
continue
```

早期应观察到 `logger`，随后是 `name="snlua"`、`param="bootstrap"`。命中 `snlua_create` 后：

```gdb
bt
next
```

`third_party/skynet/service-src/service_snlua.c::snlua_create` 中的 `lua_newstate(lalloc, l)` 创建一个 snlua 实例私有的 Lua State。

命中 `thread_worker` 时，Runtime 已经开始创建 Worker：

```gdb
info threads
thread apply all bt 3
continue
```

此时可以看到 Monitor、Timer、Socket 和多个 Worker。`config.thread = 8` 只表示 Worker 数，不包含三个系统线程。

结束：

```gdb
kill
quit
```

再在 VS Code “运行和调试”选择 `ARPG Runtime：GDB`，在相同函数设置图形断点。Windows VS Code 提供 UI，C/C++ Extension、`/usr/bin/gdb` 和 Skynet Process 都运行在 Ubuntu。

## 23. 用现有现场还原完整启动链

### 23.1 配置 Lua State

源码：`third_party/skynet/skynet-src/skynet_main.c::main`

执行顺序：

```text
读取 argv[1]
  -> skynet_globalinit / skynet_env_init
  -> luaL_newstate 创建临时配置 State
  -> 执行内嵌 load_config
  -> 读取 config/game.lua
  -> _init_env 把配置写入 Skynet Environment
  -> lua_close 关闭临时 State
  -> 组装 skynet_config
  -> skynet_start
```

这个 State 只用于配置，不属于 Main、Watchdog 或 PlayerAgent。配置 Lua Table 在 `lua_close` 后不存在，业务 Service 通过 `skynet.getenv` 读取 Environment String。

### 23.2 Runtime 初始化与首个 snlua

源码：`third_party/skynet/skynet-src/skynet_start.c::skynet_start`

它初始化 Handle、Message Queue、Module、Timer 和 Socket，创建 logger，再把：

```text
snlua bootstrap
```

拆成 Module Name 与参数，调用 `skynet_context_new`。`cpath` 让 Module Loader 找到 `third_party/skynet/cservice/snlua.so`。

### 23.3 snlua Loader

源码：

```text
third_party/skynet/service-src/service_snlua.c::snlua_create
third_party/skynet/service-src/service_snlua.c::init_cb
third_party/skynet/lualib/loader.lua
```

每个 snlua 实例调用 `lua_newstate`。`init_cb` 设置 `LUA_SERVICE`、`LUA_PATH`、`LUA_CPATH`，再加载 `loader.lua`。Loader 把参数中的 Service Name 代入 `luaservice` Pattern。

`bootstrap` 在自己的 `service/?.lua` 中不存在，随后命中官方：

```text
third_party/skynet/service/bootstrap.lua
```

### 23.4 官方 Bootstrap 到业务 Main

官方 Bootstrap 创建 `.launcher`、`.cslave`、`DATACENTER` 和 `service_mgr`，读取 `start = "main"`，通过 `.launcher` 创建新 snlua Service。这一次 Loader 在本项目找到：

```text
service/main.lua
```

官方 Bootstrap 随后退出。业务 Main 按依赖顺序创建：

```text
ProtocolLoader
  -> StorageMgr
  -> MemoryWorker × 2
  -> PlayerMgr
  -> Auth
  -> Watchdog
  -> official gate
  -> Debug Console
  -> Main exit
```

Main 退出后进程继续运行，因为其他 Service Context 仍然存在。

### 23.5 一条 Login 的 Process、Thread、Service、State 和 coroutine

```text
Process
  一个 third_party/skynet/skynet Linux Process

Socket Thread
  接收 TCP 数据，产生 Socket Event

Gate Service
  按 2-byte Header 切出 Sproto Payload

Worker Thread A / Watchdog Lua State / data coroutine
  解码 Login
  call Auth -> yield

Worker Thread B / Auth Lua State / verify coroutine
  校验 dev:<player_id>，返回

某个 Worker / Watchdog 原 coroutine
  恢复，检查 connection 仍存活
  call PlayerMgr -> yield

PlayerMgr Lua State / login coroutine
  进入 player_id 对应 queue
  newservice PlayerAgent -> yield
  call Agent.load -> yield

PlayerAgent Lua State / load coroutine
  call StorageMgr -> yield

StorageMgr Lua State / load coroutine
  call MemoryWorker -> yield

MemoryWorker Lua State
  读取自己的 players，返回 Clone

Response 逐层恢复
  MemoryWorker -> StorageMgr -> PlayerAgent -> PlayerMgr -> Watchdog

Watchdog
  bind Agent
  Gate forward
  Frame.write Login Response

Client
  解 Frame，按 session 匹配 Response，输出 LOGIN_OK
```

Worker 只在某段时间执行某个 Service coroutine，不永久属于该 Service。一个 coroutine 在 `skynet.call` 处 yield 后，其他消息可以进入同一 Service 并修改它的 Lua State，所以 Watchdog 每次恢复都重新验证连接。

## 24. 完成 Feature Branch，合并到 Main

合并前先把根目录的 `README.md` 更新为当前工程的实际使用说明。课程做到这里，仓库已经从空目录变成可独立恢复的 Login Server；README 也应从最初的目标说明改成新同事 Clone 后能够直接执行的入口文档。

完整路径：`README.md`

````markdown
# Skynet MMO ARPG Server

当前阶段已经完成一条可运行的 Login 链路：TCP Client 通过 Sproto 发送 `login` 请求，Watchdog 完成 Auth 校验并调用 PlayerMgr 创建 PlayerAgent，PlayerAgent 经 StorageMgr 加载数据，绑定连接后返回 Player Snapshot。

## 环境

- Ubuntu 运行环境；Windows 开发机使用 WSL2 Ubuntu
- GCC、Make、Autoconf、Git、GDB、Netcat、rlwrap、curl
- Windows VS Code 通过 WSL Extension 打开本仓库

工程固定使用 Skynet v1.8.0。Skynet 源码和编译产物位于忽略提交的 `third_party/`，由 Bootstrap Script 恢复。

## 从新 Clone 恢复

```bash
sudo apt update
sudo apt install -y build-essential autoconf git gdb netcat-openbsd \
    rlwrap curl ca-certificates pkg-config file binutils gh

./scripts/bootstrap_skynet.sh
./scripts/linux/build.sh
./scripts/linux/test.sh
```

测试结束时应看到：

```text
LOGIN_E2E_OK
ALL_TESTS_OK
```

## 手工运行 Login

VS Code WSL 集成终端 `SERVER`：

```bash
./scripts/linux/run_server.sh
```

另一个 VS Code WSL 集成终端 `CLIENT`：

```bash
./scripts/linux/run_client.sh --player=10001
```

Client 应输出 `LOGIN_OK`。开发环境 Token 规则为 `dev:<player_id>`；该规则只用于课程阶段，不可直接用于生产认证。

## 调试入口

- Skynet Debug Console：`./scripts/linux/debug_console.sh`
- LuaPanda：先执行 `./scripts/linux/build_luapanda.sh`，再从 VS Code 选择显式 LuaPanda Launch Configuration
- C Runtime：`gdb --args ./third_party/skynet/skynet config/game.lua`

普通启动、E2E 和生产式配置都不会加载 LuaPanda。只有 `config/debug_luapanda.lua` 会执行 Debugger Preload。

## Login 消息路径

```text
client/login_client.lua
  -> Gate
  -> service/gateway/watchdog.lua
  -> service/auth/auth.lua（校验后返回 Watchdog）
  -> service/player/player_mgr.lua
  -> service/player/player_agent.lua
  -> service/storage/storage_mgr.lua
  -> service/storage/memory_worker.lua
  -> Response 逐层返回 Watchdog
  -> Gate forward 到 PlayerAgent
  -> Watchdog Response
  -> Client
```

PlayerAgent 持有在线玩家状态，MemoryWorker 持有持久化数据的内存替身，Watchdog 持有连接阶段和当前 Agent Handle。Watchdog 在每个 `skynet.call` 恢复后都会检查连接是否仍然有效。
````

上面的大段代码围栏里嵌套了 README 自己的代码围栏。实际编辑 `README.md` 时，只复制最外层四个反引号之间的内容。

检查最终目录。这里排除 `.git` 和可重建的 `third_party`，避免输出几千个上游文件：

```bash
find . \
    -path './.git' -prune -o \
    -path './third_party' -prune -o \
    -type f -print | sort
```

应至少看到这些由本课创建的文件：

```text
./.gitattributes
./.gitignore
./.vscode/extensions.json
./.vscode/launch.json
./.vscode/settings.json
./.vscode/tasks.json
./Makefile
./README.md
./client/login_client.lua
./config/debug_luapanda.lua
./config/game.lua
./config/test.lua
./lualib/debug/luapanda_preload.lua
./lualib/protocol/frame.lua
./lualib/protocol/schema.lua
./scripts/bootstrap_luapanda.sh
./scripts/bootstrap_skynet.sh
./scripts/linux/build.sh
./scripts/linux/build_luapanda.sh
./scripts/linux/debug_console.sh
./scripts/linux/run_client.sh
./scripts/linux/run_luapanda_server.sh
./scripts/linux/run_server.sh
./scripts/linux/test.sh
./service/auth/auth.lua
./service/gateway/watchdog.lua
./service/main.lua
./service/player/player_agent.lua
./service/player/player_mgr.lua
./service/protocol/protoloader.lua
./service/storage/memory_worker.lua
./service/storage/storage_mgr.lua
./tests/integration/login_smoke.sh
./tests/tooling/test_luapanda_runtime.sh
```

把 README 更新纳入 Feature Branch：

```bash
git add README.md
git diff --cached
git commit -m "docs: complete login server usage guide"
git push
```

先停止所有 Server 和 Debug Session，重新跑正常配置测试：

```bash
./scripts/linux/test.sh
git status --short
git log --oneline --decorate --graph --all
```

Working Tree 必须干净，测试必须结束于 `ALL_TESTS_OK`。确认 Feature Branch 已 Push：

```bash
git push
```

切回 Main，取得远程最新状态：

```bash
git switch main
git pull --ff-only
```

`git pull --ff-only` 可以按 `git fetch` 加一次受限的本地更新来理解。它和 `svn update` 都会取得服务器上的新版本，但 Git 还要更新本地 Branch Pointer；`--ff-only` 要求本地没有需要合并的分叉，发现分叉就停止，让开发者先查看 Commit Graph。

合并：

```bash
git merge --no-ff feature/login
```

`git merge` 把另一条 Branch 的 Commit History接到当前 Branch。`--no-ff` 即使可以直接移动 `main` 指针，也保留一个明确的 Merge Commit，使 Git Log 中能看出 Login 功能的开发边界。SVN 常通过 Branch 目录和 Mergeinfo 记录合并；Git 直接在 Commit Graph 中记录 Parent 关系。

合并后再测试，不能只相信 Feature Branch 上的结果：

```bash
./scripts/linux/test.sh
git status --short
git log --oneline --decorate --graph --all -n 30
git push origin main
```

给第一课验收点打 Annotated Tag：

```bash
git tag -a lesson-1-login -m "Lesson 1: runnable login server"
git show lesson-1-login --stat
git push origin lesson-1-login
```

Git Tag 类似给某个 Revision 一个稳定名称。SVN 项目常用 `/tags` 目录复制形成 Release Tag；Git Tag 直接指向 Commit。`-a` 创建带作者、时间和 Message 的 Annotated Tag。

`git show <对象>` 展示一个 Commit 或 Tag 指向的内容；`--stat` 只显示文件变更统计，便于 Push 前确认 Tag 落在预期 Merge Commit。

本地 Feature Branch 已合并后可以删除：

```bash
git branch -d feature/login
```

`-d` 只允许删除已经 Merge 的 Branch，删除的是本地 Branch Reference，不删除 Commit，也不删除远程 `origin/feature/login`。本课保留远程 Branch 作为学习记录。

## 25. 常见故障按层定位

| 现象 | 所在层 | 检查 |
|---|---|---|
| `/usr/bin/env: bash\r` | 文件格式 | `.gitattributes`、VS Code LF、重新保存脚本 |
| `Need a config file` | ELF 入口 | `run_server.sh` 是否传入 `config/game.lua` |
| 找不到 `bootstrap.lua` | snlua Loader | `luaservice` 是否包含 Skynet `service/?.lua` |
| `module 'protocol.schema' not found` | Lua Module Path | `lua_path` 是否包含 `lualib/?.lua` |
| `sprotoloader.load(1)` 失败 | Service 启动顺序 | ProtocolLoader 是否先于 Watchdog |
| `connection refused` | Socket Listen | Server 是否存活，8888/18888 是否监听 |
| Login 无 Response | Watchdog coroutine | LuaPanda 是否停在断点；Server Log 是否报 Handler Error |
| `AUTH_FAILED` | Auth | Token 是否严格为 `dev:<player_id>` |
| `PLAYER_NOT_FOUND` | Storage | 只预置了 10001、10002；检查 Hash Worker |
| `ALREADY_ONLINE` | PlayerAgent 生命周期 | 旧连接是否仍绑定；Debug Console 查看 Agent |
| Test Server 启动失败 | 测试隔离 | 18888 是否被旧进程占用 |
| `socket.core` 找不到 | LuaPanda Runtime | 重新执行 `build_luapanda.sh` 并看 Runtime Test |
| Git Push 认证失败 | GitHub 凭据 | `gh auth status`、`gh auth setup-git` |
| Push Non-fast-forward | 远程历史领先 | `git fetch` 后检查 Graph，禁止直接 Force Push |

## 26. 第一课练习

先完成操作，再看下一节答案。

### 练习一：从空目录复写最小启动链

不复制现有文件，在另一个临时空目录重新写出 `bootstrap_skynet.sh`、`build.sh`、`config/game.lua`、`service/main.lua` 和 `run_server.sh`，让 Main 输出一条日志后退出。说明三个 Native 产物的加载方。

### 练习二：手画 Login 时序

从 Client `socket.send` 开始，写到 Client 输出 `LOGIN_OK`。每次 `skynet.call` 标注调用方、接收方、yield 和 Response 返回后的恢复位置。

### 练习三：连接在 Auth Call 期间关闭

在 Watchdog 的 Auth Call 前后下断点。解释 Client 关闭后，为什么原 Login coroutine 恢复时不能继续使用局部变量 `connection`。

### 练习四：两个相同玩家同时登录

说明 PlayerMgr 为什么不能只写“查表为空 → newservice → 写表”。指出 `skynet.queue` 覆盖的代码范围，以及本课对第二条连接的处理结果。

### 练习五：Git 恢复误 Stage

新建一个不应提交的 `scratch.txt`，再修改 `README.md`。故意把两者都 Stage，然后只撤销 `scratch.txt` 的 Stage，保留磁盘文件，最后提交 README。

### 练习六：区分配置 Lua State 和 Service Lua State

用 GDB 的断点和源码说明两个 State 分别在哪里创建、何时销毁、由谁使用。

### 练习七：重新拉取并验收远程工程

在另一个临时目录 Clone `SkynetMMOServerTest`，按 README/脚本恢复 Skynet，运行 Login E2E。该练习验证远程仓库是否保存了足够的重建信息。

### 练习八：设计 Unity 与 H5 的 Login 接入

不修改 Server 业务 Service，分别画出 Unity 原生客户端和 H5 客户端发出 `login`、收到 Response 的字节路径。标明 Transport、消息边界、Sproto Codec、RPC session 和 64 位 `player_id` 在客户端使用的类型。说明哪些代码可以共用，哪些只能留在 TCP 或 WebSocket Adapter。

## 27. 参考答案

### 答案一

Shell 调用 `third_party/skynet/skynet config/game.lua`。ELF 主程序读取配置，加载 `cservice/snlua.so` 创建 snlua Service；Service Lua State 中的 `require "skynet"` 再加载 `luaclib/skynet.so`。最小 Main 调用 `skynet.exit()` 后没有其他长期 Service，Process 正常结束。

### 答案二

```text
Client login_client.lua
  -> TCP Frame 到 Gate
  -> Gate send Watchdog socket/data
  -> Watchdog host:dispatch
  -> call Auth，Watchdog coroutine yield
  -> Auth retpack，Watchdog 恢复并 alive check
  -> call PlayerMgr，Watchdog yield
  -> PlayerMgr queue 内 newservice/call Agent.load，PlayerMgr yield
  -> Agent call StorageMgr，Agent yield
  -> StorageMgr call MemoryWorker，StorageMgr yield
  -> Worker 返回玩家 Clone
  -> 调用链逆序恢复
  -> Watchdog call Agent.bind_client，yield/恢复
  -> Watchdog call Gate.forward，yield/恢复
  -> frame.write Login Response
  -> Client 按 session 解 Response
```

### 答案三

`connection` 是 Watchdog coroutine 在 yield 前保存的 Lua Table Reference。Auth 等待期间，Gate Close Event 可以进入 Watchdog 的另一个 coroutine，执行 `connections[fd] = nil`；fd 后续还可能复用。原 coroutine 恢复时必须用 `connections[fd] == connection` 重新确认 Table Identity，不能因为局部变量仍指向旧 Table 就认为连接有效。

### 答案四

`newservice` 和 `call Agent.load` 都会 yield，两个 Login coroutine 可在第一个还未写表时同时创建 Agent。`player_lock(player_id)(function ... end)` 从查表、创建、Load 到写入路由全部串行化。第二条连接拿到已有 Agent，`CMD.bind_client` 看到 Agent 已是 `ONLINE`，返回 `ALREADY_ONLINE`，Watchdog 给新连接返回 code 3 并关闭它；第一条连接保持在线。

### 答案五

```bash
# 使用 VS Code 新建 scratch.txt，并在 README.md 追加一行课程记录，然后：
git add scratch.txt README.md
git status --short
git restore --staged scratch.txt
git diff --cached
git commit -m "docs: record lesson one completion"
```

`git restore --staged <path>` 只把该路径从 Staging Area 撤回，不删除 Working Tree 文件。SVN 没有对应的常驻 Staging Area；这是 Git 提交前重新组织 Change Set 的常用操作。Commit 后删除未 Track 的 `scratch.txt`。

### 答案六

`third_party/skynet/skynet-src/skynet_main.c::main` 调用 `luaL_newstate` 创建配置 State，执行 `config/game.lua`、写入 Environment 后立即 `lua_close`。`third_party/skynet/service-src/service_snlua.c::snlua_create` 调用 `lua_newstate(lalloc, l)` 创建某个 snlua 实例的 State，它加载 `loader.lua` 和具体 Service，存活到该 Service Release。不同 Service 不共享普通 Lua Global/Table。

### 答案七

```bash
cd ~/workspace
git clone https://github.com/simbiwu/SkynetMMOServerTest.git verify-login
cd verify-login
./scripts/bootstrap_skynet.sh
./scripts/linux/build.sh
./scripts/linux/test.sh
git describe --tags --always
```

成功条件是新目录没有借用原工程的 `third_party`，仍然输出 `ALL_TESTS_OK`，并且 `git describe` 能看到 `lesson-1-login`。

### 答案八

```text
Unity Windows/Android/iOS
  LoginRequest(C#，player_id 使用 long)
  -> C# Sproto Codec 编码业务结构
  -> RPC Envelope 写入 type/session
  -> TCP Adapter 加 2-byte big-endian Length
  -> Skynet Gate 拆 Frame
  -> Watchdog host:dispatch
  -> Auth/PlayerMgr/PlayerAgent
  -> response Closure 编码 Sproto Payload
  -> TCP Frame
  -> Unity TCP Adapter 拆 Frame
  -> 按 session 完成 Pending Request

H5 / Unity WebGL
  LoginRequest(TypeScript，player_id 使用 BigInt 或 String)
  -> TypeScript Sproto Codec 编码业务结构
  -> RPC Envelope 写入 type/session
  -> WebSocket Binary Message，不增加 TCP 的 2-byte Header
  -> Skynet WebSocket Gateway 取得完整 Payload
  -> 与 TCP 入口共用 Sproto dispatch 和后续业务链
  -> WebSocket Binary Response
  -> 按 session 完成 Promise
```

两端共用权威 `.sproto` 定义、协议 ID、Field Tag、生成规则、RPC session 语义和互通样本。TCP 的粘包缓冲与两字节 Header 只属于 Unity Native TCP Adapter；WebSocket Handshake、Ping/Pong 和 Binary Message 只属于 H5/WebGL Adapter。Watchdog 后面的 Auth、PlayerMgr 和 PlayerAgent 不因前端类型分叉。

## 28. 课程结束检查表

```text
[ ] Ubuntu VHDX 位于 G:\WSL\Ubuntu
[ ] 实操工程位于 ~/workspace/skynet-mmo-arpg
[ ] origin 指向 simbiwu/SkynetMMOServerTest
[ ] main 与 origin/main 同步
[ ] lesson-1-login Tag 已 Push
[ ] Skynet 固定为 v1.8.0
[ ] 正确 Token 输出 LOGIN_OK
[ ] 错误 Token 输出 AUTH_FAILED
[ ] E2E 输出 LOGIN_E2E_OK 和 ALL_TESTS_OK
[ ] Debug Console 能观察 PlayerAgent
[ ] LuaPanda 能命中 Watchdog 和动态 PlayerAgent
[ ] GDB 能命中 Runtime 与 snlua 创建函数
[ ] 能解释每次 call 的 yield 与恢复检查
[ ] 能区分 TCP Frame 大端长度与 Sproto 内部小端字段
[ ] 能说明当前链路未使用 sproto.pack/unpack
[ ] 能说明 Unity 与 H5 的 Transport、64 位整数和 Codec 边界
[ ] 能在新的 Clone 中仅靠脚本恢复并通过测试
```

完成第一课后，`SkynetMMOServerTest` 已经是一套可以继续开发的 Login Server。下一阶段会在 PlayerAgent 后接 Scene，并把登录后的 Client Packet Dispatcher、Move、AOI 和状态所有权加入同一个工程。

上游资料：

- Microsoft WSL 安装：<https://learn.microsoft.com/windows/wsl/install>
- Microsoft WSL 基本命令：<https://learn.microsoft.com/windows/wsl/basic-commands>
- Skynet v1.8.0：<https://github.com/cloudwu/skynet/tree/v1.8.0>
- Tencent LuaPanda：<https://github.com/Tencent/LuaPanda>
- LuaSocket v3.1.0：<https://github.com/lunarmodules/luasocket/releases/tag/v3.1.0>
