# 00 - 从这里开始：构建、调试与生产向学习路线

这是一份唯一的入门入口。第一次接触工程时只阅读并执行本文即可；其他文档是专题参考，不要求现在逐份打开。

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

## 生产向学习路线

本路线不设天数、周数或赶进度目标。每一阶段都按照“能解释、能操作、能调试、能验证”的标准验收；没有形成可靠心智模型时不急于进入下一阶段。讲解从可观察现象进入实现源码，逐层深入，但不牺牲生产级严谨性。

### 第一阶段：构建链和产物

不把 `make linux` 当作黑盒。需要掌握：

- 官方 Skynet v1.8.0 及 Submodule 如何固定；
- GCC、Make、Bundled Lua 5.4.7 和 jemalloc 分别参与哪一步；
- `skynet`、`cservice/*.so`、`luaclib/*.so` 和 Lua 源码各自如何产生、加载；
- 为什么业务 Lua 修改通常只需重启，而 C Runtime 修改需要重新构建；
- VS Code Task、Windows wrapper、WSL Bash 脚本之间的调用关系。

验收动作：完成一次 Clean Build 观察全量产物，再修改一个 Lua Service 和一个受控的 C Runtime 位置，比较两条迭代路径。任何源码实验都应保留可恢复性，不直接污染固定的上游基线。

### 第二阶段：启动链和调试链

从下面的真实启动命令开始：

```bash
./third_party/skynet/skynet config/game.lua
```

跟踪 `config/game.lua`、Skynet `bootstrap`、`service/main.lua` 到业务 Service 的创建顺序。随后分别练习：

- 用 Debug Console 检查 Service、Mailbox 和 Coroutine；
- 用 GDB 启动 Skynet、设置 C 断点、查看线程和调用栈；
- 对纯 Lua 逻辑运行可复现测试并建立源码断点能力；
- 制造启动失败、协议错误、RPC 等待和进程崩溃，区分各自的证据与诊断工具。

这一阶段不是只学命令，而是建立调试决策：什么问题使用断点，什么问题使用 Trace，什么问题必须通过录制回放或 Core Dump 分析。

### 第三阶段：Runtime 与完整请求链

沿下面的顺序找到对应文件：

```text
main.lua
  -> watchdog.lua
  -> auth.lua
  -> player_mgr.lua
  -> player_agent.lua
  -> scene_mgr.lua
  -> scene.lua
```

同时进入 Skynet Runtime 源码，理解 Global Queue、Service Message Queue、Worker Thread、Service Handle、Session 和 Coroutine Response。学习 `skynet.start`、`newservice`、`dispatch`、`call`、`send`、`timeout` 和 `queue`，但重点不是背 API，而是还原一次请求的调度与恢复路径。

这一阶段配合阅读 `docs/01_ARCHITECTURE.md`、`docs/03_SKYNET_CORE_API.md`、`docs/04_LOGIN_FLOW.md` 和 `docs/06_COROUTINE_AND_CONCURRENCY.md`。

### 第四阶段：状态所有权与并发正确性

跟踪登录、重复登录、断线、60 秒重连窗口和退出保存，理解 `fd + connection_id` 为什么要一起校验，以及 PlayerAgent 为什么按玩家串行处理业务请求。

继续审查 Scene 为什么拥有实时坐标、AOI 和怪物 HP，PlayerAgent 为什么只保存持久化快照。所有 Service 修改都要列出状态所有者、yield 点、恢复后的陈旧状态、`call`/`send` 选择、Hot Actor 风险和 Generation Check。

这一阶段阅读 `docs/05_SCENE_AOI_COMBAT.md` 和 `docs/15_P0_AUTHORITATIVE_MOVEMENT.md`。

### 第五阶段：生产工程与性能

建设结构化日志、Trace Context、Service 状态快照、消息队列和 RPC 延迟指标、网络/业务事件录制回放、故障注入与自动化机器人。学习 memory/MySQL Worker 分片、最终保存、integration smoke test 和 AOI Benchmark，并从观测数据而不是 Lua 性能假设出发优化。

最后结合 `docs/13_PRODUCTION_GAPS.md` 做一次投产评审，明确单节点容量、故障域、重启恢复、灰度兼容和仍未闭合的风险。

## 始终牢记的三条规则

1. Service 是状态所有者，不只是一个 Lua 文件。PlayerAgent 拥有持久玩家状态；Scene 拥有实时空间状态。
2. `skynet.call` 看似同步，实际会让当前 Coroutine yield。恢复后必须重新判断旧状态是否仍然有效。
3. 一个 hot Service 仍是单 Actor 瓶颈。增加 `thread` 不会让同一个 Scene 的 Lua 同时使用多个 CPU core；扩展依赖场景分线、分片或 Actor 拆分。

## 其他文档什么时候看

- Windows/Ubuntu 安装失败：`docs/09_WINDOWS_WSL2.md`
- Linux 主机部署：`docs/10_LINUX.md`
- 逐行调试或 GDB：`docs/16_DEBUGGING.md`
- MySQL 存储：`docs/07_STORAGE.md`
- 测试和 benchmark：`docs/08_TESTING_AND_BENCHMARK.md`
- 已知生产差距：`docs/13_PRODUCTION_GAPS.md`

正常入门不需要按编号阅读所有文档；本文会在对应阶段告诉你下一份应该看什么。
