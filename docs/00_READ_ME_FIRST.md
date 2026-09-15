# 00 - 从这里开始：构建、调试与生产向学习路线

这是一份环境操作入口。完整四课主线与能力验收统一见 `docs/COURSE_CATALOG.md`；第一次接触工程时执行本文的构建、运行和调试步骤即可，其他编号文档是专题参考，不要求逐份打开。

## 学习者定位

本文按“有多年 MMO Server C++ 主程经验、熟悉 Lua、准备把 Skynet 用于真实工作”的背景组织，不重复讲解 TCP、Lua 语法或普通服务器分层。培训重点是 Skynet 与传统 C++ MMO Server 在调度、消息、Coroutine、状态所有权和故障诊断上的差异。

学习结果不以“示例可以运行”为终点，而以能够完成以下工作为准：

- 从源码和构建产物解释 Skynet Runtime 如何运行；
- 跟踪请求所在线程、Service、消息队列和 Coroutine；
- 审查每个 yield 前后的状态一致性；
- 为真实项目设计 Gate、PlayerAgent、Scene 和 Storage 边界；
- 使用断点、测试、Trace、状态快照、Profiling 和 Core Dump 定位问题；
- 根据观测和 Benchmark 做容量规划与性能优化。

## 这个工程教什么

本工程不是可直接投产的通用框架。P0 目标是在一条可运行的 MMO 链路中，把 Skynet 的 Actor、消息、Coroutine、状态归属和竞态展示清楚：

```text
Client
  -> Gate
  -> Watchdog（登录前）
  -> Auth
  -> PlayerMgr
  -> PlayerAgent
  -> Storage
  -> SceneMgr
  -> Scene/AOI/Combat
  -> PlayerAgent
  -> Gate/Socket
  -> Client
```

不要先把重复的 `skynet.dispatch` 抽象成大型 base service。这里保留适量重复，是为了打开任意 Service 都能直接看见消息如何进入、如何返回，以及状态属于谁。

## Windows 用户：从零运行

### 1. 安装 Ubuntu/WSL2

用管理员 PowerShell 执行：

```powershell
wsl --install -d Ubuntu
```

按提示重启 Windows。重启后从开始菜单搜索并打开 `Ubuntu`，首次启动时创建一个小写英文用户名和密码。输入 Linux 密码时屏幕不显示字符是正常现象。

在 Ubuntu 中安装工具：

```bash
sudo apt update
sudo apt install -y build-essential autoconf git gdb netcat-openbsd rlwrap
```

如果安装、首次启动或盘符挂载出现问题，再查阅 `docs/09_WINDOWS_WSL2.md`；正常情况下不需要先读它。

### 2. 用 Windows 版 VS Code 打开工程

Windows 安装 VS Code 和 Microsoft 的 `WSL` extension。然后在 Ubuntu terminal 执行：

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
code .
```

VS Code 仍是 Windows 应用；Skynet、Lua、GCC 和 GDB 在 Ubuntu 中运行。打开后确认左下角显示：

```text
WSL: Ubuntu
```

在 VS Code terminal 验证：

```bash
uname -a
pwd
```

`uname` 应显示 Linux，`pwd` 应显示 `/mnt/g/simbi/dev/skynet-mmo-learning`。

### 3. 第一次构建和测试

在 VS Code 按 `Ctrl+Shift+P`，运行 `Tasks: Run Task`，依次选择：

1. `Skynet MMO：拉取 v1.8.0`
2. `Skynet MMO：构建`
3. `Skynet MMO：完整测试`

三项都成功后，环境才算准备完成。

### 4. 启动服务器和客户端

运行 task `Skynet MMO：启动服务器`，看到下面的日志表示启动成功：

```text
[Main] startup complete
```

保持服务器 terminal 不关闭，再运行 task `Skynet MMO：启动交互客户端`，输入：

```text
ping
move 101 100
attack 100001
logout
```

命令行用户也可以直接执行：

```bash
./scripts/bootstrap_skynet.sh
./scripts/linux/build.sh
./scripts/linux/test.sh
./scripts/linux/run_server.sh
```

另开一个 Ubuntu terminal：

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
./scripts/linux/run_client.sh
```

## 当前可用的调试入口

当前工程已经具备三类调试入口：

- Lua 业务层：VS Code + LuaPanda 图形断点、单元测试和集成测试；
- Skynet Service：Debug Console 查看 Service、Mailbox 和 Coroutine 状态；
- C Runtime：Windows VS Code 作为界面，使用 WSL Ubuntu 中的 GDB。

连接后先尝试：

```text
help
list
stat
```

- `list` 查看所有 Service 地址。
- `stat` 查看消息数量和 mailbox 状态。
- `task :Service地址` 查看某个 Service 的 Coroutine。

Lua Language Server 负责补全、跳转和静态检查；LuaPanda 负责运行期断点，两者职责不同。第一次使用 LuaPanda 前运行 task `Skynet MMO：准备 LuaPanda 调试环境`，随后在“运行和调试”中选择 Scene 或 PlayerAgent Configuration。详细配置、接入链路、限制与故障排查见 `docs/16_DEBUGGING.md`。

## 四课生产向学习主线

课程不按天数推进，每课都以“能解释、能操作、能调试、能验证”为完成标准。详细章节、配套专题和验收项集中在 `docs/COURSE_CATALOG.md`，这里不再维护第二份分散目录。

1. 第一课：启动链、构建与调试工具链。主教材 `docs/Skynet第一课_启动链源码导读_重写版.pdf`。
2. 第二课：Service 模型与 Actor 架构。主教材 `docs/Skynet第二课_Service模型与Actor架构.md` 及同名 PDF。
3. 第三课：完整 MMO 业务闭环与一致性。
4. 第四课：生产工程、故障诊断与性能。

当前应在第一课的环境、启动链和断点验收完成后进入第二课；不要跳过 Service coroutine 重入与状态所有权，直接开始堆业务系统。

## 始终牢记的三条规则

1. Service 是状态所有者，不只是一个 Lua 文件。PlayerAgent 拥有持久玩家状态；Scene 拥有实时空间状态。
2. `skynet.call` 看似同步，实际会让当前 Coroutine yield。恢复后必须重新判断旧状态是否仍然有效。
3. 一个 hot Service 仍是单 Actor 瓶颈。增加 `thread` 不会让同一个 Scene 的 Lua 同时使用多个 CPU core；扩展依赖场景分线、分片或 Actor 拆分。

## 其他文档什么时候看

- Windows/Ubuntu 安装失败：`docs/09_WINDOWS_WSL2.md`
- Linux 主机部署：`docs/10_LINUX.md`
- 逐行调试或 GDB：`docs/16_DEBUGGING.md`
- 四课统一目录：`docs/COURSE_CATALOG.md`
- 第一课启动链源码教材：`docs/Skynet第一课_启动链源码导读_重写版.pdf`
- 第二课 Service/Actor 教材：`docs/Skynet第二课_Service模型与Actor架构.md` 或同名 PDF
- MySQL 存储：`docs/07_STORAGE.md`
- 测试和 benchmark：`docs/08_TESTING_AND_BENCHMARK.md`
- 已知生产差距：`docs/13_PRODUCTION_GAPS.md`

正常入门不需要按编号阅读所有文档；本文会在对应阶段告诉你下一份应该看什么。
