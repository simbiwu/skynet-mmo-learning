# Skynet MMO 学习课程第二课：Service 模型、消息通信与 MMO Actor 架构

> **工程基线**：`simbiwu/skynet-mmo-learning` 当前 `main` 分支
> **Skynet 基线**：Skynet v1.8.0 + Skynet Bundled Modified Lua 5.4.7
> **运行环境**：Linux / WSL2
> **前置课程**：第一课《从构建产物到业务 Service：Skynet 启动链源码导读》

---

## 0. 这一课到底要解决什么问题

第一课解决的是：

```text
./third_party/skynet/skynet config/game.lua
```

执行以后，Skynet Runtime、`snlua`、`loader.lua`、`bootstrap.lua` 和我们的 `service/main.lua` 是怎样一层一层启动起来的。

到了第二课，重点应该从“Skynet 怎么启动”转到“Skynet 启动以后，MMO 业务应该怎样写”。

这一课只围绕四个问题展开：

1. **Service 到底是什么，一个 Lua Service 和 Lua State 是什么关系？**
2. **Service 之间怎样通信，`call / send / dispatch / retpack` 分别解决什么问题？**
3. **为什么 Skynet 的 Service 明明是单线程执行，仍然会出现业务并发和状态覆盖？**
4. **Player、Scene、Storage、Watchdog 这些 MMO 状态究竟应该归谁管理？Service 应该拆多细？**

学完本课后，你至少应该能自己完成下面这些事情：

- 写一个新的 Lua Service；
- 用 `skynet.newservice` / `skynet.uniqueservice` 创建它；
- 用 `skynet.call` 和 `skynet.send` 与其它 Service 通信；
- 写出标准的 `skynet.dispatch("lua", ...)` 消息入口；
- 能识别一个 Handler 中所有可能发生 yield 的位置；
- 理解 `skynet.queue` 为什么不是普通 C++ mutex，却能解决很多 Actor 内部的时序问题；
- 能决定一份 MMO 状态应该归 PlayerAgent、Scene、Manager 还是 Storage；
- 能解释当前工程中一次 `move` 请求的完整执行路径。

第三课再进入 Scene、九宫格 AOI、Monster、Combat。也就是说，本课会用 Scene 的 `move` 作为真实案例，但不会在这里展开 AOI 算法本身。

---

# 1. 先从你熟悉的 C++ MMO Server 讲起

你以前熟悉的 GameServer 大致可以抽象成：

```text
GameServer
│
├── PlayerManager
│    ├── Player 10001
│    ├── Player 10002
│    └── Player ...
│
├── SceneManager
│    ├── Scene 1
│    ├── Scene 2
│    └── Scene ...
│
├── MonsterManager
├── ActivityManager
└── TimerManager
```

如果整个 GameServer 业务主要跑在一个线程里，那么对象之间最自然的通信方式就是直接调用：

```cpp
Player* player = playerMgr.GetPlayer(playerId);
Scene* scene = sceneMgr.GetScene(sceneId);

scene->MovePlayer(player, x, y);
player->AddExp(100);
```

这种架构有一个很大的优点：**同一个 GameServer 主线程里，状态关系非常直接。**

只要你不在中间进入其它异步回调，就可以认为：

```text
读取 player.gold
修改 player.gold
更新背包
返回
```

是一段连续执行的逻辑。

Skynet 把这个模型换了一种组织方式。

现在 Player 和 Scene 不一定是同一个 GameServer 对象树中的两个 C++ 对象，而可能分别运行在两个 Service 里：

```text
PlayerAgent Service                      Scene Service

player = {                               entities = {
    player_id = 10001,                       ["p:10001"] = {...}
    gold = 10000,                         }
    level = 10,
}
```

PlayerAgent 不能拿到 Scene 内部的 `entities` 引用，然后直接调用：

```text
scene->MovePlayer(...)
```

它要发一条消息：

```lua
local ok, x, y = skynet.call(
    scene_service,
    "lua",
    "move",
    player.player_id,
    x,
    y
)
```

所以，从传统 C++ MMO 迁移到 Skynet 时，最重要的变化不是 Lua，而是：

```text
共享对象 + 直接函数调用

            ↓

状态所有权 + Service 消息通信
```

后面所有 Skynet 架构问题，基本都可以追溯到这两个概念。

---

# 2. Service 到底是什么

## 2.1 先给一个准确但够用的定义

在本课程里，可以把一个 Skynet Service 理解为：

> 一个有自己运行时身份、消息入口、私有状态和生命周期的执行单元。

对于我们工程里的 **Lua Service**，再具体一点：

```text
一个 Lua Service

    ↓

一个 snlua Service 实例

    ↓

一个独立 lua_State

    ├── 自己的 Lua 全局变量
    ├── 自己的 package.loaded
    ├── 自己的 Lua Heap / GC
    ├── 自己的业务状态
    └── 多条消息 Coroutine
```

这里正好回答你前面问过的问题：

> **是不是一个 Service 就对应一个 Lua State？**

准确说法是：

**一个 `snlua` 类型的 Lua Service 对应一个独立 Lua State。**

但 Skynet 中也存在 C Service，例如底层 logger 等，这些 Service 本身没有业务 Lua State，所以不能把“所有 Skynet Service”都简单等同成 Lua State。

在我们的学习工程里，下面这些都是 Lua Service：

```text
service/main.lua
service/gateway/watchdog.lua
service/player/player_mgr.lua
service/player/player_agent.lua
service/scene/scene_mgr.lua
service/scene/scene.lua
service/storage/storage_mgr.lua
service/storage/memory_worker.lua
service/storage/mysql_worker.lua
```

它们启动后，各自拥有独立 Lua State。

---

## 2.2 一个 Lua 文件不等于一个 Service

这个区别一定要建立起来。

文件：

```text
service/scene/scene.lua
```

只是 **Service 的代码模板**。

如果调用：

```lua
local scene1 = skynet.newservice("scene/scene")
local scene2 = skynet.newservice("scene/scene")
```

会产生两个不同的 Service：

```text
scene.lua 源代码
       │
       ├───────────────┐
       ↓               ↓
Scene Service A    Scene Service B
Lua State A        Lua State B
entities A         entities B
Mailbox A          Mailbox B
Address A          Address B
```

两个 Service 即使加载的是同一个 `scene.lua`，下面这些变量也不会共享：

```lua
local scene_id
local grid
local entities = {}
local visible = {}
```

这也是 Actor 隔离的基础。

---

## 2.3 普通 Lua Module 又是什么

当前仓库里：

```text
lualib/scene/aoi_grid.lua
lualib/scene/movement.lua
lualib/scene/combat.lua
```

它们不是 Service。

它们只是由 Scene Service `require` 进去的普通 Lua Module。

例如当前文件：

```text
service/scene/scene.lua
```

开头有：

```lua
local Grid = require "scene.aoi_grid"
local combat = require "scene.combat"
local movement = require "scene.movement"
```

这里的 `Grid`、`combat`、`movement`：

- 没有自己的 Service Address；
- 没有自己的 Mailbox；
- 不能被 `skynet.call`；
- 生命周期跟着加载它们的 Lua State；
- 本质仍然是普通函数调用。

所以判断“这个模块应该做成 Service，还是普通 Lua Module”，可以先问：

> 它是否真的需要独立状态、独立生命周期、消息边界、并行能力或者分片能力？

如果只是一个伤害公式：

```lua
combat.player_damage(player)
```

把它拆成 `CombatService`，然后每攻击一次都 `skynet.call`，通常只是在制造额外 RPC。

---

# 3. Service、Actor、Manager、Agent，不要混成一个概念

## 3.1 Actor 是架构概念，Service 是 Skynet 的运行实体

可以这样理解：

```text
Actor
    是一种设计思想

Service
    是 Skynet 提供的运行实体

PlayerAgent / Scene
    是我们的业务角色
```

例如：

```text
Scene Actor

Identity   -> Scene Service Address
Inbox      -> Scene Service Mailbox
State      -> entities / grid / visible
Behavior   -> enter / leave / move / attack
```

当前：

```text
service/scene/scene.lua
```

就是用一个 Skynet Service 来实现 Scene Actor。

---

## 3.2 Agent 和 Manager 不是 Skynet 的特殊语法

Skynet Runtime 并不知道：

```text
PlayerAgent
PlayerMgr
SceneMgr
StorageMgr
```

有什么特殊含义。

这些都是我们自己定义的业务架构角色。

当前工程中：

```text
PlayerAgent
    一名在线玩家对应一个 Service
    持有玩家业务状态和当前连接绑定

PlayerMgr
    管理 player_id -> PlayerAgent Address

SceneMgr
    管理 scene_id -> Scene Address

StorageMgr
    管理并路由 Storage Worker
```

这非常接近你以前 C++ 工程里的：

```cpp
PlayerManager
SceneManager
DBManager
```

但 Manager 里存的不再是：

```cpp
Player*
Scene*
```

而是：

```text
PlayerAgent Service Address
Scene Service Address
```

---

# 4. Service Address：Skynet 世界里的“对象句柄”

## 4.1 `skynet.self()`

一个 Service 可以通过：

```lua
local self = skynet.self()
```

取得自己的 Service Address。

你可以把它类比成：

```text
Actor ID
Runtime Handle
```

但不要把它理解成 C++ 指针。

它只是 Skynet Runtime 用来找到目标 Service 的地址。

例如当前文件：

```text
service/player/player_mgr.lua
```

创建 PlayerAgent 后，会把自己的 Address 传进去：

```lua
local ok, err = skynet.call(agent, "lua", "load", {
    player_id = player_id,
    storage_mgr = storage_mgr,
    scene_mgr = scene_mgr,
    player_mgr = skynet.self(),
})
```

以后 PlayerAgent 下线时，就能回调 PlayerMgr：

```lua
skynet.call(
    player_mgr,
    "lua",
    "remove",
    player.player_id,
    skynet.self()
)
```

---

## 4.2 Address 不是永久 ID

Service Address 代表的是：

> **当前这个 Service 实例。**

它不是 `player_id`，也不是永久业务 ID。

因此不要把 Service Address 持久化进玩家数据库，然后认为服务器重启以后还能继续用。

例如：

```text
玩家业务身份：player_id = 10001

当前运行实例：PlayerAgent Address = :00000025
```

第二次启动服务器时，它完全可能变成其它 Address。

这和你以前自己设计的 HANDLE 思路非常接近：

```text
Business ID
    用来标识“是谁”

Runtime Handle
    用来标识“当前是哪一个运行实例”
```

当前 `PlayerMgr.remove` 甚至还做了一次 Address 比较：

**文件：`service/player/player_mgr.lua`**

```lua
function CMD.remove(player_id, agent)
    if players[player_id] ~= agent then
        return false
    end

    players[player_id] = nil
    return true
end
```

为什么不是直接：

```lua
players[player_id] = nil
```

因为旧 Agent 的延迟消息可能在新 Agent 已经建立后才到。

如果不比较 Address：

```text
旧 Agent A 退出
        ↓
remove(10001, A) 延迟
        ↓
新 Agent B 已经登录
players[10001] = B
        ↓
旧 remove 到达
        ↓
错误删除 B
```

Address 比较就是一个非常典型的 **stale message 防护**。

---

# 5. 创建 Service：`newservice` 与 `uniqueservice`

## 5.1 `skynet.newservice`

例如当前：

**文件：`service/player/player_mgr.lua`**

```lua
local agent = skynet.newservice("player/player_agent")
```

意思是：

> 创建一个新的 `player/player_agent` Lua Service 实例。

再次调用：

```lua
skynet.newservice("player/player_agent")
```

还会再创建一个。

因此它适合：

```text
PlayerAgent
Scene Instance
Storage Worker
Dungeon Instance
```

等“一种代码模板，需要很多运行实例”的 Service。

---

## 5.2 `skynet.uniqueservice`

当前：

**文件：`service/main.lua`**

会创建：

```lua
local storage_mgr = skynet.uniqueservice("storage/storage_mgr")
local scene_mgr = skynet.uniqueservice("scene/scene_mgr")
local player_mgr = skynet.uniqueservice("player/player_mgr")
```

可以把 `uniqueservice` 理解成：

> 当前 Skynet Node 内，按这个服务名字只保留一个实例。

这比较适合 Manager。

但它不是 C++ 语言级 Singleton，也不代表：

- 跨机器唯一；
- 跨 Skynet Node 唯一；
- 自动高可用；
- 自动恢复状态；
- 性能无限。

它只是在当前 Skynet Runtime 中帮你管理一个唯一 Service 实例。

---

## 5.3 `newservice` 自己也可能 yield

这点非常重要。

从第一课已经知道，`newservice` 最终需要经过 `.launcher` 完成 Service 启动握手。

因此不要把：

```lua
local agent = skynet.newservice(...)
```

理解为 C++：

```cpp
auto* agent = new PlayerAgent;
```

它更接近：

```cpp
co_await ActorSystem.CreateActor(...);
```

因此 `newservice` 前后也存在 coroutine 时序问题。

当前 `SceneMgr` 就专门处理了这个问题。

---

# 6. Skynet Service 的标准消息入口

我们先看当前工程里最常见的一段代码。

**文件：`service/player/player_mgr.lua`**

```lua
skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(
            CMD[command],
            "unknown player_mgr command: " .. tostring(command)
        )

        local result = { fn(...) }

        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
```

这段代码基本就是当前工程很多普通 Lua Service 的标准入口。

下面逐项拆开。

---

## 6.1 `skynet.dispatch("lua", handler)`

它的作用是：

> 注册 `lua` 类型消息的处理函数。

以后其它 Service：

```lua
skynet.call(player_mgr, "lua", "login", player_id)
```

或者：

```lua
skynet.send(player_mgr, "lua", "remove", player_id, agent)
```

只要消息协议类型是：

```text
lua
```

都会进入这个 dispatcher。

`"lua"` 不是说“目标 Service 是 Lua 写的”，而是 **使用名为 `lua` 的 Skynet 消息协议**。

---

## 6.2 `session`

```lua
function(session, source, command, ...)
```

这里的 `session` 对普通 Lua RPC 非常重要。

简单理解：

```text
skynet.send
    session = 0

skynet.call
    session = 一个非 0 的请求关联号
```

`call` 需要等 Response，所以 Skynet 必须知道：

```text
这个返回结果
究竟对应之前哪一次 call？
```

session 就承担这个关联作用。

---

## 6.3 `source`

`source` 是消息来源 Service 的 Address。

例如：

```text
PlayerAgent
    call Scene
```

Scene 收到消息时：

```text
source = PlayerAgent Address
```

很多普通业务并不需要显式使用 `source`，但在：

- 权限验证；
- 日志追踪；
- 服务身份校验；
- Debug；

这些场景中会用到。

---

## 6.4 `command`

当前工程自己约定：

```text
Lua 消息的第一个业务参数 = command
```

例如：

```lua
skynet.call(scene, "lua", "move", player_id, x, y)
```

到 Scene：

```text
command = "move"

... = player_id, x, y
```

于是：

```lua
local fn = CMD[command]
```

最后调用：

```lua
CMD.move(player_id, x, y)
```

这实际上就是我们自己实现了一层：

```text
RPC Command Dispatcher
```

---

## 6.5 `skynet.retpack`

假设：

```lua
function CMD.get(player_id)
    return players[player_id]
end
```

函数的 `return` 只是：

> 把值返回给当前这个 Lua dispatcher。

它还没有自动返回到调用方 Service。

当前 dispatcher 会：

```lua
local result = { fn(...) }

if session ~= 0 then
    skynet.retpack(table.unpack(result))
end
```

`retpack` 才会把这些返回值封装成 Skynet Response，发回调用方。

所以要区分：

```text
CMD.xxx 的 Lua return

        和

跨 Service RPC Response
```

当前工程的 dispatcher 把两者连接了起来。

---

# 7. `skynet.send`：只发消息，不等结果

例如当前 Scene 广播：

**文件：`service/scene/scene.lua`**

```lua
local function push_player(player_id, name, args)
    local p = entities[ekey(TYPE_PLAYER, player_id)]

    if p and p.agent then
        skynet.send(
            p.agent,
            "lua",
            "push",
            name,
            args
        )
    end
end
```

Scene 告诉 PlayerAgent：

```text
有实体进入视野
有实体移动
怪物血量变化
```

这些通知并不需要 Scene 等待 PlayerAgent 返回：

```text
Scene
   │
   ├── send Agent A
   ├── send Agent B
   ├── send Agent C
   └── 继续执行
```

因此使用 `send` 很合理。

---

## 7.1 `send` 适合什么

典型场景：

```text
AOI Push
日志
聊天广播
事件通知
异步统计
非关键派生数据
```

特点：

```text
发送成功 ≠ 业务执行成功
```

调用方只是把消息交给 Skynet 去投递，不会等目标返回一个业务结果。

如果业务要求：

```text
必须确认执行
失败必须重试
绝不能重复
```

就不能简单因为用了 `send` 就认为可靠性问题已经解决。

商业系统仍然可能需要：

```text
Operation ID
Ack
Retry
Deduplication
```

这属于业务协议层，不是 `send` 自动提供的。

---

# 8. `skynet.call`：看起来同步，底层其实是 RPC + Coroutine yield

当前 PlayerAgent 的移动：

**文件：`service/player/player_agent.lua`**

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

代码看起来和普通函数很像：

```text
调用 Scene
等待结果
继续执行下一行
```

这也是 Skynet 非常好用的地方。

但底层不是普通函数调用。

可以把它理解成：

```text
PlayerAgent Coroutine A

    ↓

生成一个 RPC session

    ↓

把 Request 投递到 Scene Mailbox

    ↓

Coroutine A yield

    ↓

Worker 可以去执行别的工作

    ↓

Scene 处理 move

    ↓

Scene retpack Response

    ↓

Response 回到 PlayerAgent

    ↓

根据 session 找到 Coroutine A

    ↓

Coroutine A resume

    ↓

skynet.call 返回
```

如果用现代 C++ 表达思想，大致接近：

```cpp
auto [ok, x, y] = co_await CallActor(scene, MoveRequest{...});
```

---

## 8.1 `call` 挂起的不是 Worker Thread

这点一定不要理解错。

假设：

```lua
skynet.call(scene_service, "lua", "move", ...)
```

等待 Scene Response 时：

**不是这个 Worker Thread 被阻塞在那里。**

真正被挂起的是：

```text
当前 PlayerAgent 的请求 Coroutine
```

Worker 可以继续执行：

```text
其它 Scene
其它 PlayerAgent
甚至当前 PlayerAgent 的其它消息 Coroutine
```

最后这句话就是下一节最关键的内容。

---

# 9. “一个 Service 单线程执行”为什么仍然会有并发问题

这是第二课最重要的知识点之一。

## 9.1 Skynet 给你的保证是什么

一个 Lua Service 的同一个 Lua State，不会在同一时刻被两个 Worker Thread 同时执行 Lua 代码。

所以不会出现这种情况：

```text
Worker 1                    Worker 2

同时执行同一个
PlayerAgent Lua State
```

这已经帮你消除了大量传统共享内存多线程 Data Race。

但它没有保证：

> 一个业务 Handler 从开始到结束永远不会被其它消息逻辑穿插。

---

## 9.2 一个经典 Lost Update

假设 PlayerAgent：

```lua
local old_gold = player.gold

local price = skynet.call(
    shop,
    "lua",
    "get_price",
    item_id
)

player.gold = old_gold - price
```

开始时：

```text
player.gold = 1000
```

执行顺序可能是：

```text
Coroutine A：BuyItem

old_gold = 1000

        ↓

call Shop

        ↓

yield
```

这时 PlayerAgent 可以收到其它消息。

例如：

```text
Coroutine B：Reward

player.gold = 1500
```

随后 Shop Response 回来：

```text
Coroutine A resume

player.gold = old_gold - 100
            = 900
```

Reward 加进去的 500 被覆盖了。

注意：

```text
A 和 B 从未同时执行 Lua 指令。
```

但结果仍然发生了并发逻辑错误。

因此以后审查 Skynet 代码，不能只问：

```text
这个 Service 是不是单线程？
```

还要问：

```text
这个 Handler 中间哪里会 yield？

yield 期间，同一个 Service 的哪些状态可能被其它 Coroutine 改？

恢复以后，之前读到的数据还有效吗？
```

---

# 10. 哪些操作要当成 yield 点看待

至少要对下面这些保持警觉：

```text
skynet.call(...)
skynet.sleep(...)
skynet.wait(...)
skynet.newservice(...)
skynet.uniqueservice(...)
```

以及某些封装起来的：

```text
数据库操作
Socket 等待
Cluster RPC
其它底层最终会等待 Response / Wakeup 的 API
```

重点不是死记 API 清单，而是建立一个习惯：

> **如果当前 Coroutine 需要等待某件将来才发生的事，就要怀疑这里存在 yield。**

---

# 11. `skynet.queue`：Skynet 业务开发中非常重要的工具

当前工程已经用了三种非常典型的 `skynet.queue` 场景。

先理解它的本质。

`skynet.queue()` 返回的是一个 **Coroutine 级的串行执行器**。

它不是 OS mutex，也不会让 Worker Thread 卡死。

如果 Coroutine A 已经进入 queue，Coroutine B 再进来：

```text
Coroutine B
    ↓
skynet.wait()
    ↓
挂起
```

等 A 离开以后，再 `wakeup` B。

---

## 11.1 场景一：PlayerAgent 串行客户端业务

**文件：`service/player/player_agent.lua`**

```lua
local serial = queue()
```

客户端请求最终经过：

```lua
local function dispatch_request(name, args)
    local fn = REQUEST[name]

    if not fn then
        return {
            code = 404,
            message = "UNKNOWN_REQUEST"
        }
    end

    return serial(fn, args)
end
```

假设客户端连续发：

```text
move
attack
move
```

第一条 `move` 内部：

```lua
skynet.call(scene_service, ...)
```

发生 yield。

如果没有 `serial`，下一条 `attack` 可以进入另一个 Coroutine 开始执行。

加入：

```text
serial
```

以后：

```text
move
   ↓
等待 Scene
   ↓
完成

attack
   ↓
开始
```

这样一个玩家的客户端核心业务保持串行。

这和你之前考虑过的：

> 多线程处理不同玩家，但同一玩家必须串行

实际上是高度一致的。

Skynet 天然很适合这种模型。

---

## 11.2 场景二：PlayerMgr 防止同一玩家创建两个 Agent

当前：

**文件：`service/player/player_mgr.lua`**

```lua
local login_locks = {}

for i = 1, 64 do
    login_locks[i] = queue()
end
```

然后：

```lua
local function player_lock(player_id)
    return login_locks[(player_id % #login_locks) + 1]
end
```

登录：

```lua
function CMD.login(player_id)
    return player_lock(player_id)(function()
        local existing = players[player_id]

        if existing then
            return existing, false
        end

        local agent = skynet.newservice("player/player_agent")
        ...

        players[player_id] = agent
        return agent, true
    end)
end
```

为什么必须锁？

如果没有：

```text
Coroutine A
players[10001] == nil
newservice → yield

Coroutine B
players[10001] == nil
newservice → yield
```

最后可能创建：

```text
PlayerAgent A
PlayerAgent B
```

同时代表玩家 10001。

这在 MMO 中属于 P0 级错误。

---

## 11.3 为什么不是“一个玩家一把永不释放的锁”

当前 PlayerMgr 用 64 路分片：

```text
player_id % 64
```

这样不会永久维护：

```text
曾经登录过多少玩家
就留多少 queue object
```

代价是：

```text
两个不同 player_id
偶尔会 hash 到同一把锁
```

它们的登录会短暂互相等待。

这是一个很典型的工程取舍：

```text
有界锁数量
换取少量无害碰撞
```

---

## 11.4 场景三：SceneMgr 防止重复创建同一 Scene

**文件：`service/scene/scene_mgr.lua`**

```lua
local scenes = {}
local create_lock = queue()
```

创建：

```lua
local function get_scene(scene_id)
    if scenes[scene_id] then
        return scenes[scene_id]
    end

    return create_lock(function()
        if scenes[scene_id] then
            return scenes[scene_id]
        end

        local service = skynet.newservice("scene/scene")
        skynet.call(service, "lua", "init", scene_id)

        scenes[scene_id] = service
        return service
    end)
end
```

这里有两个很重要的点。

第一，为什么要 lock？

因为：

```text
newservice
call Scene.init
```

都可能 yield。

第二，为什么进 lock 后还要再检查一次：

```lua
if scenes[scene_id] then
    return scenes[scene_id]
end
```

因为 Coroutine B 等锁期间，Coroutine A 可能已经把 Scene 创建好了。

这就是非常标准的：

```text
Check
Lock
Check Again
Create
Publish
```

---

# 12. `skynet.queue` 不是越多越好

看到 coroutine 重入以后，很容易走向另一个极端：

```text
那我把整个 Service 所有 Handler 都包进一个 queue。
```

这往往会把 Actor 自己变成一个“大锁”。

例如：

```text
PlayerAgent

Queue持有期间：
    call Scene
    call Storage
    sleep
    call Guild
```

如果 Storage 卡了：

```text
Ping
重连
顶号
Kick
其它状态修复
```

可能全部排在后面。

所以 queue 的原则不是：

```text
哪里有 yield 就全部锁住。
```

而是：

> 先确定哪一段状态修改必须构成一个串行事务，再决定 queue 的边界。

对商业 MMO 来说，很多复杂系统最终会采用：

```text
状态机
+ Version / Generation
+ 小范围 queue
```

而不是一把大锁包住所有事情。

---

# 13. MMO 架构最重要的问题：状态到底归谁

Skynet Actor 模型真正有价值的地方，不是：

```text
把功能拆成很多 Service。
```

而是：

```text
让每一份可变状态都有明确 Owner。
```

当前学习工程已经体现得比较清楚。

| 状态 | Owner | 文件 |
|---|---|---|
| TCP 连接生命周期 | Watchdog | `service/gateway/watchdog.lua` |
| 当前连接绑定 | PlayerAgent | `service/player/player_agent.lua` |
| `player_id -> Agent` | PlayerMgr | `service/player/player_mgr.lua` |
| 玩家持久化快照 | PlayerAgent | `service/player/player_agent.lua` |
| `scene_id -> Scene` | SceneMgr | `service/scene/scene_mgr.lua` |
| 在线实时坐标 | Scene | `service/scene/scene.lua` |
| AOI 可视集合 | Scene | `service/scene/scene.lua` |
| Monster HP / Respawn | Scene | `service/scene/scene.lua` |
| 存储 Worker 路由 | StorageMgr | `service/storage/storage_mgr.lua` |

---

# 14. PlayerAgent 和 Scene 为什么都有 x/y

当前 PlayerAgent 里：

```lua
player.x
player.y
```

Scene 里面也有：

```lua
entity.x
entity.y
```

表面上看像重复状态。

关键在于：

```text
它们不是两个同级的权威状态。
```

当前设计：

```text
Scene
    在线期间实时位置 Owner

PlayerAgent
    持久化 Snapshot
```

移动流程：

```text
PlayerAgent
    │
    │ 请求移动
    ▼
Scene
    │
    ├── 校验移动是否合法
    ├── 修改 Grid
    ├── 修改权威位置
    ├── 修改 AOI
    │
    └── 返回已提交坐标
         │
         ▼
PlayerAgent
    │
    └── 更新 player.x / player.y 快照
```

当前代码：

**文件：`service/player/player_agent.lua`**

```lua
local ok, rx, ry = skynet.call(
    scene_service,
    "lua",
    "move",
    player.player_id,
    x,
    y
)

if not ok then
    return {
        code = 3,
        message = rx or "MOVE_FAILED",
    }
end

player.x, player.y = rx, ry
```

顺序非常关键。

如果 PlayerAgent 先：

```lua
player.x = x
player.y = y
```

然后才请求 Scene：

```text
Scene拒绝移动
```

PlayerAgent 就已经留下错误快照。

玩家此时掉线，甚至可能把非法位置保存进数据库。

这就是 **State Ownership 决定更新顺序** 的一个真实例子。

---

# 15. Scene 为什么适合做一个 Actor

当前：

```text
service/scene/scene.lua
```

拥有：

```lua
local grid
local entities = {}
local visible = {}
```

这些状态之间具有非常强的事务关系。

一次移动可能同时修改：

```text
玩家位置
Grid Cell
玩家自己的 visible
其它玩家的 visible
AOI Enter
AOI Leave
AOI Move Push
```

如果把这些拆成：

```text
PositionService
AOIService
CombatService
MonsterService
```

一次移动变成：

```text
Scene
  call Position
  call AOI
  call Visibility
  call Broadcast
```

复杂度和失败窗口会急剧增加。

因此当前工程采用：

```text
一个 Scene Service
    + AOI 普通 Module
    + Movement 普通 Module
    + Combat 普通 Module
```

这个边界非常合理。

Actor 粒度的基本判断可以记成：

> 高度耦合、需要一起提交的状态，尽量留在同一个 Actor；真正需要独立生命周期、隔离、分片或并行的边界，再拆 Service。

---

# 16. 当前 Scene 的一个重要设计：关键提交段不 yield

看当前：

**文件：`service/scene/scene.lua`**

`CMD.move` 的关键路径大致是：

```text
找到 Player Entity
    ↓
校验目标坐标
    ↓
movement.try_move
    ↓
grid.move
    ↓
修改 player.x / y
    ↓
重新计算 visible
    ↓
提交 visible 差异
    ↓
skynet.send AOI Push
    ↓
return
```

这里中间没有：

```text
skynet.call
skynet.sleep
skynet.wait
```

而：

```lua
skynet.send(...)
```

不会等待目标结果，因此不会像 `call` 那样挂起当前 Coroutine。

这意味着从移动校验到 AOI 提交，是一段连续完成的状态修改。

对于高频 Scene 逻辑，这非常重要。

你可以把它类比成以前单线程 GameServer 中：

```cpp
bool Scene::MovePlayer(...)
{
    Validate();
    UpdateGrid();
    UpdateAOI();
    Broadcast();
    return true;
}
```

尽量不要在中间突然：

```cpp
await RemoteNavServer();
```

否则 Actor 内部的时序模型会立刻复杂很多。

---

# 17. Manager 应该负责什么，不应该负责什么

当前工程中的 Manager 基本承担两类职责：

```text
Lifecycle
Routing
```

例如：

```text
PlayerMgr
    player_id -> PlayerAgent

SceneMgr
    scene_id -> Scene

StorageMgr
    player_id -> Storage Worker
```

这很合理。

但 Manager 很容易被写成：

```text
所有请求都必须经过 Manager
```

例如错误设计：

```text
PlayerAgent
    ↓
SceneMgr
    ↓
Scene
```

每一次移动都走 SceneMgr。

这样 SceneMgr 会成为额外数据面节点。

当前 PlayerAgent 在 `enter_world` 时取得真实 Scene Address：

```lua
local ok, scene, snapshot = skynet.call(
    scene_mgr,
    "lua",
    "enter",
    {...}
)

scene_service = scene
```

以后移动直接：

```text
PlayerAgent
    ↓
Scene
```

不再经过 SceneMgr。

这是非常值得保留的设计习惯：

> Manager 负责找到 Actor，找到以后高频路径尽量直接访问 Owner。

---

# 18. StorageMgr 为什么用了 Worker Pool

当前：

**文件：`service/storage/storage_mgr.lua`**

启动时会创建固定数量 Worker：

```lua
for i = 1, conf.pool do
    local worker = skynet.newservice(service_name)
    skynet.call(worker, "lua", "start", conf, i)
    workers[i] = worker
end
```

玩家固定路由：

```lua
return workers[(player_id % #workers) + 1]
```

因此：

```text
Player 10001
    永远去 Worker X

Player 10002
    永远去 Worker Y
```

这有两个价值。

第一，避免：

```text
全服所有 DB 请求
    ↓
一个 Storage Service
```

形成单 Actor 瓶颈。

第二，同一个玩家的操作稳定落到同一个 Worker，有利于维护操作顺序。

这和你以前 DBServer 里：

```text
同一玩家写请求需要有稳定顺序
后写不能被旧写覆盖
```

的考虑是一致的。

当前学习版仍然通过 StorageMgr 中转所有请求。后续商业化优化时，可以进一步让 PlayerAgent 缓存自己对应的 Worker Address，减少一个 Manager hop。

---

# 19. Service 粒度：是不是一个玩家一个 Service？

当前项目明确采用：

```text
One online player = one PlayerAgent Service
```

这对于学习 Skynet 非常合适。

每个玩家：

```text
自己的 Lua State
自己的业务状态
自己的请求串行队列
自己的连接绑定
```

状态边界很清楚。

但是到了真正商业 MMO，不能只因为 Actor 模型就机械地认为：

```text
一切对象都一个 Service。
```

---

## 19.1 一玩家一 Service 的优点

```text
状态所有权非常清楚
玩家之间天然隔离
不同玩家可由 Worker Pool 并行执行
单玩家业务容易串行
Agent异常影响范围较小
```

尤其适合：

```text
玩家业务很多
玩家之间直接共享状态较少
在线人数规模适中
```

的游戏。

---

## 19.2 成本

每个 `snlua` PlayerAgent 都有：

```text
Lua State
Lua Heap
package.loaded
Coroutine相关状态
Service Runtime结构
Mailbox
```

所以如果：

```text
10 万在线
```

就必须实测：

```text
空 Agent 基础内存
加载业务 Module 后内存
平均玩家业务状态
Coroutine峰值
Service调度成本
```

不能只从架构美观判断。

---

## 19.3 商业项目常见的折中

可能是：

```text
PlayerAgent：一玩家一 Actor
Scene：一个地图实例一个 Actor
Guild：多个公会一个 Shard Actor
Storage：固定 Worker Pool
Rank：按榜或按Shard拆
Chat：独立Service或节点
```

而不是：

```text
一个玩家
    一个BagService
    一个TaskService
    一个EquipService
    一个SkillService
    一个MailService
```

Bag、Task、Equip 如果只是 PlayerAgent 内部高度耦合的玩家状态，更适合普通 Lua Module：

```text
PlayerAgent
    ├── bag.lua
    ├── task.lua
    ├── equip.lua
    └── skill.lua
```

这与你以前：

```cpp
Player
    BagModule
    TaskModule
    EquipModule
```

的模块化思路其实没有冲突。

---

# 20. 独立 Lua State 带来的另一个现实问题：内存

如果每个 Lua Service 都有独立 Lua State，那么：

```lua
require "huge_item_config"
```

默认情况下，每个 Lua State 都有自己的 `package.loaded` 和 Lua 对象。

如果配置非常大：

```text
Item 20MB
Monster 20MB
Skill 30MB
Activity 30MB
```

再有很多 Agent/Scene 重复加载，会带来明显内存浪费。

当前 Scene 已经使用：

```lua
local sharedata = require "skynet.sharedata"
```

并读取：

```lua
local game_cfg = sharedata.query "game_config"
```

这是 Skynet 对大型只读共享配置非常重要的机制。

本课先记住原因即可：

> Service 隔离带来清晰状态边界，同时也意味着普通 Lua 对象不会天然跨 Lua State 共享。

sharedata 的配置体系和热更新，可以放到第四课生产化部分继续展开。

---

# 21. 完整案例一：一次登录，Service 是怎样串起来的

这一段不展开网络协议细节，只关注 Service 协作。

当前主要文件：

```text
service/gateway/watchdog.lua
service/player/player_mgr.lua
service/player/player_agent.lua
service/storage/storage_mgr.lua
service/scene/scene_mgr.lua
service/scene/scene.lua
```

完整链路：

```text
Client
   │
   ▼
Gate
   │
   │ 登录前数据
   ▼
Watchdog
   │
   ├── call Auth
   │
   ├── call PlayerMgr.login
   │         │
   │         ├── newservice PlayerAgent
   │         │
   │         └── call PlayerAgent.load
   │                    │
   │                    └── call StorageMgr.load_player
   │                              │
   │                              └── call Storage Worker
   │
   ├── call PlayerAgent.bind_client
   │
   ├── call PlayerAgent.enter_world
   │         │
   │         └── call SceneMgr.enter
   │                   │
   │                   └── call Scene.enter
   │
   └── Gate.forward(fd -> PlayerAgent)
```

这条链能很好地说明：

```text
Service不是类层级
Manager不是中央GameServer
Agent也不是网络线程
```

它们是多个状态 Owner，通过 RPC 协作完成一次登录。

---

# 22. Watchdog 中为什么每次 `call` 之后都要重新检查 Connection

当前：

**文件：`service/gateway/watchdog.lua`**

登录过程中有：

```lua
local auth_ok = skynet.call(...)

if not alive(fd, c) then
    return
end
```

后面还有：

```lua
local agent, is_new, err = skynet.call(...)

if not alive(fd, c) then
    ...
    return
end
```

为什么这么啰嗦？

因为：

```text
call = yield
```

在 Watchdog 等 Auth / PlayerMgr / Agent 的期间：

```text
Client完全可能已经断线。
```

所以：

```text
call之前的 c
```

不能无条件认为在 call 返回后仍然代表当前有效 Connection。

这就是我们前面讲的：

> yield 之后要重新验证之前依赖的状态。

当前 Watchdog 的 `connection_id` 也是同一个思想。

fd 可能被操作系统复用，因此连接身份采用：

```text
fd + connection_id
```

和你以前的：

```text
HANDLE + unique id
```

双校验几乎是同一种工程思路。

---

# 23. 完整案例二：一次 move 请求

这条链是本课最值得真正掌握的例子。

当前核心文件：

```text
service/player/player_agent.lua
service/scene/scene.lua
```

登录完成以后，Gate 已经把这个 fd 的数据转发目标设置成 PlayerAgent。

流程：

```text
Client
  │
  │ move(x, y)
  ▼
Gate
  │
  │ PTYPE_CLIENT
  ▼
PlayerAgent
  │
  │ Sproto decode
  ▼
REQUEST.move
  │
  │ serial(...)
  ▼
Player业务Coroutine
  │
  │ skynet.call(Scene, "move", ...)
  │
  ├──────────── yield ──────────────┐
  │                                 │
  │                          Scene Mailbox
  │                                 │
  │                                 ▼
  │                            Scene CMD.move
  │                                 │
  │                         校验 / Grid / AOI
  │                                 │
  │                         send AOI Push
  │                                 │
  │                         retpack(ok,x,y)
  │                                 │
  └────────── Response ─────────────┘
  │
  ▼
原 Player Coroutine resume
  │
  ├── player.x = rx
  ├── player.y = ry
  │
  ▼
Sproto Response
  │
  ▼
Client
```

---

# 24. 把 `move` 对应到真实代码

## 第一步：PlayerAgent 收到客户端请求

**文件：`service/player/player_agent.lua`**

PlayerAgent 注册了：

```lua
skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
    ...
}
```

因此 Gate 转过来的已登录客户端包，会进入这个 Protocol Dispatcher。

解析以后：

```lua
local name, args, response = ...

local ok, result = pcall(
    dispatch_request,
    name,
    args
)
```

如果是：

```text
move
```

最终找到：

```lua
REQUEST.move
```

---

## 第二步：进入 PlayerAgent 的 `serial`

当前：

```lua
return serial(fn, args)
```

这保证当前玩家的客户端业务请求不会在 `call` 时相互穿插提交。

---

## 第三步：PlayerAgent 请求 Scene

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

当前 Coroutine yield。

注意此时：

```text
PlayerAgent Service并没有“死掉”
Worker Thread也没有“卡死”
```

只是这个业务 Coroutine 在等 Response。

---

## 第四步：Scene 处理

**文件：`service/scene/scene.lua`**

消息进入：

```lua
skynet.dispatch("lua", function(session, source, command, ...)
    local fn = assert(CMD[command], ...)
    local result = { fn(...) }

    if session ~= 0 then
        skynet.retpack(table.unpack(result))
    end
end)
```

于是调用：

```lua
CMD.move(player_id, x, y)
```

Scene 完成实时状态提交。

---

## 第五步：AOI Push 使用 `send`

Scene 对周围玩家：

```lua
skynet.send(
    p.agent,
    "lua",
    "push",
    name,
    args
)
```

不等待这些 Agent。

否则一个移动如果周围有 50 个玩家：

```text
call Agent 1
等
call Agent 2
等
...
```

Scene 的移动吞吐量会非常差。

---

## 第六步：Scene Response

`CMD.move`：

```lua
return true, x, y
```

外层 dispatcher：

```lua
skynet.retpack(...)
```

Response 回 PlayerAgent。

Skynet 根据 RPC session 找到之前挂起的 Coroutine，把它恢复。

于是：

```lua
player.x, player.y = rx, ry
```

最后编码客户端 Response。

到这里，一次完整 Actor RPC 才真正结束。

---

# 25. `call` 和 `send` 在 MMO 里怎么选

不要用一句：

```text
需要返回值就call，否则send
```

就结束思考。

这个规则大体没错，但商业 MMO 还应该同时考虑：

```text
一致性
延迟
失败传播
Fan-out
调用链深度
```

可以用下面这个表作为起点。

| 场景 | 常见选择 | 原因 |
|---|---|---|
| 登录加载玩家 | `call` | 必须知道 Load 是否成功 |
| Player → Scene 移动 | `call` | Agent需要Scene提交后的权威结果 |
| Scene → Agent AOI Push | `send` | 广播不应同步等待每个玩家 |
| 写普通日志 | `send` | 不应阻塞业务 |
| 获取必须立即使用的数据 | `call` | 后续逻辑依赖结果 |
| 非关键统计 | `send` | 可异步处理 |
| Logout最终关键保存 | 常需要确认 | 不能简单发完消息就销毁Agent |
| 全服事件通知 | 通常异步 | 避免形成超长同步链 |

---

# 26. 为什么要警惕深 `call` 链

假设以后写成：

```text
PlayerAgent
    call Scene
        call Guild
            call World
                call Storage
                    call Center
```

一次玩家请求的延迟变成：

```text
所有下游等待的总和
```

任何一个节点变慢，都向上传播。

同时你会积累大量等待 Coroutine。

对于 MMO 高频路径，应该特别警惕：

```text
Player -> A -> B -> C -> D
```

这种深同步 RPC。

很多系统更适合：

```text
核心提交：call
派生事件：send
```

例如：

```text
攻击伤害判定
    在Scene本地提交

战斗日志
    send

统计
    send

成就进度
    视一致性要求决定同步或异步
```

---

# 27. Skynet 的“并发”到底来自哪里

把这一课的模型放在一起：

```text
Skynet Process
│
├── Worker 1
├── Worker 2
├── Worker 3
├── ...
│
├── PlayerAgent A
│      └── Lua State A
│
├── PlayerAgent B
│      └── Lua State B
│
├── Scene 1
│      └── Lua State C
│
└── Storage Worker
       └── Lua State D
```

不同 Service 可以被不同 Worker 同时执行：

```text
Worker 1 -> PlayerAgent A
Worker 2 -> Scene 2
Worker 3 -> Storage Worker
```

所以相较于你以前：

```text
一个GameServer主线程
管理整个游戏世界
```

Skynet 更容易把不同状态 Owner 分散到多个 Core。

但：

```text
一个Scene Service
```

本身仍然是单 Actor 热点。

如果一张地图 5000 人，Scene CPU 打满：

```text
thread = 32
```

也不会自动把：

```text
一个 Scene
```

拆成 32 核并行。

这时要解决的是 Actor 粒度：

```text
分线
地图实例化
Region Partition
Scene Sharding
```

这部分第三、第四课再深入。

---

# 28. 和你以前单线程 GameServer 的真正区别

可以把两套模型放一起。

## 传统模型

```text
GameServer Thread

Player 10001
Player 10002
Scene 1
Scene 2
Monster
Guild
Activity

全部在一个主要业务线程里
```

优点：

```text
一致性简单
对象调用直接
业务代码自然
```

缺点：

```text
一个热点可能拖慢整个GameServer
难利用多核
模块故障边界大
```

---

## Skynet 模型

```text
PlayerAgent 10001
PlayerAgent 10002
Scene 1
Scene 2
Storage Worker
Guild Shard
...

由Worker Pool并行调度
```

优点：

```text
状态隔离
容易多核并行
Actor可以分片
生命周期清晰
```

代价：

```text
跨Actor变成消息
必须处理yield时序
需要控制RPC深度
需要设计Actor粒度
状态Owner必须明确
```

所以 Skynet 并不是“自动比 C++ 单线程架构先进”。

真正的价值取决于：

```text
Actor边界是否合理
```

如果把一个原本清晰的 GameServer：

```text
乱拆成几十层 RPC
```

架构只会更难维护。

---

# 29. 当前工程里几个值得保留的设计

## 29.1 Gate / Watchdog / PlayerAgent 分层

```text
Watchdog
    登录前连接控制

PlayerAgent
    登录后的玩家业务
```

登录完成后 Gate 直接 forward 到 PlayerAgent，避免 Watchdog 成为在线数据面的公共中转点。

---

## 29.2 PlayerAgent 与 Connection 分离

PlayerAgent 可以继续存在，而 fd 断开。

因此可以实现：

```text
断线
重连
顶号
Grace Period
```

而不是：

```text
Socket == Player Object生命周期
```

---

## 29.3 PlayerMgr 创建 Agent 时有并发保护

同一玩家不会因为并发登录轻易创建两个 Agent。

---

## 29.4 Scene 实时状态集中提交

Movement、AOI、Combat 高度相关状态保留在同一个 Scene Actor 中。

---

## 29.5 Storage 已经按 Worker Pool 分片

不是一个 DB Actor 扛所有请求。

这些都是很适合继续发展成 MMO Server 的骨架。

---

# 30. 当前工程里仍然是“学习版”的地方

这不是缺陷，而是后续课程要继续补的内容。

例如：

```text
一玩家一Agent的实际内存Benchmark
PlayerAgent定时Dirty Save
关键资产Journal
Service监督与自动恢复
Cluster跨节点
跨Scene迁移协议
Scene Epoch / Generation
统一Trace ID
RPC失败边界
热更与状态迁移
Actor监控与Mailbox报警
```

因此学习时要区分：

```text
机制正确
```

和：

```text
已经达到商业生产完整度
```

当前工程非常适合理解机制，但商业化还要继续做第四课那一层工程能力。

---

# 31. 第二课最容易写错的几种代码

## 错误一：认为 Service 单线程，所以 Handler 中随便 call

```lua
local old = state.value

skynet.call(...)

state.value = old + 1
```

必须检查：

```text
yield期间state.value会不会被改？
```

---

## 错误二：所有模块都拆 Service

```text
BagService
TaskService
EquipService
SkillService
BuffService
```

最终一次玩家操作变成大量 RPC。

优先考虑：

```text
PlayerAgent + 普通Module
```

---

## 错误三：Manager 进入所有高频请求路径

```text
Player -> SceneMgr -> Scene
```

应该尽量：

```text
Player -> Scene
```

Manager 只做生命周期和路由发现。

---

## 错误四：AOI 广播使用 call

```text
Scene
  call 50个Agent
```

Scene 会被最慢的 Agent 拖住。

通知通常使用 `send`。

---

## 错误五：同一状态有两个 Owner

例如：

```text
PlayerAgent认为自己的x/y绝对权威
Scene也认为自己的x/y绝对权威
```

出现冲突时就没有确定规则。

必须定义：

```text
谁判定
谁提交
谁只是Snapshot
什么时候同步
```

---

## 错误六：用一个大 queue 包住整个 Service

这样虽然“看起来安全”，但可能让：

```text
慢DB
```

把：

```text
Ping
重连
Kick
```

全部阻塞。

---

# 32. 学习实验一：自己增加一个 `get_gold`

不要先让 Codex 写。

你自己做一次非常小的 Service RPC，最容易真正建立感觉。

目标文件：

```text
service/player/player_agent.lua
```

增加：

```lua
function CMD.get_gold()
    return player.gold
end
```

然后临时从其它 Service：

```lua
local gold = skynet.call(
    agent,
    "lua",
    "get_gold"
)
```

重点不是功能，而是确认你自己能够解释：

```text
command是什么？
session是什么？
谁retpack？
call为什么能拿到gold？
```

---

# 33. 学习实验二：把 `call` 改成 `send` 看区别

同样的 `get_gold`：

```lua
local gold = skynet.send(...)
```

你会发现：

```text
send不能直接获得目标业务返回值。
```

这能让 `call/send` 的区别从概念变成真正的运行体验。

---

# 34. 学习实验三：故意制造 Coroutine 重入

在测试分支中给 PlayerAgent 写两个测试命令。

伪代码：

```lua
function CMD.test_a()
    local old = test_value

    skynet.sleep(100)

    test_value = old + 1
end
```

另一条：

```lua
function CMD.test_b()
    test_value = test_value + 100
end
```

初始：

```text
test_value = 0
```

让 A 先执行，在 sleep 时执行 B。

观察最终值。

然后用：

```lua
local serial = queue()
```

把两条逻辑放入同一 queue，再观察结果。

这个实验对理解 Skynet 比背 API 有价值得多。

---

# 35. 学习实验四：观察 PlayerMgr 并发登录保护

目标文件：

```text
service/player/player_mgr.lua
```

重点观察：

```lua
return player_lock(player_id)(function()
```

思考：

如果去掉它，同时发起两个：

```text
login player=10001
```

在哪个 yield 点最容易出现两个 Agent？

答案不是在：

```lua
players[player_id]
```

本身。

真正的问题出现在检查之后的：

```lua
skynet.newservice(...)
```

和：

```lua
skynet.call(agent, ... "load")
```

它们让当前 Coroutine 有机会挂起。

---

# 36. 调试时应该观察什么

第二课阶段暂时不用深入 GDB Runtime。

优先使用：

```text
日志
Debug Console
LuaPanda
```

观察三个东西就足够：

```text
Service Address
Coroutine正在等谁
Mailbox是否积压
```

例如：

```text
PlayerAgent等待Scene
Scene是否正在处理大量move
Storage是否成为同步链下游
```

如果某个 Scene 成为 Hot Actor，典型表现不是 mutex deadlock，而是：

```text
Scene Mailbox持续增长
Scene CPU集中
增加Worker数量效果很小
```

因为真正的瓶颈在一个 Actor 内，而不是 Worker 数量不够。

---

# 37. 第二课的完整心智模型

把这一课压缩到一张图：

```text
                       Skynet Process

        ┌──────────────── Worker Pool ────────────────┐
        │                                             │
        │     调度不同 Service 的 Mailbox             │
        │                                             │
        └──────────────────┬──────────────────────────┘
                           │
          ┌────────────────┼─────────────────┐
          │                │                 │
          ▼                ▼                 ▼

    PlayerAgent         Scene            StorageWorker

    Lua State A        Lua State B        Lua State C
        │                  │                  │
        │                  │                  │
    Player State        Entities           DB State
    Connection          Grid               Connection
    Coroutine           AOI                Coroutine
        │                  │
        │ call             │ retpack
        ├─────────────────►│
        │                  │
        │ yield            │
        │                  │
        ◄──────────────────┤
        │ Response         │
        │                  │
       resume              │
```

需要牢牢记住的关系：

```text
Lua Service
    ≈ 一个独立 Lua State

Service之间
    通过消息通信

send
    发送后继续

call
    发送Request + 当前Coroutine yield + 等Response恢复

一个Service不会被两个Worker同时执行Lua代码
    但多个Coroutine可以跨yield交错

skynet.queue
    可以让特定业务段跨yield保持串行

Actor设计的核心
    是状态Owner，不是把所有代码都拆成Service
```

---

# 38. 本课自测题

如果下面的问题可以不看文档自己完整回答，第二课基本就掌握了。

> 下面的参考答案按当前仓库实现编写。行号用于对照本课基线；后续代码变动后，应同时根据完整仓库路径和函数名定位。

### 1

为什么只能说：

> 一个 **Lua Service / snlua Service** 对应一个独立 Lua State

而不能说：

> Skynet 所有 Service 都对应 Lua State？

**参考答案：**`Service` 是 Runtime 运行实体，动态加载的 C Service 也是 Service，但未必嵌入 Lua VM。`snlua` 才是为 Lua Service 提供 Lua State 的 C Service Module：`third_party/skynet/service-src/service_snlua.c:502-511` 的 `snlua_create` 为每个 snlua 实例调用 `lua_newstate`。因此可以说运行中的每个 snlua Service 拥有独立 Lua State，不能把这个结论扩大到 `logger`、`gate` 等 C Service。

### 2

`service/scene/scene.lua` 和运行中的 Scene Service 是什么关系？为什么同一个文件可以创建多个 Scene？

**参考答案：**`service/scene/scene.lua` 是 Service 的加载代码，运行中的 Scene Service 是一次 `skynet.newservice("scene/scene")` 创建出来的 Context、Handle、Mailbox 和 snlua Lua State。`service/scene/scene_mgr.lua:19-21` 先新建实例，再用 `init` 传入 `scene_id`。每调用一次 `newservice` 都会重新加载该文件，文件中 `service/scene/scene.lua:13-18` 的 `scene_id`、`entities`、`visible` 等 local 状态属于新 Lua State，所以多个实例不共享这些 table。

### 3

`movement.lua` 为什么适合普通 Module，而不是 MovementService？

**参考答案：**移动额度、坐标和 AOI 归 Scene 所有，移动校验只是对 Scene 已有状态的本地计算。`lualib/scene/movement.lua:34-57` 不依赖 Skynet，可在 Scene 同一次无 yield 的提交段内执行，也可直接单元测试。如果拆成 MovementService，每次 Move 都要 RPC；Scene 需在 `call` 前读状态、恢复后再校验是否过期，还会增加 Mailbox、序列化和调度成本，却没有获得新的状态所有权边界。

### 4

`skynet.call` 等待结果时，究竟是：

```text
Worker Thread被阻塞？
整个Service被阻塞？
还是当前Coroutine被挂起？
```

**参考答案：**被挂起的是调用 `skynet.call` 的当前 coroutine。`third_party/skynet/lualib/skynet.lua:725-737` 发送带非零 session 的 Request，随后进入 `yield_call`；`third_party/skynet/lualib/skynet.lua:714-722` 记录 session 与 coroutine 的映射并 `coroutine_yield "SUSPEND"`。Worker Thread 会继续调度其他可运行 Service，同一 Service 的其他消息也可以创建 coroutine 执行；等 Response 按 session 匹配到返回时，原 coroutine 才 resume。

### 5

`skynet.send` 为什么适合 AOI Push？

**参考答案：**AOI Push 的语义是把已提交的场景变化投递给观察者，Scene 不需要用 Agent 的返回值决定本次 Move 是否成功。`service/scene/scene.lua:36-40` 用 `send` 转发 Push，对应 `third_party/skynet/lualib/skynet.lua:692-695` 的 session 0 单向消息。如果改成 `call`，Scene 会逐个等 Agent Response，延长提交路径，并可能形成 Scene→Agent→Scene 的同步环。`send` 仍可能造成对方 Mailbox 积压，不代表投递成功就等于客户端已收到。

### 6

为什么 Service 是单线程执行，仍然可能出现 Lost Update？

**参考答案：**Runtime 保证同一 Service 在某一时刻不会被两个 Worker 并行执行，但 Handler 可在 `call`/`sleep`/`wait` 处 yield。例如 A 读到 `gold=100`后 `call` DB，B 在 A 等待期间把 gold 改为 150，A 恢复后仍用旧值写入 110，就会丢掉 B 的更新。这是 coroutine 交错导致的逻辑竞态，不是两条 CPU 指令同时写内存的 data race。

### 7

`skynet.queue` 是 OS mutex 吗？等待 queue 的 Coroutine 会不会占住 Worker Thread？

**参考答案：**它是 Lua 层 coroutine 串行器，不是 OS mutex。`third_party/skynet/lualib/skynet/queue.lua:24-34` 把等待者放入 `thread_queue`，调用 `skynet.wait()` 让出执行；持有者退出最外层临界区时，`third_party/skynet/lualib/skynet/queue.lua:12-19` 用 `skynet.wakeup` 唤醒下一个 coroutine。等待期间 Worker Thread 可以做其他工作。它允许同一 coroutine 重入，`ref` 归零时才交出所有权。

### 8

当前 PlayerMgr 为什么使用 64 路 queue，而不是只写：

```lua
if not players[player_id] then
    players[player_id] = skynet.newservice(...)
end
```

**参考答案：**`players[player_id]` 的检查和赋值之间存在 `newservice` 和 Agent `load` 两个 yield 点，见 `service/player/player_mgr.lua:27-48`。两个同玩家登录 coroutine 都可在赋值前看到 nil，各自创建 Agent。64 路 queue 按 `player_id` 分片，见 `service/player/player_mgr.lua:13-18`；同一玩家必定串行，不同玩家只有哈希冲突时互相等待。这避免了无界增长的“每个历史玩家一把锁”表，也比全局一把 queue 少了无关登录间的阻塞。

### 9

SceneMgr 为什么进入 `create_lock` 后还要再检查一次：

```lua
if scenes[scene_id] then
```

**参考答案：**第一次检查是无竞争时的快速路径。多个 coroutine 可以在第一次检查都看到 nil，然后排队进入 `create_lock`。前一个 coroutine 在锁内经过 `newservice` 和 `call init` 后已经填入 `scenes[scene_id]`；后一个获得 queue 时必须在 `service/scene/scene_mgr.lua:15-18` 再检查，否则仍会重复创建。这是 yield 语义下的 double-check，不是为了 CPU 内存屏障。

### 10

PlayerAgent 和 Scene 都保存 x/y，为什么不算真正的“双权威状态”？谁是实时位置 Owner？

**参考答案：**Scene 是在线实时坐标、移动额度、Grid 成员关系和 Visible Set 的 Owner。`service/scene/scene.lua:193-204` 先在一段无 yield 逻辑中校验并提交这些状态。PlayerAgent 在 `service/player/player_agent.lua:142-147` 等 Scene 成功返回后才更新 x/y，用于下线存档和登录快照。只要关系一直是“Scene 提交结果→PlayerAgent 复制快照”，Agent 不自行接受客户端坐标为权威，就是 Owner 与派生副本，不是两个可互相覆盖的 Owner。

### 11

为什么 Scene 的 `CMD.move` 中间尽量不要插一个：

```lua
skynet.call(nav_service, ...)
```

**参考答案：**`CMD.move` 在 `service/scene/scene.lua:183-249` 中把读取玩家、消耗 Token Bucket、移动 Grid、写坐标、替换 Visible Set 放在一个无 yield 提交段。中间插入 `call` 后，另一条 Scene coroutine 可处理离场、传送、死亡或第二次移动，原 coroutine 手中的 `player`、旧坐标和 `old_visible` 都可能过期。如果导航必须异步，应在 call 前捕获 Scene/Entity generation 和请求版本，恢复后重新查找 Entity 并校验版本，再进入短提交段。

### 12

Manager 最适合承担什么职责？为什么高频请求不应该永远经过 Manager？

**参考答案：**Manager 适合做实例创建/回收、唯一性、稳定 ID 到当前 Service Address 的路由，以及启动阶段的依赖注入。例如 `service/scene/scene_mgr.lua:10-34` 创建 Scene 并把首次 enter 转发过去。玩家进场后，PlayerAgent 在 `service/player/player_agent.lua:95` 缓存 Scene Address，Move 在 `:142` 直接 call Scene。如果每个 10‑20 Hz Move 都经 SceneMgr，Manager 会多一次消息拷贝和 Mailbox 排队，并把原本可并行的多个 Scene 汇聚到一个热点 Actor。

### 13

`player_id` 和 PlayerAgent Service Address 的区别是什么？为什么 Address 不应该持久化？

**参考答案：**`player_id` 是业务稳定标识，跨登录、进程重启和数据库存档仍然有意义。Service Address 是当前 Skynet Runtime 中某个 Context 的句柄，只对当前实例生命周期有效；Agent 下线退出后，下次登录会得到新 Address。`service/player/player_mgr.lua:8` 的映射只存内存，`service/player/player_mgr.lua:52-57` 在 Agent 退出前删除映射。把 Address 写入 DB 会在重启、迁移或句柄复用后变成悬空路由；应持久化 `player_id`，运行时再查 PlayerMgr/Router 获得当前 Address 和 generation。

### 14

如果未来 10 万在线玩家都使用“一玩家一 PlayerAgent”，你最先应该 Benchmark 哪些指标？

**参考答案：**先测“空 Agent”基线：每个 snlua Lua State/Context/Mailbox 的 RSS 增量、创建与销毁速率、启动洪峰耗时和 GC 时间。再加入真实玩家 table、Sproto 对象、离线 Timer 和 pending pushes，测 RSS/Agent 分布、全进程 RSS、GC P95/P99、Timer 成本。运行负载要分 Idle Online、均匀 RPC、同时登录/断线风暴，记录 PlayerAgent Mailbox、消息延迟、Worker CPU 分布和 Storage/Scene 下游等待。只测连接数会漏掉一 Agent 一 Lua State 的主要成本；只测总 QPS 也无法区分 Agent 粒度成本和下游热点。

### 15

画出一次 `move`：

```text
Client -> PlayerAgent -> Scene -> PlayerAgent -> Client
```

并在图上标出：

```text
call
send
yield
retpack
resume
State Owner
```

**参考答案：**

```text
Client
  -- 2-byte big-endian frame + Sproto move Request -->
Gate
  -- PTYPE_CLIENT，fd 被当作转发 session -->
PlayerAgent [持久玩家状态 Owner；x/y 为已提交快照]
  service/player/player_agent.lua:249-280 解包
  service/player/player_agent.lua:182-190 进入 serial
  service/player/player_agent.lua:132-142 校验参数并 call Scene
  -- call: Request(session=N) --> Scene
  -- yield: 只挂起当前 PlayerAgent coroutine
Scene [实时坐标、Token Bucket、entities/Grid/visible Owner]
  service/scene/scene.lua:183-204 无 yield 提交
  -- send(session=0) --> 可见 PlayerAgent 的 AOI Push
  service/scene/scene.lua:206-247 维护可见关系并投递 Push
  service/scene/scene.lua:249 return
  service/scene/scene.lua:330-336 retpack(Response, session=N)
PlayerAgent
  -- Response 匹配 session=N，coroutine resume
  service/player/player_agent.lua:143-147 只在成功后更新快照
  service/player/player_agent.lua:277-279 编码 Sproto Response
  --> Gate/socket send queue --> Client
```

Scene 推送给观察者的 `send` 不在 Client→PlayerAgent→Scene→PlayerAgent→Client 这条 RPC Response 主线上，它是 Scene 提交后的旁路单向消息。客户端 Response 也不是 Scene 直接发送；Scene 先 `retpack` 唤醒请求方 PlayerAgent，再由 PlayerAgent 完成 Sproto Response 编码与 socket 写入。

---

# 39. 第二课完成标准

进入第三课之前，你应该已经可以独立做到：

1. 从零写一个普通 Lua Service；
2. 使用 `newservice` 和 `uniqueservice` 创建 Service；
3. 理解 Service Address 的生命周期；
4. 写出 `skynet.dispatch("lua", ...)`；
5. 正确使用 `call / send / retpack`；
6. 看到一段 Handler 能主动找出全部 yield 风险；
7. 知道什么时候应该使用 `skynet.queue`；
8. 能解释当前 PlayerMgr 和 SceneMgr 为什么需要 queue；
9. 能明确 PlayerAgent 与 Scene 的状态所有权；
10. 能自己画出登录链和 move 链；
11. 能判断一个新功能应该做成 Service，还是 Player/Scene 内部 Module；
12. 能解释“增加 Worker 数量为什么解决不了单 Scene Hot Actor”。

达到这个程度，才算真正掌握了 Skynet 的业务开发基础。

---

# 40. 下一课：Scene、九宫格 AOI 与 Combat

第三课不再重复 Service API，而是在本课的基础上进入 MMO 最核心的实时场景系统。

会重点解决：

```text
Scene为什么保持单Actor提交
Grid如何组织空间对象
九宫格AOI为什么有效
GridSize和ViewRadius怎么选
Enter / Leave / Move如何维护可视集合
Monster怎么进入AOI
Combat为什么放在Scene
Scene Tick怎么设计
Scene CPU打满后怎么分片
AOI Benchmark应该怎么做
```

到第三课结束，整个工程会从“会使用 Skynet Service”进入“可以真正承载 MMO 场景业务”的阶段。

第四课再完成商业化必需的：

```text
Cluster
跨服
DB持久化策略
热更
GC与内存
监控
容灾
性能优化
生产架构演进
```

这样四课的学习链才是完整的：

```text
第一课
Skynet怎么启动
        ↓
第二课
Skynet业务怎么组织
        ↓
第三课
MMO实时世界怎么实现
        ↓
第四课
怎么把它变成商业级MMO Server
```
