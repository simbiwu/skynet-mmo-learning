# Skynet MMO 学习课程第二课：Service 模型与 Actor 架构

> 适用基线：Skynet v1.8.0，Skynet Bundled Modified Lua 5.4.7。
> 前置内容：第一课的构建、启动链、LuaPanda、Debug Console 和 GDB。
> 本课任务：从一次真实的 `move` 请求出发，理解 Actor、Service、Mailbox、Worker、coroutine，以及 `call/send` 的运行语义。

---

## 0. 从一个 C++ Scene 开始

Actor 这个词很容易被讲得过于抽象。我们先从熟悉的 C++ MMO Scene 写法开始。

```cpp
class Scene {
public:
    MoveResult Move(PlayerId id, int x, int y);
    AttackResult Attack(PlayerId id, EntityId target);

private:
    std::unordered_map<PlayerId, Player> players_;
    AoiGrid grid_;
};
```

如果网络线程、定时器线程和 GM 线程都保存了 `Scene*`，它们就可能在不同线程调用 `Move`、`Attack`、`UpdateMonster`。Scene 的内部状态需要锁来保护，跨模块调用还要规定锁的顺序和持有范围。

另一种组织方式是：外部代码不再直接调用 Scene，也不能取得 `players_` 的可写引用。它只能把命令放入 Scene 的收件箱。

```cpp
sceneInbox.Push(MoveCommand {
    .playerId = 10001,
    .x = 102,
    .y = 100,
});
```

Scene 收到命令后，由自己的处理逻辑修改 `players_` 和 `grid_`。这时，Scene 已经具备 Actor 的基本形态：它有可寻址的身份，有接收消息的入口，并且独占自己的可变状态。

```text
                         MoveCommand
Network / Timer / GM  ----------------->  Scene
                                         ├── Inbox
                                         ├── players
                                         ├── monsters
                                         ├── AOI grid
                                         └── Move/Attack/Enter/Leave
```

用一句平实的话描述：

> Actor 是一个拥有内部状态的运行单元。其他运行单元通过消息请求它工作，状态的实际修改由它自己完成。

这里包含四个要素：

| 要素 | Scene 例子 |
|---|---|
| Identity | Scene 的运行时地址 |
| Inbox | 等待处理的 Scene 消息 |
| State | 玩家、怪物、AOI、战斗状态 |
| Behavior | Move、Attack、Enter、Leave |

Actor 是一种架构模型。Skynet 用 Service 作为主要运行机制来实现它。因此，本课程提到“Scene Actor”时，指的是一个运行中的 Scene Service 以及它所拥有的状态和消息处理逻辑。

```text
Actor    架构模型
Service  Skynet 的运行时实体
Scene    业务角色

组合起来：用一个 Skynet Service 实现 Scene Actor
```

Actor 没有要求“一 Actor 一线程”。Skynet 中大量 Service 共享 Worker Pool。Actor 的稳定身份是 Service Address，Worker 只在调度到它时临时执行其代码。

还要留意 coroutine 带来的时序变化。一条消息的 handler 调用 `skynet.call` 后会挂起，Service 随后可以处理其他消息。Skynet 避免了同一 Lua State 被两个 Worker 同时执行，却仍然允许多条业务 coroutine 在时间上交错。后面讨论并发正确性时，我们会回到这个区别。

### 哪些东西可以看作 Actor

当前工程中，运行中的 Scene、PlayerAgent、Storage Worker 都符合 Actor 的特征。`movement.lua`、`combat.lua` 和 `aoi_grid.lua` 属于普通 Lua Module；它们由某个 Service 加载，没有自己的运行时地址和收件箱。

判断一个候选对象是否适合成为 Actor，可以检查四件事：

1. 是否存在需要独占管理的可变状态；
2. 是否需要独立的运行身份和生命周期；
3. 外部是否适合通过消息请求它执行行为；
4. 这个边界能否带来并行、隔离或分片价值。

如果一个组件只是纯算法，放在 Service 内作为 Module 往往更直接。

---

## 1. Actor 在 Skynet 中如何落地

下面把 Actor 的四个要素映射到 Skynet。

```text
Scene Actor
  |
  +-- Identity  -> Service Handle / Address
  +-- Inbox     -> Service Mailbox
  +-- State     -> scene.lua 所在 Lua State 中的局部数据
  +-- Behavior  -> CMD.enter / leave / move / attack
```

### Service

Service 是 Skynet Runtime 中可以创建、寻址、接收消息和退出的运行单元。运行中的 Lua Service 通常包括：

```text
skynet_context
  +-- Handle
  +-- callback
  +-- Mailbox
  +-- Runtime statistics

snlua instance
  +-- independent lua_State
  +-- module cache
  +-- Lua heap and GC
  +-- protocol dispatchers
  +-- message coroutines

business state
  +-- Scene entities / AOI
  +-- or PlayerAgent snapshot
```

`service/scene/scene.lua` 是加载代码。同一文件可以创建多个 Scene Service，每个实例都有独立 Address、Mailbox、Lua State 和业务数据。

### Handle 和 Address

Handle 是 Runtime 分配给 Service 的身份。Address 是 Lua API、日志和文档中常用的称呼，本课范围内可以把两者理解成同一个寻址概念。

```text
:00000012     十六进制形式的 Service Address
.launcher     当前节点注册的本地名称
```

调用：

```lua
skynet.call(scene_address, "lua", "move", player_id, x, y)
```

其中 `scene_address` 用来路由消息。它没有暴露 Scene 内部 table，也不表示 Scene 固定运行在哪条线程。

### Context

`skynet_context` 是 C Runtime 承载 Service 的结构。它关联 Handle、Callback、Mailbox、Module Instance 和运行统计。业务 Lua 平时不会直接操作 Context；在 GDB 中查看 `ctx->handle`、`ctx->queue` 和 callback 时会遇到它。

### Agent 和 Manager

Agent、Manager 属于项目的业务命名，Skynet Runtime 没有名为 Agent 或 Manager 的特殊类型。

当前工程采用“一名在线玩家对应一个 PlayerAgent Service”。PlayerAgent 持有玩家快照和当前连接，接收已登录玩家的请求，并协调 Scene 与 Storage。

Manager 负责生命周期和路由：

| Service | 管理内容 |
|---|---|
| PlayerMgr | `player_id -> PlayerAgent` |
| SceneMgr | `scene_id -> Scene` |
| StorageMgr | `player_id -> Storage Worker` |

Manager 可以帮助调用者找到目标 Service。找到目标后，高频数据通常直接发给 Owner，省去长期经过中心 Manager 的额外排队。

### Lua State 与 coroutine

每个 snlua Service 有自己的 `lua_State`。全局变量、`package.loaded`、Lua Heap、GC 和业务 table 都属于这个 Lua State。

一个 Lua State 中可以存在多条 coroutine。每当 Service 收到请求，`skynet.lua` 会创建或复用一条 coroutine 来执行 Protocol Dispatcher。coroutine 可以在 `call/sleep/wait` 等位置挂起，收到 Response 或 Wakeup 后继续执行。

```text
one snlua Service
  -> one Lua State
       -> many message coroutines over time
```

### Worker Thread

Worker 是共享执行器。它从 Global Queue 取得可运行的 Service Mailbox，然后调用对应 Service 的 callback。Worker 不长期归属于某个 PlayerAgent 或 Scene。

```text
Scene A -------\
Scene B --------+--> Worker Pool
PlayerAgent 1 --+
PlayerAgent 2 --/
```

业务日志和 Trace 应使用 Service Handle、Player ID、Scene ID 等稳定身份。Thread ID 适合分析 Runtime 调度和 Native Stack，不适合作为 Actor 身份。

---

## 2. 三种 Queue 容易混淆

Skynet 相关代码里会同时出现三种 Queue。它们位于不同层次。

| 名称 | 所在层 | 保存的内容 | 用途 |
|---|---|---|---|
| Mailbox / `message_queue` | C Runtime | 发给某个 Service 的 Message | Service 收件箱 |
| Global Queue | C Runtime | 当前可运行的 `message_queue*` | Worker 调度 |
| `skynet.queue()` | Lua Library | 等待进入临界区的 coroutine | 跨 yield 串行业务操作 |

### Mailbox

每个 Service 有一条私有 Mailbox。PlayerAgent 的 Mailbox 里可能同时出现：

```text
PTYPE_CLIENT move
PTYPE_LUA bind_client
PTYPE_RESPONSE from Scene
PTYPE_LUA push
```

它们按队列顺序被取出。某条消息对应的 coroutine 挂起后，后面的消息仍然可以开始处理，所以 Mailbox FIFO 只约束消息开始 Dispatch 的顺序。

### Global Queue

Global Queue 保存“当前有工作可做的 Mailbox”。Worker 从中取出一个 `message_queue*`，处理其中一批 Message，然后根据调度情况归还 Queue。

```text
Message -> Target Mailbox -> Global Queue -> Worker
```

`message_queue.in_global` 表示该 Mailbox 已经进入 Global Queue，或者正在 Dispatch。这项状态防止同一个 Mailbox 被多个 Worker 同时领取。

### `skynet.queue`

`skynet.queue()` 返回一个 Lua closure，用来串行一段允许 yield 的业务代码。PlayerAgent 使用它保护同一玩家的客户端业务请求：

```lua
local serial = require("skynet.queue")()

local function dispatch_request(name, args)
    return serial(REQUEST[name], args)
end
```

前一条 `REQUEST.move` 在 Scene RPC 上挂起时，后一条客户端请求会在 `serial` 入口等待。它不会创建新的 Mailbox，也不参与 Worker 调度。

---

## 3. 用一次 `move` 串起全部概念

客户端输入：

```text
move 102 100
```

完整路径如下：

```text
Client
  -> TCP frame
  -> Gate Service
  -> PTYPE_CLIENT Message
  -> PlayerAgent Mailbox
  -> Worker dispatches PlayerAgent
  -> PlayerAgent request coroutine
  -> REQUEST.move
  -> skynet.call(Scene)
  -> PlayerAgent coroutine yields
  -> Scene Mailbox
  -> Worker dispatches Scene
  -> Scene CMD.move
  -> PTYPE_RESPONSE
  -> PlayerAgent Mailbox
  -> original coroutine resumes
  -> update player snapshot
  -> encode Sproto response
  -> Client
```

把每一步放进运行上下文：

| 阶段 | Service | 执行上下文 | 状态所有者 |
|---|---|---|---|
| TCP 数据到达 | 无业务 Service | Socket Thread | Socket Runtime |
| 网络包转发 | Gate | Gate 消息 coroutine | Gate connection table |
| 请求解码 | PlayerAgent | PTYPE_CLIENT coroutine | Agent connection/snapshot |
| 移动判定 | Scene | PTYPE_LUA coroutine | Scene realtime state |
| RPC 恢复 | PlayerAgent | 原 PTYPE_CLIENT coroutine | Agent snapshot |

这张表中写“某个 Worker”比写 Worker 1 更准确。一次请求的不同阶段可以由不同 Worker 执行。

---

## 4. Gate 如何把消息交给 PlayerAgent

当前工程使用官方 `third_party/skynet/service/gate.lua`。登录前，Gate 尚未绑定 PlayerAgent，网络包先交给 Watchdog：

```lua
skynet.send(watchdog, "lua", "socket", "data", fd, packet)
```

Watchdog 完成 Auth、PlayerAgent 创建或复用、进场流程后，调用：

```lua
skynet.call(gate, "lua", "forward", fd, 0, agent)
```

Gate 从此保存：

```text
c.agent  = PlayerAgent Address
c.client = 0
```

后续业务包直接转发：

```lua
skynet.redirect(agent, c.client, "client", fd, msg, sz)
```

这条语句指定了目标、来源、Protocol、session 和 payload：

```text
destination = PlayerAgent Address
source      = 0
protocol    = PTYPE_CLIENT
session     = fd
payload     = Sproto bytes
```

`PTYPE_CLIENT` 在这里借用 session 字段携带 fd。它没有建立一次 Skynet RPC，所以 PlayerAgent 的 Client Dispatcher 会调用：

```lua
skynet.ignoreret()
```

客户端业务响应由 Sproto Response Encoder 生成，再通过 Socket 写回。它不走 `skynet.retpack`。

Watchdog 负责连接和登录的控制流程；完成绑定以后，Gate 把高频业务包直接送到 PlayerAgent。这个结构缩短了数据路径，也避免 Watchdog 变成所有在线玩家共用的转发热点。

---

## 5. Message、Protocol 和 Dispatcher

一条 Skynet Message 可以理解为以下逻辑字段：

```text
destination  目标 Service
source       来源 Service
session      请求与响应的关联号，或 Protocol 自定义值
type         PTYPE_LUA / RESPONSE / CLIENT / SOCKET ...
payload      序列化数据
```

Runtime 的 `struct skynet_message` 保存 source、session、data 和 sz。目标 Address 在投递时用于找到 Context；Protocol Type 编码在 `sz` 高位，真实 payload size 位于低位。

Protocol 决定如何解包 payload，以及把消息交给哪个 Dispatcher。Lua Service 常用：

```lua
skynet.dispatch("lua", function(session, source, command, ...)
    local fn = assert(CMD[command])
    local result = { fn(...) }
    if session ~= 0 then
        skynet.retpack(table.unpack(result))
    end
end)
```

这里可以分成三层：

```text
Protocol Dispatcher  接收 PTYPE_LUA Message
Command              payload 中的方法名，例如 "move"
Handler               CMD.move 函数
```

PlayerAgent 还注册了 `PTYPE_CLIENT`：

```lua
skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
    unpack = function(msg, sz)
        return host:dispatch(msg, sz)
    end,
    dispatch = function(fd, source, protocol_type, ...)
        ...
    end,
}
```

Sproto Host 在 unpack 阶段得到 `REQUEST`、协议名、参数和 Response Encoder。Dispatcher 随后调用对应的 `REQUEST.move`。

### session 的含义跟随 Protocol

一次 `move` 会经过三种 Message：

```text
Gate -> PlayerAgent
  PTYPE_CLIENT
  session = fd

PlayerAgent -> Scene
  PTYPE_LUA
  session = RPC session

Scene -> PlayerAgent
  PTYPE_RESPONSE
  session = same RPC session
```

调试时看到 session，需要同时查看 Message Type。只看整数本身无法判断它是 fd 还是 RPC Correlation ID。

---

## 6. Mailbox 如何被 Worker 调度

相关源码：

```text
third_party/skynet/skynet-src/skynet_mq.c
third_party/skynet/skynet-src/skynet_server.c
third_party/skynet/skynet-src/skynet_start.c
```

`message_queue` 采用可扩容 Ring Buffer，初始容量为 64。`skynet_mq_push` 把 Message 写入目标 Mailbox；如果 Mailbox 当前不在 Global Queue，函数会把它标为 `in_global` 并放入 Global Queue。

Worker 主循环调用：

```text
skynet_context_message_dispatch(monitor, queue, weight)
```

简化后的过程为：

```text
pop a Mailbox from Global Queue
  -> read its Service Handle
  -> grab skynet_context
  -> pop one Message
  -> mark Monitor source/destination
  -> dispatch_message(ctx, msg)
  -> clear Monitor mark
  -> process more messages according to weight
  -> return/requeue Mailbox
```

`dispatch_message` 提取 Message Type 和 Payload Size，累计 Service 的 Message/CPU 统计，然后调用 `ctx->cb`。对于 snlua Service，这条 callback 链最终进入 `skynet.lua::dispatch_message`。

### Mailbox Overload

当 Mailbox 长度跨过 1024、2048、4096 等阈值，Runtime 会记录：

```text
May overload, message queue length = ...
```

积压可能来自 handler CPU 过重、同步等待下游、单 Scene 玩家过多、上游缺少 Backpressure 或瞬时 Burst。`stat` 中的 `mqlen` 能提供当前长度，连续采样才能判断它是短时波动还是持续失衡。

增加 Worker 数量能提高多个 Service 的并行执行能力。单个 Scene 持续积压时，还需要检查 Scene 的消息成本、AOI Fan-out、同步 RPC 和分片设计。

---

## 7. Lua Dispatcher 为什么使用 coroutine

`third_party/skynet/lualib/skynet.lua` 的 `raw_dispatch_message` 收到普通请求时，会取得 Protocol Dispatcher 并创建或复用一条 coroutine：

```lua
local co = co_create(f)
session_coroutine_id[co] = session
session_coroutine_address[co] = source
suspend(co, coroutine_resume(co, session, source, p.unpack(msg, sz)))
```

这几行完成三项工作：

1. 为本次请求准备执行上下文；
2. 保存请求的 session 和 source，供 Response 使用；
3. 解包 Message 并进入业务 Dispatcher。

handler 执行结束后，coroutine 会清理关联状态并回到 Coroutine Pool。若非零 session 没有调用 `ret/retpack/response/ignoreret`，Skynet 会输出 `Maybe forgot response`。

LuaPanda 的 Coroutine Hook 也发生在这一层。本仓库先加载 LuaPanda，再加载会缓存 `coroutine.create` 的 `skynet.lua`，确保后续消息 coroutine 都能被调试器跟踪。

---

## 8. `send`、`call` 和 Response

### `skynet.send`

`send` 发送 session 为 0 的 Message：

```lua
skynet.send(agent, "lua", "push", "entity_move", args)
```

调用方完成投递后继续运行，不等待目标返回业务结果。Scene 向 PlayerAgent 发送 AOI Push 就属于这种情况。Scene 的移动提交不会因为某个 Agent 或 Socket 较慢而同步等待。

调用方不等待结果，并不代表目标一定成功执行。需要可靠交付的关键业务还要设计 Ack、Operation ID、Retry 和 Deduplication。

### `skynet.call`

PlayerAgent 移动请求调用 Scene：

```lua
local ok, rx, ry = skynet.call(
    scene_service,
    "lua",
    "move",
    player.player_id,
    x,
    y
)
```

`call` 的核心流程是：

```text
allocate non-zero session
  -> send Request Message
  -> watching_session[session] = target
  -> session_id_coroutine[session] = current coroutine
  -> current coroutine yields
```

Worker 没有在这里阻塞。当前 Lua callback 返回 Runtime，PlayerAgent 也可以继续处理后续 Message。

Scene 的 Dispatcher 执行 `CMD.move` 后调用 `skynet.retpack`。Response 携带原 session，重新进入 PlayerAgent Mailbox。

```text
PlayerAgent coroutine A
  -> call Scene, session 37
  -> yield

Scene coroutine B
  -> CMD.move
  -> retpack(...), session 37

PlayerAgent receives PTYPE_RESPONSE
  -> find coroutine A by session 37
  -> resume coroutine A
```

`call` 因此很像 C++ coroutine 中的 `co_await ActorRpc(...)`：源码从下一行继续，底层已经经历了两次 Mailbox 投递和两个 Service 的执行。

### 业务失败与 Runtime 失败

Scene 可以正常返回：

```lua
return false, "OUT_OF_BOUNDS"
```

这仍是一条正常 Response，PlayerAgent 解包后得到业务返回值 `false`。

目标退出或 Dispatcher 抛异常时，调用方收到 `PTYPE_ERROR`，`skynet.call` 抛出 `call failed`。如需区分两类失败，调用方应在合适边界使用 `pcall`，并记录 target、command、trace id 和状态版本。宽泛捕获后继续运行会掩盖半提交状态。

---

## 9. Service 串行与 coroutine 交错

同一个 Service 的 Lua State 不会同时被两个 Worker 执行。这一保证消除了许多共享内存 Data Race，却没有覆盖整个业务事务。

考虑下面的代码：

```lua
local old_gold = player.gold
local price = skynet.call(shop, "lua", "get_price", item_id)
player.gold = old_gold - price
```

可能出现这样的时间线：

```text
coroutine A reads gold = 1000
coroutine A calls Shop and yields

coroutine B handles a reward message
coroutine B changes gold to 1500

Shop Response arrives
coroutine A resumes
coroutine A writes 1000 - price
```

两条 coroutine 从未同时执行 Lua 指令，结果依然发生了 Lost Update。问题来自 yield 前后的状态版本变化。

### Mailbox FIFO 的边界

假设 PlayerAgent 依次收到请求 A 和 B：

```text
Mailbox dequeue: A -> B
```

A 开始执行后在 Scene RPC 上挂起，B 随后可以开始。于是业务提交顺序还取决于下游响应和本地保护机制。

```text
A starts -> A yields -> B starts -> ... -> A resumes
```

审查一条 handler 时，需要列出所有可能 yield 的调用，包括封装在 Module 中的 `call/sleep/wait`。每次恢复后，再检查此前读取的 fd、Service Address、State Version 和 Entity 是否仍然有效。

### `skynet.queue` 如何串行业务段

PlayerAgent 通过同一个 `serial` closure 执行客户端业务请求：

```lua
local serial = queue()

local function dispatch_request(name, args)
    local fn = REQUEST[name]
    return serial(fn, args)
end
```

上游 `skynet.queue` 记录当前 coroutine、重入计数和等待队列。另一条 coroutine 进入时调用 `skynet.wait()`；持有者最外层退出后再唤醒下一条。

因此，`REQUEST.move` 在 Scene RPC 上挂起期间，下一条客户端业务请求仍会等待 `serial`。

保护范围由调用位置决定。当前 `CMD.bind_client` 没有经过这个 `serial`。`offline()` 虽然在 timer 中通过 `serial(offline)` 进入，但它内部会依次等待 Scene、Storage 和 PlayerMgr；重连可以在这些等待窗口执行 `bind_client`。这正是第三课记录的 offline/reconnect 竞态来源。

把所有消息都塞入一个大临界区会让慢 Storage 阻塞 Ping、Reconnect 和 Kick。更稳妥的设计是先定义状态机与 Version Protocol，再决定哪些 transition 需要共享同一串行区。

---

## 10. PlayerAgent 和 Scene 的状态所有权

当前坐标同时出现在 PlayerAgent 和 Scene：

```text
PlayerAgent player.x/player.y
Scene entity.x/entity.y
```

两份数据承担不同职责。Scene 负责在线期间的实时空间判定，PlayerAgent 保存可持久化的玩家快照。

移动流程采用以下顺序：

```text
PlayerAgent requests Scene.move
  -> Scene validates boundary and speed
  -> Scene updates AOI and authoritative position
  -> Scene returns committed coordinates
  -> PlayerAgent updates persistent snapshot
```

如果 PlayerAgent 在调用 Scene 前先更新坐标，Scene 拒绝移动后就会留下错误快照，掉线保存还可能把非法坐标写入 Storage。

判断状态所有权时，可以查看四个问题：谁决定修改是否成立，谁生成版本，出现冲突时采用哪一份，以及副本在什么时点同步。

当前工程的主要所有权如下：

| 状态 | Owner | 同步关系 |
|---|---|---|
| Connection lifecycle | Watchdog | Agent 保存当前 binding |
| Persistent player snapshot | PlayerAgent | 保存到 Storage |
| Online Agent mapping | PlayerMgr | 登录创建、退出比较 Address 后删除 |
| Realtime position | Scene | Commit 后同步给 Agent |
| AOI visible set | Scene | Push 给 Client |
| Monster HP/respawn | Scene | Combat Push 给观察者 |

### Scene 的无 yield 提交段

`CMD.move` 的关键部分依次执行：

```text
find entity
  -> validate integer position
  -> movement.try_move
  -> grid.move
  -> update entity position
  -> calculate visibility changes
  -> update visible sets
  -> send pushes
  -> return committed position
```

从读取旧位置、消费移动额度到提交 AOI，中间没有 `call/sleep/wait`。`skynet.send` 只投递 Push，不挂起 Scene coroutine，因此这段修改连续完成。

如果在中间加入同步 NavService RPC，等待期间玩家可能离场、再次移动或切换 Scene。恢复后就要重新校验 Entity Generation、Scene Epoch、Source Position 和 Request Sequence。高频移动判定通常更适合让 Scene 本地访问只读 Nav Data。

无 yield 提交段仍要保持短小且有明确 CPU Budget。一次扫描全地图的操作即使没有时序竞态，也会占用 Worker 并增加其他 Service 的调度延迟。

---

## 11. Service 边界与 Manager

Actor 边界会带来消息打包、排队、调度、失败处理和生命周期管理。拆分时应确认这些成本换来了什么。

适合独立 Service 的常见原因包括：

- 明确的可变状态所有权；
- 独立生命周期或故障隔离；
- 真实的并行和分片能力；
- 数据库连接等外部资源隔离；
- 跨节点路由边界。

AOI Grid、移动校验和伤害公式都是普通 Module。它们与 Scene 共享同一状态语境，函数调用比 RPC 更清晰。

### SceneMgr 的重复创建问题

SceneMgr 的 `get_scene` 包含两个 yield 点：

```text
check scenes[scene_id]
  -> newservice Scene
  -> call Scene.init
  -> publish Address
```

第一条 coroutine 在 `newservice` 处挂起后，第二条 coroutine 可能也发现 Map 中没有目标 Scene。当前代码用 `create_lock` 串行创建流程，并在进入临界区后再次检查 Map。

### PlayerMgr 的分片登录锁

同一玩家的并发登录必须落到同一把锁，否则可能创建两个 PlayerAgent。PlayerMgr 准备了 64 个 `skynet.queue`，用 player_id 选择 shard。

这样既能保证同一 player_id 串行，又避免某个玩家的慢加载阻塞全部登录。不同 player_id 偶尔落在同一 shard，会产生有限的额外等待。

### Hot Actor

当单个 Scene 的 `mqlen` 持续增长、CPU 时间集中、AOI Fan-out 过大，而且增加 Worker 后没有明显改善，它已经成为 Hot Actor。

可选方向包括实例化地图、分线、Region Partition、合并同 Tick Push、降低非关键广播频率。拆分会引入跨区迁移、Ghost Entity、Epoch 和顺序协议，应当以 Profile 和 Benchmark 作为依据。

---

## 12. fd、Timer 和 Service Address 都有生命周期

异步消息可能在产生后很久才被处理。消息携带的身份需要能够区分“当前实例”和“已经过期的上一代实例”。

### Connection ID

OS 会复用 fd。旧连接的 Close/Kick 延迟到达时，同一个数字可能已经属于新连接。Watchdog 为每次连接分配递增的 `connection_id`，并在关闭时同时检查 fd 和 id。

```text
connection identity = fd + connection_id
```

PlayerAgent 重连后可以绑定新的连接，同时保持玩家 Actor 的生命周期。玩家身份和 Socket 身份由此分开。

### Offline Version

断线时 PlayerAgent 增加 `offline_version`，Timer 捕获当前值：

```lua
local version = offline_version

skynet.timeout(6000, function()
    if version ~= offline_version or client_fd then
        return
    end
    serial(offline)
end)
```

玩家在宽限期内重连会改变 Version，旧 Timer 到点后直接结束。现有实现只在进入 `offline` 前校验一次，`offline` 内部各个 RPC 恢复后仍需重新检查，这部分属于已记录的生产缺口。

### Service Address

Manager 保存的 Address 指向某个具体 Service 实例。旧 Agent 退出时调用：

```lua
PlayerMgr.remove(player_id, agent_address)
```

PlayerMgr 会比较 Map 中当前 Address，只有一致才删除。这样可以防止旧 Agent 的延迟 Remove 清掉后来创建的新 Agent。

Scene 重建、跨服迁移和延迟 Timer 通常还需要 Scene Epoch、Actor Generation 或 State Version。

---

## 13. 同步调用链和失败传播

每增加一层 `call`，请求都会多经历一个 Mailbox、一次调度和一个等待 coroutine。

```text
Agent -> Scene -> Guild -> Storage -> Center
```

这样的调用链会传播下游 P99，并增加 Timeout、Cancel、Retry 和目标退出的处理成本。调用者当前确实需要返回值时再采用同步 RPC；通知和派生数据可以使用 `send` 或其他异步协议。

环形调用需要结合业务串行区分析：

```text
A calls B while holding queue A
B calls A
new message in A waits for queue A
```

A 的 Runtime 仍能接收消息，但处理 B 请求的 coroutine 卡在 queue A，原 coroutine 又等待 B，形成逻辑环路。排查时应画 Wait-for Graph，把 Service、session 和业务 queue 一起标出来。

### 目标 Service 退出

`watching_session` 记录每次 `call` 等待的目标。Skynet 收到 Error Protocol 后，会恢复相关 coroutine，并让 `yield_call` 抛出错误。这能结束永久等待，却不会自动回滚调用者在 yield 前已经修改的本地状态。

### 忘记 Response

非零 session 的 Request 需要通过 `ret/retpack` 回复，或者使用 `skynet.response` 延迟回复。特殊协议可以显式 `ignoreret`。handler 正常执行 `return` 只把值交给本地 Dispatcher；Dispatcher 仍要发送 Response。

---

## 14. 三组调试实验

### 实验一：LuaPanda 观察 `call` 前后

选择 `Skynet Lua：LuaPanda 调试 PlayerAgent`，在 `REQUEST.move` 设置两个断点：

```lua
local ok, rx, ry = skynet.call(...)
player.x, player.y = rx, ry
```

客户端输入：

```text
move 102 100
```

第一次停住时，记录 Player ID、旧坐标、Scene Address 和 Call Stack。Response 到达后，第二个断点仍位于原 `REQUEST.move` coroutine，`rx/ry` 是 Scene 提交后的结果。

随后切换到 `Skynet Lua：LuaPanda 调试 Scene`，在 `CMD.move` 中观察 `entities[key]`、Movement Token 和 Visible Set。确认 PlayerAgent 与 Scene 各自在独立 Lua State 中运行。

LuaPanda 只用于个人隔离环境。断点会改变调度时序，不能用来证明 Race 不存在。

### 实验二：Debug Console 查看等待链

连接：

```bash
./scripts/linux/debug_console.sh
```

常用命令：

```text
list
stat
task :<agent_handle>
task :<scene_handle>
```

`stat` 提供 `task/mqlen/cpu/message` 快照。`task` 可以显示挂起 coroutine 的 traceback。若 Agent 在等待 Scene，再查看 Scene 是否等待 Storage，就能逐层还原同步调用链。

稳定观察等待窗口时，建议在测试配置加入可控 Barrier，由测试代码决定何时释放。固定 `sleep` 会让复现依赖机器负载。

短时消息 Trace：

```text
trace :<handle> lua on
trace :<handle> lua off
```

它适合确认 Request、Call、Response 和 Resume 的顺序。高频 Service 长期开启会产生明显日志和运行开销。

### 实验三：GDB 查看 Runtime Dispatch

```bash
gdb --args ./third_party/skynet/skynet config/game.lua
```

断点：

```gdb
set breakpoint pending on
break skynet_context_push
break skynet_context_message_dispatch
break dispatch_message
run
```

这些函数命中频繁，可以先通过 Debug Console 获取目标 Handle，再增加条件。观察 `ctx->handle`、`msg->source` 和 `msg->session`，将 C Runtime Message 与 Lua 层的 Service 调用对应起来。

实验的目标是确认 Response 也会进入调用方 Mailbox，并由后续 Dispatch 恢复 coroutine。它并非从 Scene 线程直接回调 PlayerAgent 栈帧。

---

## 15. 修改 Service 时的审查顺序

本仓库要求在修改 Service 前完成以下检查。

### 状态

先列出 Service 拥有的状态，并区分权威状态、Cache 和 Snapshot。相同字段出现在多个位置时，写明修改决策权、版本来源和同步时点。

### yield

沿完整调用链寻找 `call/sleep/wait/newservice`、queue contention、Socket/Database API，以及 Module 内隐藏的 yield。对每个位置记录：yield 前读了什么，等待期间谁能修改，恢复后用什么 Version/Generation 校验。

### 消息方式

判断当前结果是否依赖目标返回值。需要结果时使用 `call` 并处理 Runtime Failure；通知类路径使用 `send`，同时根据业务重要性补充可靠性协议。

### Actor 边界

确认新 Service 具有独立状态、生命周期、资源隔离、并行或分片价值。检查 Manager 是否进入高频数据面，以及新边界是否产生深同步链。

### 陈旧消息

检查 fd、Service Address、Timer、Scene Transfer 和异步 Response 是否需要 Connection ID、Generation、Version 或 Epoch。

### 验证

为时序问题设计 Barrier-based Regression Test；用 LuaPanda 查看局部控制流，用 `stat/task/trace` 观察运行状态，用 GDB 连接 C Runtime。每种工具回答的问题不同。

---

## 16. 本课小结

把本课内容压缩成一张图：

```text
Actor model
  -> implemented by Skynet Service
       -> identified by Handle
       -> owns State and Mailbox
       -> Mailbox scheduled through Global Queue
       -> Worker enters Service callback
       -> snlua enters independent Lua State
       -> Protocol Dispatcher runs a coroutine
       -> send posts a message
       -> call posts a request and yields
       -> Response resumes original coroutine by session
```

Scene 的实时位置和 AOI 由 Scene Service 管理；PlayerAgent 保存玩家快照。一次移动先由 Scene 判定和提交，再同步回 Agent。这个顺序体现了 Actor State Ownership。

Service 的执行具有两层语义：Runtime 不会让两个 Worker 同时执行同一 Lua State；业务 coroutine 在 yield 后可以和其他消息交错。后续设计登录、重连、保存、场景迁移和交易系统时，都要在这个语义上分析状态版本。

### 自测题

1. Scene Actor 的 Identity、Inbox、State 和 Behavior 分别对应什么？
2. Mailbox、Global Queue 和 `skynet.queue` 各自保存什么？
3. Gate 转发的 `PTYPE_CLIENT` 为什么把 fd 放在 session 中？
4. `skynet.call` 挂起的是 Worker、Service，还是当前 coroutine？
5. Scene Response 如何找到 PlayerAgent 原来的 coroutine？
6. Mailbox FIFO 为什么无法保证整个业务事务严格串行？
7. PlayerAgent 和 Scene 都有坐标字段时，实时修改权属于谁？
8. `CMD.move` 中插入 NavService RPC 后，需要重新检查哪些状态？
9. PlayerMgr 为什么要比较 Agent Address 后再删除映射？
10. 哪些证据能判断一个 Manager 已经成为 Hot Actor？

### 完成标准

进入第三课前，应当能够独立画出 `move` 的消息链，解释每段所在的 Service、Lua State 和 coroutine；能够从源码说明 `call/response` 的 session 映射；能够找出一条 handler 的全部 yield 点，并说明恢复后的失效条件。

---

## 附录：源码阅读顺序

建议按一次 `move` 的执行链阅读：

```text
client/test_client.lua
  -> request("move")

third_party/skynet/service/gate.lua
  -> handler.message / redirect

service/player/player_agent.lua
  -> PTYPE_CLIENT dispatcher
  -> dispatch_request
  -> REQUEST.move

third_party/skynet/lualib/skynet/queue.lua
  -> player request serialization

third_party/skynet/lualib/skynet.lua
  -> skynet.call / yield_call

third_party/skynet/skynet-src/skynet_server.c
  -> skynet_send / skynet_context_push

third_party/skynet/skynet-src/skynet_mq.c
  -> Mailbox / Global Queue

third_party/skynet/skynet-src/skynet_server.c
  -> skynet_context_message_dispatch / dispatch_message

third_party/skynet/lualib/skynet.lua
  -> raw_dispatch_message

service/scene/scene.lua
  -> CMD.move / retpack

third_party/skynet/lualib/skynet.lua
  -> PTYPE_RESPONSE / coroutine resume

service/player/player_agent.lua
  -> update snapshot / encode Sproto Response
```

配套调试说明见 `docs/16_DEBUGGING.md`，完整 MMO 生命周期与一致性分析见第三课。
