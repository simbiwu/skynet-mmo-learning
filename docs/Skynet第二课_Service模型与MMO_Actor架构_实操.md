# Skynet 第二课配套实操：跟踪 Service RPC、Coroutine 重入与状态所有权

这份实操从一次真实登录和 Move 请求开始，不另造 Actor 框架。完成后要能现场证明：Service Address 如何对应运行实例，`call` 为何只挂起当前 coroutine，`send` 为何没有业务返回值，PlayerAgent 与 Scene 各自拥有什么状态，yield 后哪些引用需要重新校验。

命令默认在 WSL2/Linux 的仓库根目录执行。课程实验所有代码改动都应在专用分支完成，实验后使用明确的文件恢复，不使用 `git reset --hard` 或 `git clean`。

## 1. 运行基线与三端工作台

Terminal A：

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
./scripts/linux/test.sh
./scripts/linux/run_server.sh
```

Terminal B：

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
./scripts/linux/debug_console.sh
```

Terminal C：

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
./scripts/linux/run_client.sh --player=10001
```

客户端登录后先输入 `ping`，再在 Debug Console 执行 `list`、`stat`、`mem`。对比登录前后 Service 列表，新出现的 snlua 实例是 PlayerAgent；`service/player/player_mgr.lua:35-48` 创建并记录它。记下 PlayerAgent 和 Scene Address，随后使用：

```text
stat
task :<agent_handle>
task :<scene_handle>
info :<scene_handle>
call :<scene_handle> stats
```

Handle 使用 `list` 的实际输出，不抄文档中的示例值。`service/scene/scene.lua:312-327` 的 `CMD.stats` 返回 Scene ID、tick、players、entities 和 cells。

## 2. 沿登录路径逐个审查 yield

从 Gate 将首包交给 Watchdog 开始，按代码执行顺序记录：

| 顺序 | 当前 Service / coroutine | 代码 | 是否 yield | 恢复后的检查 |
|---|---|---|---|---|
| 1 | Watchdog socket coroutine | `service/gateway/watchdog.lua:74-91` | `host:dispatch` 不跨 Service | 首次 yield 前先把 Connection 改为 `AUTHING` |
| 2 | Watchdog | `service/gateway/watchdog.lua:93-104` | `call auth_service` | `alive(fd, c)` 确认 fd 仍指向同一 Connection table |
| 3 | Watchdog | `service/gateway/watchdog.lua:106-120` | `call player_mgr` | 再次 `alive`；断线且新建 Agent 时发 `abort_if_unbound` |
| 4 | PlayerMgr | `service/player/player_mgr.lua:27-49` | `newservice` 和 `call load` | 整段由 player-id 分片 queue 串行 |
| 5 | PlayerAgent | `service/player/player_agent.lua:49-60` | `call storage_mgr` | Response 成功后才赋值 `player` |
| 6 | Watchdog | `service/gateway/watchdog.lua:123-130` | `call bind_client` | 再次 `alive` |
| 7 | Watchdog/Agent/SceneMgr | `watchdog.lua:132-143` 及 `player_agent.lua:79-99` | enter 链上多次 call | Watchdog 校验 Connection；Agent 只在 Scene 成功后缓存 Address |
| 8 | Watchdog | `service/gateway/watchdog.lua:145-168` | `call gate.forward` | 当前代码返回后未再 `alive`，需在 Review 中标为时序风险 |

第 8 步不要被“这是 Gate 操作”迷惑：`skynet.call` 仍会 yield。断线消息可在等待期间删除 `connections[fd]`，恢复后的 `c` 可已过期。本实操只记录并设计回归时序，不用宽泛 `pcall` 隐藏问题。

## 3. 把一次 Move 的 Request/Response 与状态 Owner 对齐

在客户端输入：

```text
move 101 100
```

执行链是：

```text
client/test_client.lua:72-75
  Sproto Request + session，再由 :38-40 加 2-byte big-endian frame
    -> Gate 按 forward 结果转发 PTYPE_CLIENT
    -> service/player/player_agent.lua:249-280 解包
    -> service/player/player_agent.lua:182-190 进入 serial
    -> service/player/player_agent.lua:132-142 call Scene，当前 coroutine yield
    -> service/scene/scene.lua:183-204 无 yield 提交实时位置/Grid/Visible
    -> service/scene/scene.lua:206-247 send AOI Push
    -> service/scene/scene.lua:249 返回
    -> service/scene/scene.lua:330-336 retpack
    -> PlayerAgent coroutine resume
    -> service/player/player_agent.lua:143-147 更新持久快照
    -> player_agent.lua:277-279 编码 Client Response
```

在 Review 表中明确：Scene 拥有实时 x/y、`move_state`、Grid 和 Visible Set；PlayerAgent 拥有玩家持久状态和连接绑定，其 x/y 是 Scene 成功后的 Snapshot。`service/player/player_agent.lua:142` 之前读到的 `scene_service` 和 `player` 属于跨 yield 引用；当前通过 `serial` 保证同玩家客户端业务不交错，但系统命令和 Timer 仍需按自身 generation 校验。

### 沿 `skynet.call` 进入 Runtime

业务断点确认调用参数后，继续阅读 `third_party/skynet/lualib/skynet.lua`：

```text
third_party/skynet/lualib/skynet.lua::skynet.call
  -> proto["lua"].pack(command, ...)
  -> auxsend 发送带非零 session 的 Request
  -> yield_call(target, session)
       -> watching_session[session] = target
       -> session_id_coroutine[session] = running_thread
       -> coroutine_yield("SUSPEND")
```

Request 进入 C Runtime 后，`third_party/skynet/skynet-src/skynet_server.c::skynet_context_push` 找到目标 Context，`third_party/skynet/skynet-src/skynet_mq.c::skynet_mq_push` 把消息放入 Scene 私有 Mailbox。空队列第一次变成可运行状态时进入 Global Queue。Worker 在 `third_party/skynet/skynet-src/skynet_start.c::thread_worker` 中调用 `skynet_context_message_dispatch` 取 Mailbox 并执行 Service callback。

Scene 的 Lua callback 最终进入 `third_party/skynet/lualib/skynet.lua::raw_dispatch_message`。普通 Request 会创建一条消息 coroutine，记录 `session/source`，再调用 Scene 注册的 dispatcher。`CMD.move` 返回后，`skynet.retpack` 把结果发给 `source` 并保留原 session。Response 回到 PlayerAgent 时，`raw_dispatch_message` 走 `PTYPE_RESPONSE` 分支，从 `session_id_coroutine[session]` 找到原 coroutine 并 resume。

| 对象 | 作用 | 生命周期 |
|---|---|---|
| Service Address | 找到目标 Context | 当前 Service 实例存活期间 |
| Mailbox | 保存发给该 Service 的消息 | 跟随 Context |
| session | 关联一次 `call` 的 Request/Response | RPC 完成或失败前 |
| coroutine | 保存调用方 Lua 执行现场 | Handler 完成或异常退出前 |

调用方无法通过 Address 直接访问 Scene 的 `entities`。Address 参与 Runtime 路由，跨 Service 数据要经过消息打包、投递和解包。

## 4. 在 LuaPanda 中分两遍看 Move

按 `.vscode/launch.json:5-20` 选“Skynet Lua：LuaPanda 调试 Scene”，只会为显式选中的 `scene/scene` 启用 LuaPanda。断点放在：

- `service/scene/scene.lua:183`：记录 coroutine、`player_id/x/y`。
- `service/scene/scene.lua:195`：看 Token Bucket 校验前后。
- `service/scene/scene.lua:200-204`：核对 old/new Visible 与提交顺序。
- `service/scene/scene.lua:249`：确认 Response 内容。

停服后再选 `.vscode/launch.json:23-38` 的 PlayerAgent 配置，断在 `service/player/player_agent.lua:132`、`:142`、`:146`。不要一次启动两个调试配置争用 8818 端口。断点会改变调度时序，适合个人环境理解路径，不能当作并发竞态的唯一证据。

PlayerAgent 这一遍在 `skynet.call` 前记录 `player.x/y`、`scene_service` 和请求参数；Step Over 后记录 `ok/rx/ry`。Scene 这一遍在 `CMD.move` 中记录 `player.move_state`、`old_visible`、Grid Cell 和提交后的 `new_visible`。两次调试结果合并后应得到：

```text
客户端 x/y             非权威输入
PlayerAgent player.x/y  最近一次 Scene 成功提交后的持久化快照
Scene player.x/y        在线实时权威坐标
Scene move_state        移动额度 Owner
Scene grid/visible      AOI Owner
```

不要比较两个 LuaPanda Session 里 Lua table 的内存地址。PlayerAgent 与 Scene 属于不同 Lua State，能对齐的是业务字段、Service Address、session 和执行顺序。

### 两个客户端观察 `send` 的旁路 Push

启动 Player 10001 与 10002：

```bash
# Terminal C，当前目录：仓库根目录
./scripts/linux/run_client.sh --player=10001
```

```bash
# Terminal D，当前目录：仓库根目录
./scripts/linux/run_client.sh --player=10002
```

`service/storage/memory_worker.lua::CMD.start` 中两名玩家的出生点是 `(100,100)` 和 `(108,100)`，距离小于 `lualib/config/game_data.lua` 配置的 18 单位视距。在 10001 客户端输入：

```text
move 101 100
```

Scene 的 `push_player` 用 `skynet.send` 通知 10002 的 Agent。当前学习客户端只在等待某个 RPC Response 时读取 Socket；如果 10002 终端暂时没有输出，再输入 `ping`。`client/test_client.lua::wait_response` 会先打印已排队的 `entity_move` Push，再打印 ping Response。由此可以区分 `send` 返回、Agent 处理、数据进入 Socket send queue 和客户端消费四个阶段。

## 5. 实验 `call` 和 `send`

在专用分支的 `service/player/player_agent.lua` 的 `CMD` 区域增加只读命令：

```lua
-- 仓库路径：service/player/player_agent.lua
function CMD.get_gold()
    return player.gold
end
```

从一个临时测试 Service 执行：

```lua
local gold = skynet.call(agent, "lua", "get_gold")
skynet.error("call gold=", gold)
local send_result = skynet.send(agent, "lua", "get_gold")
skynet.error("send result=", tostring(send_result))
```

`third_party/skynet/lualib/skynet.lua:725-737` 的 `call` 创建非零 session，经 `:714-722` 挂起当前 coroutine，Agent 的 `service/player/player_agent.lua:287-292` 在 session 非 0 时 `retpack`。`third_party/skynet/lualib/skynet.lua:692-695` 的 `send` 用 session 0，调用方拿到的只是投递结果，不是 gold。Agent dispatch 因 session 0 不回复，所以只读 Handler 虽会执行，返回值无处传递。

为了让实验可重复，临时测试 Service 建议放在 `service/lesson/rpc_probe.lua`，不要把测试入口长期塞进 PlayerMgr。它接收 Agent Address，依次执行 `call` 和 `send`，日志同时打印自身 Address、目标 Address 和返回值。Address 必须取自本次 `list` 输出，不能写死；进程重启后，同一玩家的 Agent Handle 可能变化。

实验结束后需要回答：`send` 的 Lua 返回值最多说明什么？目标 Handler 报错时发送方能否同步得知？如果业务要求确认、重试和去重，应在哪一层补 Ack、Operation ID 和结果记录？

## 6. 确定性复现 Lost Update

在专用测试 Service 中建立 `test_value=0`，A 读值后 `skynet.sleep(100)`，B 在 A 睡眠期间加 100：

```lua
local test_value = 0

function CMD.test_a()
    local old = test_value
    skynet.sleep(100)
    test_value = old + 1
    return test_value
end

function CMD.test_b()
    test_value = test_value + 100
    return test_value
end
```

用另一 Service `skynet.fork` 发 A，等 10 tick 后 call B，再等 A 恢复。预期中间值 100，最终值却是 1。这证明同一 Service 虽没有两个 Worker 同时写 table，coroutine A 在 yield 前读到的 `old` 仍会过期。

然后用同一 `local serial = require("skynet.queue")()` 包住 A/B 的读改写整段，预期最终 101。`third_party/skynet/lualib/skynet/queue.lua:24-34` 让等待者 `skynet.wait()`，不占用 Worker Thread；`:12-19` 在持有者退出后唤醒下一个 coroutine。

### 可直接操作的双 Console 版本

新建 `service/lesson/reentrancy_lab.lua`：

```lua
-- 仓库路径：service/lesson/reentrancy_lab.lua
local skynet = require "skynet"

local CMD = {}
local value = 0

function CMD.reset()
    value = 0
    return value
end

function CMD.get()
    return value
end

function CMD.slow_add(delta)
    local old = value
    skynet.sleep(200) -- 2 秒；只挂起当前消息 coroutine
    value = old + delta
    return value
end

function CMD.fast_add(delta)
    value = value + delta
    return value
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command], "unknown command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
```

Debug Console 1：

```text
start lesson/reentrancy_lab
call :<lab_address> "reset"
call :<lab_address> "slow_add", 1
```

`slow_add` 尚未返回的两秒内，在 Debug Console 2 执行：

```text
call :<lab_address> "fast_add", 100
```

两边返回后执行 `call :<lab_address> "get"`，不安全版本的最终值应为 1。修复时增加：

```lua
-- 仓库路径：service/lesson/reentrancy_lab.lua
local queue = require "skynet.queue"
local serial = queue()
```

再把两个更新函数各自完整包进 `serial(function() ... end)`。用 `exit :<lab_address>` 退出旧实例，重新 `start lesson/reentrancy_lab` 后重复实验，最终值应为 101。必须新建 Service，因为运行中的 Lua State 不会随磁盘文件自动重载。

实验报告要写出两条 coroutine 的时间线、A 的 yield 点、B 修改的 Owner 状态、A 恢复时已经失效的 `old`，以及 queue 保护的不变量。只记录两个最终数字还不足以解释原因。

## 7. 检验 PlayerMgr 和 SceneMgr 的唯一性保护

PlayerMgr 的竞态窗口不在 table lookup 这条指令内，而在 `service/player/player_mgr.lua:30-47` 的“检查 nil→`newservice`→`call load`→填表”之间。`newservice` 和 `call` 都可 yield。`player_mgr.lua:13-18` 创建 64 路分片 queue，`:29-49` 使同 player_id 的登录串行。

测试时用两个客户端同时登录 10001，在 `player_mgr.lua:35` 和 `:47` 断点/结构化日志中记录 Agent Address。正常结果是只有一个 Agent，后到连接在 `service/player/player_agent.lua:63-76` 复用 Agent 并踢旧 Connection。若为了观察错误而临时去掉 queue，必须配合人工 delay 扩大窗口，并在实验后恢复文件。

SceneMgr 在 `service/scene/scene_mgr.lua:10-23` 用一把创建 queue。锁外第一次检查是快速路径，`:16-18` 的第二次检查处理“排队期间前一个 coroutine 已创建成功”的情况。检验时应同时说出为什么当前全局一把创建锁在 Scene 数很大时可进一步分片，但不需要让每次 Move 都经 SceneMgr。

### 固定的 Service Review 表

以后修改 Service，先按仓库门禁填写。PlayerAgent Move 的示例如下：

| Review 项 | 当前路径的答案 |
|---|---|
| State Owner | Scene 拥有实时坐标/AOI；Agent 拥有持久快照和连接绑定 |
| yield 点 | `service/player/player_agent.lua::REQUEST.move` 中的 `skynet.call(Scene)` |
| yield 前读取 | `scene_service`、`player.player_id`、请求 x/y |
| 恢复后是否可能过期 | 客户端业务由 `serial` 串行；系统消息仍可能改变连接与生命周期 |
| `call` 是否必要 | Agent 要使用 Scene 的权威提交结果生成 Response 和快照 |
| 是否产生 Hot Actor | Move 直达 Scene；SceneMgr 不在热路径，单 Scene 仍可能成为热点 |
| 是否需 generation | Connection 已有 `connection_id`；Scene Transfer 还没有 epoch |

换成 AOI Push 时，`call` 不必要，Scene 使用 `send`。换成 PlayerMgr 登录时，queue 必要，因为检查后有 `newservice/call` 两个 yield。Review 表必须按实际路径重填。

## 8. 用 Debug Console 看等待关系和 Mailbox

服务器与客户端运行时，在 Debug Console 执行：

```text
list
stat
task :<agent_address>
task :<scene_address>
trace :<scene_address> lua on
```

发送一次 `move`，随后关闭 trace：

```text
trace :<scene_address> lua off
```

`task` 用于看 coroutine 正在等待哪个 session/Service；`stat` 用于观察消息量、CPU 和 Mailbox。Scene `mqlen` 持续增长只证明观测窗口内到达率高于处理率。原因可能是 Handler CPU、GC、下游 call 或流量洪峰，需要与当前 task、单消息耗时和下游延迟放在同一时间线上判断。

个人环境可以使用 `debug :Address` 与 `watch("lua")` 逐行观察下一条 Lua 消息。目标 Service 在交互点可能暂停，不能在共享服务器或生产环境长时间使用。

## 9. 回归与完成标准

恢复实验文件前先查 `git diff -- <path>`，只回退自己加入的 `get_gold`/测试命令和人工 delay。然后：

```bash
./scripts/linux/test.sh
git status --short
```

验收时需要独立完成：

1. 用 Debug Console 从登录前后拓扑中找到动态 PlayerAgent，并说明 Address 的生命周期。
2. 从 `service/gateway/watchdog.lua:74` 走完登录，列出每个 yield 点和恢复后的 fd/connection generation 检查。
3. 从 Client Move 走到 Scene `retpack` 再回到 Client，标出 session 0/非 0、yield/resume 和两类坐标的 Owner/快照关系。
4. 交付一次可重复的 Lost Update 输出和 queue 修复后输出，不以手工断点碰运气。
5. 说明 PlayerMgr 为什么需要按 player_id 串行创建，SceneMgr 为什么要锁内二次检查。
6. 遇到 Scene `mqlen` 持续上升时，先查单条 Handler 耗时、下游 call 和 Hot Actor，不把增加 Worker 当作默认答案。

第二课重写版末尾的 15 道题已经逐题附上参考答案。完成实操后，至少对第 4、6、8、9、10、11、15 题重新作答，并在答案中引用本次运行得到的 Service Address、断点现场或 Lost Update 输出。参考答案用于校准语义，不能替代现场验证。
