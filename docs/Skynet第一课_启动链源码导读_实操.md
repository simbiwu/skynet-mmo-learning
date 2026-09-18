# Skynet 第一课配套实操：从构建产物走到业务 Bootstrap

这份实操以仓库当前 Skynet v1.8.0 为基线。最终交付是一组可重复的证据：主程序、C Service 和 Lua C Module 在磁盘上的对应关系；从 `main` 到 `service/main.lua` 的调用顺序；配置 Lua State 与 snlua Lua State 的生命周期；三类启动失败分别停在哪一层。只保留“命令已执行”的清单无法通过验收。

所有命令默认在 WSL2/Linux 的仓库根目录执行。Windows PowerShell 只用于进入 WSL；Skynet 不切换到非官方 Windows fork。行号对应当前工作树，后续代码变动时应以完整仓库路径和函数名为主。

## 1. 建立可重复工作台

```powershell
wsl
```

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
git status --short
git rev-parse --short HEAD
uname -a
cc --version | head -n 1
gdb --version | head -n 1
```

保留 Commit、WSL 发行版、CPU 和编译器信息，后续的栈与性能数据才有复现条件。不要在有未跟踪课程稿的工作树执行 `git clean`。

如果 `third_party/skynet/skynet` 不存在：

```bash
make bootstrap
make build
```

`Makefile:2-5` 分别进入 `scripts/bootstrap_skynet.sh` 和 `scripts/linux/build.sh`。先跑基线：

```bash
./scripts/linux/test.sh
```

尾部应出现 `UNIT_TESTS_OK`、`INTEGRATION_SMOKE_OK` 和 `ALL_TESTS_OK`。如果基线已经失败，保留完整输出，不要在未知基线上继续故障注入。

## 2. 把三类产物对到加载器

```bash
file third_party/skynet/skynet
file third_party/skynet/cservice/snlua.so
file third_party/skynet/luaclib/skynet.so
ldd third_party/skynet/skynet
ldd third_party/skynet/cservice/snlua.so
```

| 磁盘文件 | 运行时角色 | 搜索路径 |
|---|---|---|
| `third_party/skynet/skynet` | ELF 主程序，入口是 `skynet_main.c::main` | 由 Shell 直接执行 |
| `third_party/skynet/cservice/snlua.so` | Runtime 动态加载的 C Service Module | `config/game.lua:11` 的 `cpath` |
| `third_party/skynet/luaclib/skynet.so` | Lua `require` 加载的 C Module | `config/game.lua:10` 的 `lua_cpath` |

`bootstrap = "snlua bootstrap"` 的第一个词会按 `cpath` 查找 C Service；后一个词是传给 snlua 的参数，由 `third_party/skynet/lualib/loader.lua:1-24` 解析成 Service Name 并按 `luaservice` 查找 `bootstrap.lua`。`cpath`、`lua_cpath` 和 `luaservice` 不是一套搜索路径。

## 3. GDB 跟踪配置 Lua State

```bash
gdb --args ./third_party/skynet/skynet config/game.lua
```

```gdb
set pagination off
set breakpoint pending on
break main
run
print argc
print argv[1]
break third_party/skynet/skynet-src/skynet_main.c:140
break third_party/skynet/skynet-src/skynet_main.c:153
break third_party/skynet/skynet-src/skynet_main.c:154
break skynet_start
continue
```

`third_party/skynet/skynet-src/skynet_main.c:117-126` 读命令行配置名。`:140` 的 `luaL_newstate` 创建临时配置 State；`skynet_main.c:86-115` 内嵌的 `load_config` 读文件；`:143-153` 执行并写入 Runtime Environment；`:154` 立即 `lua_close(L)`。这个 State 不是任何 PlayerAgent/Scene 的 VM，其中的普通 Lua table 不能在 State 销毁后供业务 Service 共享。

在 `skynet_start` 停下时：

```gdb
print config->thread
print config->module_path
print config->bootstrap
print config->harbor
```

将实际值与 `config/game.lua:11-16` 对照。`third_party/skynet/skynet-src/skynet_start.c:271-289` 初始化 Handle/MQ/Module/Timer/Socket，创建 logger 和 bootstrap，然后启动线程。`skynet_start.c:214-228` 创建 Worker；`thread=8` 不包含 Monitor、Timer、Socket 线程，也不表示一个 Service 可被 8 个 Worker 同时执行。

## 4. Runtime 创建 logger 和 snlua bootstrap

重新启动 GDB：

```gdb
set pagination off
set breakpoint pending on
break skynet_context_new
run
print name
print param
continue
```

前两类关键命中应是 `name="logger"` 和 `name="snlua", param="bootstrap"`，来自 `third_party/skynet/skynet-src/skynet_start.c:279-287`。`bootstrap()` 在 `skynet_start.c:233-255` 拆分字符串，调用 `skynet_context_new(name, args)`。该断点会命中所有 Service 创建；捕获证据后可用 `disable <breakpoint-number>` 停掉。

`snlua_init` 所在的 `snlua.so` 是动态加载的：

```gdb
set breakpoint pending on
break snlua_init
run
bt
continue
```

`third_party/skynet/service-src/service_snlua.c:502-511` 的 `snlua_create` 为每个 snlua 实例调用 `lua_newstate`；`service_snlua.c:514-518` 在实例释放时关闭它。这与 `skynet_main.c:140` 的临时配置 State 不是同一个对象。

后续顺序应画成：

```text
snlua Lua State
  -> third_party/skynet/lualib/loader.lua:1-24 按 LUA_SERVICE 找文件
  -> third_party/skynet/lualib/loader.lua:27-50 设 package path 并执行 chunk
  -> third_party/skynet/service/bootstrap.lua:4-50
  -> .launcher / .cslave / DATACENTER / service_mgr
  -> skynet.getenv("start") == "main"
  -> skynet.newservice("main")
  -> service/main.lua:17-61
```

`third_party/skynet/service/bootstrap.lua:50-51` 创建业务 Main 后退出官方 Bootstrap Service。`service/main.lua:20-60` 按 Protocol→Config→Storage→Scene→Player→Auth/Watchdog/Gate 的顺序启动，`:61` 退出业务 Main。已创建 Service 拥有独立 Context/Handle/Mailbox，两个 bootstrap 退出都不会让整个进程退出。

## 5. Debug Console 核对 Service 拓扑

Terminal A：

```bash
./scripts/linux/run_server.sh
```

Terminal B 在 `[Main] startup complete` 后执行：

```bash
./scripts/linux/debug_console.sh
```

```text
help
list
stat
mem
```

`service/main.lua:53-56` 只在 `debug_console_port > 0` 时创建 Debug Console，开发端口在 `config/game.lua:24`。`list` 通过 `third_party/skynet/service/debug_console.lua:234-235` 查 `.launcher`，`stat` 在 `debug_console.lua:250-251` 获取统计。记录 SceneMgr、Scene、PlayerMgr、StorageMgr 和 StorageWorker 的 Address。尚无玩家登录时不应看到动态 PlayerAgent。

Debug Console 可以查状态、执行调试命令甚至终止 Service，不能暴露到公网，生产环境需要网络隔离、身份验证、审计和只读能力约束。

### 登录前后各抓一次拓扑

服务器启动完成但尚无客户端时，在 Debug Console 保存下面几项输出：

```text
list
service
stat
mem
netstat
```

`list` 展示 `.launcher` 记录的 Service 实例；`service` 展示通过 `uniqueservice` 建立的命名 Service。两份列表用途不同，不能用其中一份推断所有运行实例。此时业务 `main` 通常已经退出，Scene、StorageWorker、Gate 等 Service 仍在。

在另一个 Terminal 登录玩家：

```bash
# 当前目录：仓库根目录
./scripts/linux/run_client.sh --player=10001
```

再执行 `list` 和 `stat`。新增的 `player/player_agent` 来自 `service/player/player_mgr.lua::CMD.login`。记录它的 Address，然后执行：

```text
info :<agent_address>
task :<agent_address>
info :<scene_address>
task :<scene_address>
call :<scene_address> "stats"
```

`call :<scene_address> "stats"` 本身就是一次同步 Service RPC。Debug Console 发出带 session 的 Lua Request；`service/scene/scene.lua` 的 dispatcher 调用 `CMD.stats`；`skynet.retpack` 发回 Response；Console 中等待的 coroutine 恢复并打印结果。借这条命令可以在进入第二课前先观察一次完整 Request/Response。

玩家输入 `logout` 后，TCP Connection 会关闭，但 `service/player/player_agent.lua::CMD.client_closed` 设置了 60 秒重连窗口。立刻执行 `list` 时 Agent 仍可能存在；到期后 Timer coroutine 调用 `offline`，依次离开 Scene、保存玩家、从 PlayerMgr 删除映射并退出。这里能直接看到 Connection 生命周期、PlayerAgent 生命周期和 Process 生命周期并不相同。

### 把 Process、Thread、Service、Lua State 和 coroutine 分开记录

每次停在断点或查看 Console 时，按下面格式记录现场：

| 层次 | 第一课中的对象 | 如何确认 |
|---|---|---|
| Process | `third_party/skynet/skynet` | `ps -T -p <pid>`、GDB `info inferiors` |
| Thread | Main、Monitor、Timer、Socket、8 个 Worker | GDB `info threads` |
| Service | logger、bootstrap、Scene、PlayerAgent | Debug Console `list` |
| Lua State | 每个 snlua Service 私有的 `lua_State` | `service_snlua.c::snlua_create`、LuaPanda Variables |
| coroutine | 一次消息 Handler、Timer callback、等待中的 call | Debug Console `task :Address` |

在 GDB 中可以执行：

```gdb
info threads
thread apply all bt 3
```

只需要识别线程角色，不要在第一遍阅读时深挖每个系统调用。Worker 的入口可对到 `third_party/skynet/skynet-src/skynet_start.c::thread_worker`；Timer 与 Socket 分别有自己的线程入口。某个 Worker 当前出现在 Scene 的调用栈里，也不代表这个 Worker 永久属于该 Scene。

## 6. 把 `service/main.lua` 的启动顺序逐行跑一遍

在 `service/main.lua::skynet.start` 内按以下位置设置 LuaPanda 断点并不合适，因为普通开发配置不会加载 LuaPanda，而调试配置的目标 Service 默认是 Scene 或 PlayerAgent。第一课观察业务 Bootstrap，优先用日志、GDB 的 `skynet_context_new` 和 Debug Console `list`；如果确实要用 LuaPanda，复制 `.vscode/launch.json` 配置，把目标改成 `main`，并确认 8818 没有被其它调试会话占用。

`service/main.lua` 的实际启动顺序如下：

| 顺序 | 完整仓库路径与调用 | 当前 coroutine 是否可能 yield | 返回后得到什么 |
|---|---|---|---|
| 1 | `service/main.lua::skynet.uniqueservice("protocol/protoloader")` | 会，需等 `.launcher` 完成创建 | ProtocolLoader Address |
| 2 | `service/main.lua::skynet.uniqueservice("config/config_service")` | 会 | ConfigService Address |
| 3 | `skynet.uniqueservice("storage/storage_mgr")` + `call start` | 两处都会 | StorageMgr 与已启动 Worker Pool |
| 4 | `skynet.uniqueservice("scene/scene_mgr")` + `call start` | 两处都会 | SceneMgr 与默认 Scene 1 |
| 5 | `skynet.uniqueservice("player/player_mgr")` + `call init` | 两处都会 | 持有 Storage/Scene 依赖的 PlayerMgr |
| 6 | 创建 Auth、Watchdog，`call Watchdog.start` | 会 | Gate 已创建并监听端口 |
| 7 | `newservice("debug_console")` | 会 | 开发调试端口 |
| 8 | `skynet.exit()` | 当前 main Service 退出 | 其它 Service 继续运行 |

沿这张表检查两个问题。第一，Gate 必须在 Storage、Scene、PlayerMgr 和 Auth 可用后才开放，否则进程虽然存在，客户端却可能进入未完成初始化的业务图。第二，`main` 只负责组织依赖，不持有 Player、Scene 或 Storage 状态；它退出后不会留下一个所有请求都要经过的中央 Actor。

在 `skynet_context_new` 断点中连续观察 Service 创建时，可以按下面的时间线整理，不要求 Address 固定：

```text
logger
  -> snlua bootstrap
  -> snlua launcher
  -> 官方系统 Service
  -> snlua main
  -> protocol/protoloader
  -> config/config_service
  -> storage/storage_mgr
  -> storage/memory_worker × 4
  -> scene/scene_mgr
  -> scene/scene
  -> player/player_mgr
  -> auth/auth
  -> gateway/watchdog
  -> gate
  -> debug_console
  -> main exit
```

精确顺序以当前运行输出为准，系统 Service 会随上游配置出现差异。验收重点是解释由谁创建、创建是否需要等待、状态最终归谁。

## 7. 三层启动失败注入

每次先停正常服务器，只新建临时配置，不覆盖 `config/game.lua`。

### 配置语法错误

`config/lesson1_bad_syntax.lua`：

```lua
thread =
```

```bash
./third_party/skynet/skynet config/lesson1_bad_syntax.lua
```

失败在 `third_party/skynet/skynet-src/skynet_main.c:143-151`：临时配置 State 执行失败，`skynet_start` 尚未调用，logger/snlua 也未创建。

### Lua Service Loader 找不到 bootstrap

`config/lesson1_bad_loader.lua`：

```lua
include "game.lua"
luaservice = "./not_exists/?.lua"
```

```bash
./third_party/skynet/skynet config/lesson1_bad_loader.lua
```

C Runtime 已初始化，`snlua.so` 也能被加载；失败在 `third_party/skynet/lualib/loader.lua:10-25` 遍历 `LUA_SERVICE` 找不到 `bootstrap.lua`。

### 官方 Bootstrap 找不到业务 Main

`config/lesson1_bad_start.lua`：

```lua
include "game.lua"
start = "lesson/missing_main"
```

```bash
./third_party/skynet/skynet config/lesson1_bad_start.lua
```

官方 `bootstrap.lua` 已创建 `.launcher`等系统 Service，失败在 `third_party/skynet/service/bootstrap.lua:50` 读 `start` 并创建业务 Service 时。若要再区分顶层 `require` 与 `skynet.start` 内初始化错误，可在专用分支建最小 Service：顶层错误由 `loader.lua:50` 暴露；初始化 callback 错误经 `third_party/skynet/lualib/skynet.lua:1062-1082` 通知 `.launcher`。

## 8. 启动故障的分层判断

做完三次故障注入后，不看文档，根据第一条失败日志填写：

| 故障层 | 这一层之前已成功什么 | 第一个应检查的文件/函数 |
|---|---|---|
| 配置解析 | Process 进入 C `main` | `third_party/skynet/skynet-src/skynet_main.c::main`、目标配置文件 |
| C Service Module | 配置已写入 Environment | `config/game.lua` 的 `cpath`、`third_party/skynet/skynet-src/skynet_module.c` |
| Lua Service Loader | `snlua.so` 已加载并创建 Lua State | `third_party/skynet/lualib/loader.lua`、`luaservice` |
| Service 顶层 Chunk | Loader 已找到目标文件 | 目标 Service 顶层 `require` 和函数定义 |
| `skynet.start` 初始化 | 顶层 Chunk 已执行 | 目标 Service 的初始化 callback、下游 `call` |
| 业务监听 | 系统与部分业务 Service 已存在 | `service/main.lua`、`service/gateway/watchdog.lua::CMD.start` |

例如“8888 没监听”不应直接归到 Socket Thread。先用日志确认 `service/main.lua` 是否走到 Watchdog，再用 `list` 看 Watchdog/Gate 是否创建，用 `netstat` 看端口状态。只有业务调用链已完成仍无监听时，才继续向 Gate 和 Socket 层下钻。

## 9. 清理与验收

先用 `git status --short` 确认目标，再删除三个临时配置：

```bash
git status --short
rm config/lesson1_bad_syntax.lua
rm config/lesson1_bad_loader.lua
rm config/lesson1_bad_start.lua
./scripts/linux/test.sh
```

验收时应交付：

1. 从启动命令到 `service/main.lua` 的时序图，每个箭头标出 C 调用、Service 创建或 Lua Loader 执行。
2. GDB 中 `argv[1]`、`config->thread`、`config->bootstrap` 和 `skynet_context_new("snlua", "bootstrap")` 的实际值。
3. 配置 Lua State、Bootstrap State、Scene State 和 PlayerAgent State 的创建/销毁关系。
4. 三份故障日志，标出已成功的上游层次与第一个失败函数。
5. Debug Console `list/stat/mem` 输出，能用 Address 找到 Scene 与 Manager，并说明 Address 为什么不能持久化。
6. 复测 `ALL_TESTS_OK`，工作树没有遗留故障注入配置。

验收说明需要落到当时的 Process、Thread、Service、Lua State 和 coroutine，不只说“Skynet 先 bootstrap”。

## 第一课自测题参考答案（扩展版）

第一课 PDF 已附回答要点。下面把答案补到源码和运行现场，方便只阅读 Markdown 时复习。

### 题 1：为什么 `config/game.lua` 中的 Lua table 不能直接给所有 PlayerAgent 共享？

`third_party/skynet/skynet-src/skynet_main.c::main` 调用 `luaL_newstate` 创建配置专用 Lua State，执行配置并由 `_init_env` 把标量结果写入 Skynet Environment，随后立即 `lua_close(L)`。PlayerAgent 尚未创建时，这个 Lua State 已经销毁。

每个 PlayerAgent 以后由 `snlua_create` 创建自己的 `lua_State`。不同 Lua State 的 table、userdata、全局变量和 `package.loaded` 互不共享。配置标量通过 `skynet.getenv` 读取；需要多 Lua State 共享的大型只读配置，当前工程由 `service/config/config_service.lua` 发布到 `sharedata`，不能依赖配置文件里的普通 table 引用。

### 题 2：`bootstrap = "snlua bootstrap"` 中两个词分别是什么？

`snlua` 是 C Service Module 名称。`third_party/skynet/skynet-src/skynet_start.c::bootstrap` 把字符串拆成 Module 名和参数，再调用 `skynet_context_new("snlua", "bootstrap")`。Runtime 按 `config/game.lua` 的 `cpath` 加载 `third_party/skynet/cservice/snlua.so`。

后一个 `bootstrap` 是传给 snlua 的 Service 参数。snlua 创建 Lua State 并运行 `third_party/skynet/lualib/loader.lua`；Loader 把参数作为 `SERVICE_NAME`，按 `luaservice` 找到 `third_party/skynet/service/bootstrap.lua`。两个词分别处在 C Service 加载层和 Lua Service 加载层。

### 题 3：为什么把 `thread` 改成 32 不一定能解决单 Scene CPU 满？

`thread` 增加 Worker Pool 的执行资源，让不同 Service 可以并行。单个 Scene 的 Context、Mailbox 和 Lua State 仍由一个 Actor 顺序提交，Runtime 不会把同一个 `CMD.move` 的权威状态拆给多个 Worker 同时修改。

如果 `stat` 显示某个 Scene `mqlen` 持续增长，而其它 Worker 仍有余量，问题位于单 Actor 处理能力。应先检查 Handler CPU、Candidate/Visible/Push、GC 和下游 call，再评估分线、实例化或 Region Partition。只有多个可运行 Service 都缺 Worker 时，增加 Worker 才可能直接改善吞吐。

### 题 4：`skynet.newservice("scene/scene")` 与 C++ `new Scene()` 有哪些实质差别？

`newservice` 经过 `.launcher` 创建新的 Runtime Context、Handle、Mailbox 和 snlua Lua State，并加载 `service/scene/scene.lua`。调用过程可能 yield，返回值是 Service Address。后续交互使用 `skynet.call/send`，参数要经过消息协议，调用方拿不到 Scene 内部 table 引用。

C++ `new Scene()` 通常只在当前地址空间分配对象并返回指针；构造过程若没有显式异步机制，不会自动建立 Actor Mailbox、session、独立 Lua State和生命周期握手。两者在内存成本、失败处理、调度和调用语义上都不同。

### 题 5：为什么 `service/main.lua` 调用 `skynet.exit()` 后服务器仍运行？

`skynet.exit()` 结束当前 main Service，不结束 Skynet Process。main 此前已经创建 ProtocolLoader、ConfigService、StorageMgr/Worker、SceneMgr/Scene、PlayerMgr、Auth、Watchdog、Gate 和 Debug Console。它们各自有 Context、Handle、Mailbox；main 退出不会递归销毁这些 Service。

现场可用 Debug Console `list` 验证：启动日志出现 `[Main] startup complete` 后，main 已退出，Scene、Gate 等仍在并继续处理客户端。若要退出整个进程，需要让所有关键 Service 按停服流程结束，或由外部进程管理发送终止信号。

### 题 6：没有传统多线程 Data Race，为什么仍会出现旧值覆盖新值？

Runtime 不会让两个 Worker 同时执行同一个 Lua State，但消息 Handler 可在 `skynet.call`、`skynet.sleep`、`skynet.wait` 等位置 yield。等待期间，同一 Service 的另一条消息 coroutine 可以运行并修改共享 local table。

原 coroutine 恢复后，yield 前保存的局部值可能已经过期。如果它仍按旧值写回，就形成 Lost Update。第二课 `service/lesson/reentrancy_lab.lua` 实验会稳定复现：A 读 0 后 sleep，B 写 100，A 恢复后写 1。修复方式取决于不变量，可以用 `skynet.queue` 串行关键段，也可以在恢复后重新读取并校验 version/generation。

实操结束后再独立回答六题，答案应带现场证据：配置 State 用 GDB 的 `lua_close` 证明；单 Scene Hot Actor 用 Worker/Service 映射证明；main 退出而进程继续用 Debug Console 的 Service 列表证明。
