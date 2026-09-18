# Skynet MMO 学习课程第三课：Scene、九宫格 AOI、Monster 与 Combat

> **工程基线**：`simbiwu/skynet-mmo-learning` 当前 `main` 分支
> **Skynet 基线**：Skynet v1.8.0 + Skynet Bundled Modified Lua 5.4.7
> **运行环境**：Linux / WSL2
> **前置课程**：第一课《启动链源码导读》、第二课《Service 模型、消息通信与 MMO Actor 架构》
> **本课目标**：真正进入 MMO 的实时世界。学完以后，你应该能够独立实现一个可工作的 Scene Service，并能解释九宫格 AOI、玩家移动、怪物、战斗、广播、Tick、Hot Scene 与分片设计。

---

# 0. 第三课到底要解决什么问题

前两课解决了：

```text
第一课
Skynet 怎么启动

        ↓

第二课
Skynet 业务怎么组织
Service 怎么通信
状态归谁
Coroutine 为什么会产生时序问题
```

第三课开始，不再停留在 Runtime 和 Actor 抽象层面，而是进入 MMO Server 最核心的实时业务：

```text
Scene
AOI
Move
Monster
Combat
Broadcast
Tick
```

对于你熟悉的传统战法道 MMO ARPG，这些东西其实很熟悉。

以前的 C++ GameServer 里，大概会存在：

```cpp
class Scene {
public:
    void Enter(Player* p);
    void Leave(Player* p);
    void Move(Player* p, int x, int y);
    void Attack(Player* p, Entity* target);
    void Update(uint64_t now);

private:
    PlayerMap players_;
    MonsterMap monsters_;
    GridMap aoi_;
};
```

Skynet 并没有把这套业务推翻。

真正的变化是：

```text
以前：
Scene 是 GameServer 中的一个对象

Skynet：
Scene 变成一个独立 Service / Actor
```

所以第三课本质是在回答：

> **如何把传统单线程 C++ Scene，迁移成一个正确的 Skynet Scene Actor。**

本课围绕这些问题展开：

1. 为什么 Scene 适合做 Service；
2. Scene 应该拥有哪些实时状态；
3. 为什么 AOI、Combat、Monster 不应该继续拆成独立 Service；
4. 九宫格 AOI 为什么有效；
5. `grid_size` 与 `view_radius` 应该如何理解；
6. `Enter / Leave / Move` 时可视集合怎样维护；
7. Monster 怎样进入同一套 AOI；
8. Combat 为什么应尽量在 Scene 内提交；
9. Scene Tick 应该怎样设计；
10. 单 Scene CPU 打满后怎样扩展；
11. AOI Benchmark 应该怎样做才有意义。

---

# 1. 本课涉及的仓库文件

这一课主要使用当前仓库中的这些文件。

## Scene Service

```text
service/scene/scene_mgr.lua
service/scene/scene.lua
```

## Scene 内部普通 Lua Module

```text
lualib/scene/aoi_grid.lua
lualib/scene/movement.lua
lualib/scene/combat.lua
```

## 静态配置

```text
lualib/config/game_data.lua
```

## PlayerAgent

```text
service/player/player_agent.lua
```

## 单元测试

```text
tests/unit/test_aoi_grid.lua
tests/unit/test_movement.lua
tests/unit/test_combat.lua
tests/unit/run.lua
```

## Benchmark

```text
tests/benchmark/aoi_bench.lua
```

这一课要特别注意一个设计思想：

```text
Scene 是 Service

AOI Grid 不是 Service
Movement 不是 Service
Combat 不是 Service
```

这是第二课“Service 粒度”原则在真正 MMO 场景中的第一次落地。

---

# 2. 为什么 Scene 特别适合做成一个 Service

一个实时地图通常同时管理：

```text
Player
Monster
NPC
Position
AOI
Skill
Buff
Combat
Drop
AI
Timer
```

这些状态之间交互非常频繁。

例如一次攻击：

```text
Player Attack
    ↓
检查玩家是否还在场景
    ↓
查目标
    ↓
检查距离
    ↓
计算伤害
    ↓
修改目标 HP
    ↓
判断死亡
    ↓
更新 Entity / AOI
    ↓
广播 HP
    ↓
广播死亡
```

如果把它拆成：

```text
SceneService
    ↓ call
AoiService
    ↓ call
CombatService
    ↓ call
MonsterService
```

看起来“很服务化”，对于 ARPG 往往反而是错误设计。

原因是这些逻辑属于同一个强耦合实时事务。

拆 Service 会带来：

```text
多次消息序列化
多次 Mailbox 排队
多次 Coroutine yield
更多失败点
更多状态版本校验
更多跨 Actor 一致性问题
```

因此先记住一个原则：

> **高频、强耦合、需要连续提交的实时状态，优先放在同一个 Scene Actor 内。**

这与你以前的 C++ GameServer 思路非常接近。

你以前也不会把：

```text
AOI线程
Combat线程
Monster线程
Buff线程
```

拆开，然后让一次攻击在几个线程之间做同步 RPC。

Skynet 也不应该为了 Actor 而过度 Actor 化。

---

# 3. Scene Service 与普通 Module 的边界

当前仓库：

```text
service/scene/scene.lua
```

是 Service。

而：

```text
lualib/scene/aoi_grid.lua
lualib/scene/movement.lua
lualib/scene/combat.lua
```

只是普通 Lua Module。

可以理解为：

```text
Scene Service
│
├── Entity State
├── Visible Set
├── Grid 实例
│
├── movement.lua
│   └── 移动算法
│
├── combat.lua
│   └── 战斗算法
│
└── aoi_grid.lua
    └── 空间索引算法
```

这些 Module 没有独立 Service Address，也没有自己的 Mailbox。

它们只是：

```text
Scene 的内部实现
```

这和传统 C++ 很像：

```cpp
class Scene {
    AoiGrid grid_;
    MovementValidator movement_;
    CombatCalculator combat_;
};
```

判断一个组件该不该拆 Service，可以继续使用第二课的标准：

> **如果它只是在操作 Scene 已经拥有的数据，而且没有独立生命周期、独立状态所有权或独立扩展价值，通常不应该成为 Service。**

---

# 4. SceneMgr 与 Scene：Manager 只负责生命周期和路由

文件：

```text
service/scene/scene_mgr.lua
```

当前核心结构：

```lua
local scenes = {}
local create_lock = queue()
```

含义：

```text
scene_id
    ↓
Scene Service Address
```

例如：

```text
1 → :00000031
2 → :00000042
3 → :00000057
```

SceneMgr 负责：

```text
Scene 是否已存在
创建 Scene
保存 scene_id → address
把 Enter 请求路由到目标 Scene
```

它不应该长期承载高频 Move/Attack 数据面。

理想高频路径是：

```text
PlayerAgent
    ↓
直接持有 scene_service Address
    ↓
Scene
```

而不是：

```text
PlayerAgent
    ↓
SceneMgr
    ↓
Scene
```

每次移动都多经过一个 Manager Mailbox。

这就是第二课里“Manager 不要进入高频数据面”的具体落地。

---

# 5. Scene 的核心状态

文件：

```text
service/scene/scene.lua
```

当前核心状态可以抽象为：

```lua
local scene_id
local scene_cfg
local grid
local entities = {}
local visible = {}
local tick_count = 0
```

分别代表：

```text
scene_id
当前 Scene 实例 ID

scene_cfg
本 Scene 的只读配置

grid
空间索引

entities
场景内所有实时实体

visible
每个玩家当前可见的 Entity Set

tick_count
Scene Tick 计数
```

这里最重要的是：

```text
entities
visible
grid
```

三者不是重复数据。

它们分别解决：

```text
entities → Entity 权威状态

grid     → 空间候选查询

visible  → 客户端增量可见关系
```

---

# 6. entities：Scene 的权威实体表

当前：

```lua
local entities = {}
```

内部 Key 使用：

```text
p:10001
m:100001
```

对应代码：

```lua
local function ekey(entity_type, id)
    return (entity_type == TYPE_PLAYER and "p:" or "m:") .. tostring(id)
end
```

这样即使：

```text
player_id = 100001
monster_id = 100001
```

也不会冲突。

Player Entity 大致类似：

```lua
{
    entity_type = TYPE_PLAYER,
    id = 10001,
    name = "Player",
    level = 10,
    hp = 100,
    max_hp = 100,
    agent = player_agent,
    x = 100,
    y = 100,
    move_state = ...
}
```

Monster：

```lua
{
    entity_type = TYPE_MONSTER,
    id = 100001,
    name = "Green Slime",
    x = 104,
    y = 100,
    hp = 50,
    max_hp = 50,
    spawn_cfg = cfg,
}
```

注意：

```text
PlayerAgent 中的 player
```

和：

```text
Scene 中的 Player Entity
```

不是同一个对象。

---

# 7. PlayerAgent 与 Scene 为什么都保存坐标

当前：

```text
service/player/player_agent.lua
```

有：

```lua
player.x
player.y
```

Scene 中也有：

```lua
entity.x
entity.y
```

看起来像两份权威状态，实际上角色不同。

## Scene

负责：

```text
实时权威坐标
移动是否合法
AOI
攻击距离
怪物交互
Scene规则
```

## PlayerAgent

保存：

```text
可持久化 Snapshot
```

正确移动顺序：

```text
Client
  ↓
PlayerAgent
  ↓ call
Scene.move
  ↓
Scene 校验并提交
  ↓
返回最终 x/y
  ↓
PlayerAgent 更新 snapshot
```

当前 `service/player/player_agent.lua` 中：

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
    return { code = 3, message = rx or "MOVE_FAILED" }
end

player.x, player.y = rx, ry
```

这个顺序是对的。

不能改成：

```lua
player.x = x
player.y = y

local ok = skynet.call(scene, "lua", "move", ...)
```

否则 Scene 拒绝后：

```text
Agent Snapshot = 新位置
Scene Position  = 旧位置
```

状态就裂开了。

---

# 8. 为什么需要 AOI

假设完全不用空间索引。

一个玩家移动一次，你想知道附近是谁，最直接：

```lua
for _, entity in pairs(entities) do
    check_distance(player, entity)
end
```

如果地图：

```text
N = 10000 Entity
```

每次 Move：

```text
O(N)
```

如果每秒几千次移动，就会产生大量无意义距离判断。

AOI 的核心不是“九宫格”三个字。

真正思想是：

> **先用廉价空间索引缩小 Candidate Set，再对候选集合做精确距离过滤。**

---

# 9. Grid AOI 的结构

文件：

```text
lualib/scene/aoi_grid.lua
```

核心数据：

```lua
return setmetatable({
    grid_size = grid_size,
    cells = {},
    entity_cell = {},
}, Grid)
```

有两个索引。

## cells

```text
"gx:gy"
    ↓
这个格子有哪些 Entity
```

例如：

```lua
cells["5:5"] = {
    ["p:10001"] = true,
    ["p:10002"] = true,
    ["m:100001"] = true,
}
```

## entity_cell

反向索引：

```text
Entity
    ↓
当前在哪个 Cell
```

例如：

```lua
entity_cell["p:10001"] = "5:5"
```

为什么需要反向索引？

因为 Move/Remove 时如果没有它，就需要搜索 Cell 才知道 Entity 原来在哪。

有了：

```text
entity → cell
```

移动和删除就可以近似 O(1) 定位。

---

# 10. 世界坐标如何映射到 Grid 坐标

当前代码：

```lua
function Grid:coords(x, y)
    return math.floor(x / self.grid_size),
           math.floor(y / self.grid_size)
end
```

当前配置：

```text
grid_size = 20
```

那么：

```text
x = 0 ~ 19  → gx = 0
x = 20 ~ 39 → gx = 1
x = 40 ~ 59 → gx = 2
```

例如：

```text
Player (105,108)

gx = floor(105/20) = 5
gy = floor(108/20) = 5
```

最终：

```text
Cell = (5,5)
```

你以前项目是一格代表 1 个坐标。

那也是 Grid 思想，只是粒度极细。

如果视野只覆盖附近 1 坐标，3×3 足够。

但如果视野半径是 20 坐标，一格一坐标就需要检查大量 Cell。

因此更常见的是：

```text
一个 Cell 覆盖一块坐标区域
```

---

# 11. 为什么当前工程只查 3×3 就够

文件：

```text
lualib/config/game_data.lua
```

当前：

```lua
grid_size = 20
view_radius = 18
```

Scene 初始化还有：

```lua
assert(scene_cfg.grid_size >= scene_cfg.view_radius,
    "this 3x3 AOI lesson requires grid_size >= view_radius")
```

这是当前 3×3 查询成立的关键前提。

当：

```text
grid_size >= view_radius
```

一个以玩家为圆心、半径为 `view_radius` 的视野圆，不可能跨过超过一层相邻 Cell。

所以只需要：

```text
自己所在 Cell
+
周围 8 个 Cell
```

示意：

```text
+---------+---------+---------+
|         |         |         |
|   NW    |    N    |   NE    |
|         |         |         |
+---------+---------+---------+
|         |         |         |
|    W    | PLAYER  |    E    |
|         |         |         |
+---------+---------+---------+
|         |         |         |
|   SW    |    S    |   SE    |
|         |         |         |
+---------+---------+---------+
```

---

# 12. 九宫格不是最终可视范围

九宫格只产生：

```text
Candidate Set
```

不是：

```text
Visible Set
```

因为 3×3 是矩形区域，而真实视野一般是圆形距离。

当前 Scene：

```lua
local candidates = grid:query_3x3(e.x, e.y)
```

之后继续：

```lua
combat.distance_sq(
    e.x,
    e.y,
    other.x,
    other.y
) <= radius_sq
```

完整流程：

```text
全部 Entity

    ↓ Grid索引

3×3 Candidate

    ↓ 精确距离

真正 Visible Entity
```

这就是典型的 Broad Phase + Narrow Phase 思路。

---

# 13. 为什么距离判断用平方

文件：

```text
lualib/scene/combat.lua
```

代码：

```lua
function M.distance_sq(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by
    return dx * dx + dy * dy
end
```

判断：

```lua
distance_sq <= radius * radius
```

而不是：

```lua
math.sqrt(dx * dx + dy * dy) <= radius
```

因为 AOI 是高频路径，只做大小比较时根本不需要真正求距离。

这类小优化在热路径里很常见。

---

# 14. Grid insert / remove / move

文件：

```text
lualib/scene/aoi_grid.lua
```

## insert

```text
Entity
  ↓
计算 Cell
  ↓
加入 cells[cell]
  ↓
记录 entity_cell
```

Lua table 平均 Hash 操作近似 O(1)。

## remove

通过：

```text
entity_cell[entity_key]
```

直接找到 Cell，再删除。

如果 Cell 已空：

```lua
if next(cell) == nil then
    self.cells[key] = nil
end
```

及时清掉空格子。

## move

核心：

```lua
if old_key == new_key then
    return false
end
```

如果角色位置变了，但仍在同一 Cell：

```text
Grid Index 不需要改变
```

这是很重要的优化。

---

# 15. 同 Cell 移动为什么仍然要重新计算 Visible

Grid 不变：

```text
不代表视野不变
```

例如玩家从一个 Cell 左边走到右边，虽然仍然属于同一个 Cell，但与附近 Entity 的真实距离已经变化。

因此当前 Scene 每次成功 Move 后仍然：

```lua
local new_visible = collect_visible(player)
```

这保证：

```text
空间索引只负责候选
真实距离仍然负责最终可见性
```

---

# 16. visible：为什么要保存每个玩家当前看见什么

Scene：

```lua
local visible = {}
```

结构：

```text
visible[player_id]
    ↓
set(entity_key = true)
```

例如：

```lua
visible[10001] = {
    ["p:10002"] = true,
    ["m:100001"] = true,
}
```

为什么不每次移动都把全部附近 Entity 重新发给客户端？

因为真正需要的是增量：

```text
谁刚进入
谁刚离开
谁仍然留在视野
```

于是有：

```text
Old Visible
New Visible
```

做集合差：

```text
Old - New = Leave
New - Old = Enter
Old ∩ New = Still Visible
```

这就是 AOI 广播最核心的逻辑。

---

# 17. Player Enter 完整流程

文件：

```text
service/scene/scene.lua
```

`CMD.enter(info)`：

```text
1. 构造 Player Entity
2. 建立 movement state
3. entities[key] = player
4. grid:insert
5. collect_visible
6. visible[player_id] = now_visible
7. 生成初始 snapshot
8. 通知附近旧玩家：新玩家出现
9. 返回 snapshot 给 PlayerAgent
```

示意：

```text
PlayerAgent
   |
   | call Scene.enter
   v
Scene

Create Entity
   ↓
Insert Grid
   ↓
Query 3x3
   ↓
Exact Distance
   ↓
Visible Set
   ├── snapshot → 新玩家
   └── entity_enter → 附近旧玩家
```

---

# 18. 为什么 Enter 要维护双向可视关系

假设 A 已经在地图，B 刚进入，并且互相可见。

必须同时成立：

```text
B visible A
A visible B
```

当前代码先：

```lua
visible[player.id] = now_visible
```

建立 B 的集合。

然后：

```lua
visible[other.id][key] = true
```

把 B 写入 A 的集合。

如果只更新一边，就会出现：

```text
B 看得到 A
A 看不到 B
```

这是 AOI 很常见的状态不对称 Bug。

---

# 19. Player Leave 完整流程

`CMD.leave(player_id)`：

```text
获取 old_visible
    ↓
遍历所有可见玩家
    ↓
从对方 visible 中删除自己
    ↓
向对方 push entity_leave
    ↓
删除自己的 visible
    ↓
Grid remove
    ↓
entities remove
```

为什么不是一上来就：

```lua
entities[key] = nil
```

因为清理过程中还需要：

```text
知道自己是谁
知道邻居是谁
清理双向关系
发送离场通知
```

所以通常先断关系，最后销毁 Entity。

---

# 20. Player Move：本课最重要的函数

文件：

```text
service/scene/scene.lua
```

当前 `CMD.move` 顺序：

```text
查 Player Entity
    ↓
参数校验
    ↓
movement.try_move
    ↓
取 old_visible
    ↓
grid.move
    ↓
更新权威 x/y
    ↓
collect_visible
    ↓
visible = new_visible
    ↓
处理 Leave
    ↓
处理 Enter
    ↓
对仍可见玩家广播 Move
    ↓
返回最终位置
```

这里最值得学习的不是 Lua 代码，而是：

> **从移动校验到 AOI 提交结束，中间没有 yield。**

---

# 21. 为什么 Move 提交段不能随便插入 skynet.call

当前：

```text
movement.try_move
grid.move
position update
visible diff
push
```

中间没有：

```text
skynet.call
skynet.sleep
skynet.wait
```

所以：

```text
读旧状态
→ 校验
→ 提交新状态
→ 更新AOI
```

在同一 Scene Lua State 里连续完成。

如果改成：

```lua
local ok = movement.try_move(...)

local walkable = skynet.call(
    nav_service,
    "lua",
    "check",
    x,
    y
)

grid:move(...)
player.x = x
```

那么 `call` 时 Coroutine yield。

等待期间可能发生：

```text
玩家离场
玩家再次移动
玩家切Scene
Entity已经销毁或重建
```

恢复以后继续使用旧假设就有风险。

这正是第二课：

> **yield 是状态可能失效边界**

在实时 Scene 中最典型的案例。

---

# 22. 如果导航很复杂怎么办

## 方案一：Nav Data 本地只读

最好。

```text
Scene
   ↓
本地 NavData
```

Move 判断直接函数调用。

优点：

```text
无RPC
无yield
低延迟
状态简单
```

## 方案二：C/C++ Module

如果碰撞/寻路很重：

```text
Lua Scene
   ↓
C/C++ Nav Module
```

仍是本地调用，不是 Service RPC。

这正是 ARPG 中 Lua+C/C++ 混合的典型使用方式。

## 方案三：异步 NavService

只有确实需要计算池时才考虑。

那就需要携带：

```text
request_seq
entity_generation
scene_epoch
source_position
```

Response 回来后必须重新验证。

---

# 23. movement.lua 为什么故意不依赖 Skynet

文件：

```text
lualib/scene/movement.lua
```

它是普通 Module，没有：

```lua
require "skynet"
```

这是值得保留的设计。

好的结构应尽量把：

```text
纯业务算法
```

与：

```text
Actor Runtime
```

解耦。

所以：

```text
movement.lua
combat.lua
aoi_grid.lua
```

都能直接做普通 Lua 单元测试。

---

# 24. 当前移动校验：Token Bucket

`movement.lua` 中每个玩家维护：

```lua
{
    x = x,
    y = y,
    move_credit = ...,
    last_move_tick = ...,
}
```

思路：

```text
玩家拥有“可移动距离额度”

时间经过
    ↓
恢复额度

移动
    ↓
消耗额度
```

当前配置：

```text
move_speed = 10
move_burst_seconds = 1
```

最大 Credit：

```text
10 × 1 = 10
```

相比简单：

```text
本包移动距离 <= 固定值
```

Token Bucket 更适合处理网络包并非严格等间隔到达的情况。

---

# 25. 为什么移动权威必须在 Scene

Client 可以预测，但服务端权威不能相信 Client。

PlayerAgent 也不是最佳 Owner。

因为 Scene 才拥有：

```text
地图边界
实时坐标
AOI
碰撞
怪物
Scene规则
```

所以：

```text
Move Authority = Scene
```

PlayerAgent 只是：

```text
请求者 + 持久化 Snapshot
```

---

# 26. Monster 为什么进入同一个 Grid

当前 Monster：

```lua
grid:insert(key, monster.x, monster.y)
```

和 Player 使用同一空间索引。

这是合理的。

统一后：

```text
AOI
攻击
技能范围
附近目标
AI找玩家
```

都可以先复用同一个 Broad Phase。

当前用：

```text
entity_type
```

区分：

```text
Player
Monster
```

以后可以继续扩：

```text
NPC
Drop
Pet
Trap
Projectile
```

是否所有类型都放同一索引，要看业务查询模式和数量。

---

# 27. Monster Spawn

文件：

```text
service/scene/scene.lua
```

`spawn_monster(cfg)`：

```text
构造 Monster
    ↓
entities
    ↓
grid insert
    ↓
collect_visible(monster)
    ↓
找到附近 Player
    ↓
更新 Player visible
    ↓
push entity_enter
```

从本质看：

```text
Monster Spawn
=
Entity Enter Scene
```

以后可以把 Entity Lifecycle 抽象得更统一，但学习阶段直接写清流程更重要。

---

# 28. 为什么不应该“一怪一个 Service”

假设场景里：

```text
5000 Monster
```

如果：

```text
1 Monster = 1 Service
```

AI 可能变成：

```text
MonsterService
    ↓ call
Scene
    ↓
查玩家
    ↓ response
MonsterService
    ↓ call
Combat
```

消息量巨大。

而 Monster 与 Scene 强耦合：

```text
位置
AOI
仇恨
目标
技能
死亡
刷新
```

因此 ARPG 中通常更合理的是：

```text
Scene owns Monster
```

Monster 只是 Scene 内 Entity。

AI 是 Scene 内部 Module / 状态机。

---

# 29. Combat 为什么放在 Scene

当前：

```text
lualib/scene/combat.lua
```

只负责算法。

真正攻击提交：

```text
service/scene/scene.lua
CMD.attack
```

攻击依赖：

```text
攻击者是否存在
目标是否存在
距离是否合法
目标HP
观察者
死亡
刷新
```

这些状态都属于 Scene。

因此把 Combat Commit 放 Scene 内，可以避免跨 Service Transaction。

---

# 30. 当前 Attack 完整流程

```text
PlayerAgent
    |
    | call Scene.attack
    v

Scene

find attacker
    ↓
find monster
    ↓
check range
    ↓
calc damage
    ↓
modify HP
    ↓
collect observers
    ↓
push HP
    ↓
if dead
    ├─ remove visible
    ├─ push monster_dead
    ├─ push entity_leave
    ├─ grid remove
    ├─ entities remove
    └─ schedule respawn
```

这是一条典型 Scene 内提交链。

---

# 31. Combat Range 与 AOI Range 不是一回事

当前：

```text
view_radius = 18
attack_range = 5
```

`view_radius`：

```text
决定客户端应该知道哪些 Entity
```

`attack_range`：

```text
决定能不能攻击
```

不要因为目标存在于 `visible[player_id]` 就直接判定能攻击。

Visible Set 是：

```text
派生缓存
```

攻击合法性应该重新基于实时位置判断。

---

# 32. 为什么 Broadcast 用 send 而不是 call

Scene Push 当前：

```lua
skynet.send(
    p.agent,
    "lua",
    "push",
    name,
    args
)
```

原因：

```text
Scene 不需要等待每个客户端确认“我收到广播了”
```

如果改成：

```lua
for player in observers do
    skynet.call(player.agent, ...)
end
```

一个慢 Agent 就可能拖慢整个 Scene。

正确思路：

```text
Scene Commit
    ↓
send Push
    ↓
继续处理
```

---

# 33. send 不是“零成本”

虽然 `skynet.send` 不 yield，但它仍然包含：

```text
消息构造
序列化
Mailbox入队
目标Service调度
协议编码
Socket发送
```

所以：

```text
1000玩家同屏
每100ms广播位置
```

仍然可能产生非常高的消息量。

AOI 最大价值之一就是：

```text
限制 Fan-out
```

---

# 34. Visible Set 也有内存成本

假设：

```text
10000 Player
平均每人可见100 Entity
```

关系数约：

```text
1,000,000
```

而 Lua table 每个 Key/Value 都有明显额外内存。

玩家高度聚集时，如果大家互相可见，Visible 关系甚至趋近：

```text
O(N²)
```

这就是城战/沙巴克场景容易出问题的原因之一。

所以 AOI Benchmark 不能只看查询 QPS，还要看：

```text
Visible关系数量
Lua Heap
GC
消息量
```

---

# 35. 九宫格复杂度应该怎样理解

Grid Query 固定扫描 9 个 Cell，看起来像 O(1)。

但真正成本是：

```text
O(9个Cell里的Entity总数)
```

设候选数为 K：

```text
query ≈ O(K)
```

如果实体均匀：

```text
K 很小
```

效果很好。

如果所有玩家挤在一个 Cell：

```text
K ≈ N
```

就会退化接近全表扫描。

所以九宫格不是魔法。

它依赖：

```text
GridSize
ViewRadius
Entity密度
空间分布
```

---

# 36. GridSize 怎么选

## 太小

例如：

```text
grid_size = 5
view_radius = 20
```

视野会跨很多 Cell。

至少要向外扩：

```text
ceil(20/5) = 4
```

查询范围：

```text
(2×4+1)² = 81 Cell
```

## 太大

例如：

```text
grid_size = 100
view_radius = 20
```

虽然 3×3 足够，但单 Cell 可能包含大量无关 Entity。

Candidate 过多，精确距离过滤成本又会升高。

所以 GridSize 本质是平衡：

```text
Cell数量
vs
每Cell实体数
```

---

# 37. 当前工程为什么选 20 / 18

```text
grid_size = 20
view_radius = 18
```

教学上最大的好处是：

```text
grid_size >= view_radius
```

所以 3×3 逻辑非常清晰。

但商业项目不要死记：

```text
GridSize 必须等于 ViewRadius
```

真正应该：

```text
用真实地图密度做Benchmark
```

例如比较：

```text
GridSize = R/2
GridSize = R
GridSize = 2R
```

看：

```text
Avg Candidate
P99 Candidate
Move QPS
GC
内存
```

---

# 38. 你以前“一格=一个坐标”的方案怎么理解

这个方案不是错。

如果：

```text
坐标范围不大
实体数不高
有效视距很小
```

完全可以。

但如果真实视野半径是：

```text
10 / 20 / 30坐标
```

一格一坐标就不能只遍历周围 3×3。

需要遍历更多 Cell。

所以更常见的是：

```text
一个Grid覆盖多个坐标单位
```

减少索引格数与查询 Cell 数。

---

# 39. AOI 还有哪些常见方案

## Grid / 九宫格

优点：

```text
简单
增删快
移动快
实现稳定
```

非常适合传统 ARPG。

## 十字链表 / Orthogonal List

按 X、Y 维护有序关系，移动时更新邻接位置。

优点是范围增量更新可以很高效，但实现复杂度更高。

## Sweep and Prune

常见于物理碰撞 Broad Phase，通过轴排序减少候选。

## Quadtree

适合密度极不均匀的大空间。

缺点：动态 Entity 高频移动时维护更复杂。

## KD-Tree / R-Tree

更适合最近邻或相对静态空间索引。

对于大量实时移动 Entity，Grid 往往更直接。

对于你熟悉的传奇类 MMO：

```text
规则地图
高频移动
大量增删
```

Grid 是很实际的选择。

---

# 40. Scene Tick 是什么

当前 Scene：

```lua
local function tick()
    tick_count = tick_count + 1
    skynet.timeout(10, tick)
end

skynet.timeout(10, tick)
```

Skynet：

```text
100 tick = 1秒
```

所以：

```text
10 tick = 100ms
```

也就是 10Hz Scene Tick。

当前只计数。

真实 MMO 中可能包含：

```text
Monster AI
Buff Tick
Skill Tick
Drop Expire
Scene Event
Area Trigger
```

---

# 41. 不要把所有 Entity 每 Tick 全扫一遍

最简单：

```lua
for _, entity in pairs(entities) do
    entity:update()
end
```

但如果：

```text
10000 Entity
10Hz
```

就是：

```text
100000 Entity Update / 秒
```

很多 Entity 实际没有任何事情。

常见优化：

```text
Active Set
Timer Wheel
Deadline Queue
Budgeted Tick
事件驱动
```

例如：

```text
Monster AI → 只更新Active Monster
Buff到期    → Timer/时间轮
Respawn     → Timer
```

而不是每 Tick 全扫。

---

# 42. Timer 与 Tick 怎么选

怪物复活当前：

```lua
skynet.timeout(cfg.respawn_ticks, function()
    spawn_monster(cfg)
end)
```

很合理。

因为复活属于：

```text
明确未来时点的离散事件
```

没必要 Tick 每100ms扫描所有死亡怪物。

可以记成：

```text
连续周期逻辑 → Tick
离散到期事件 → Timer / 时间轮
```

---

# 43. Scene 单线程是否够用

一个 Scene Service：

```text
同一时刻只有一个 Worker 执行这个 Lua State
```

所以：

```text
一个 Scene Actor
=
单核热点上限
```

增加：

```text
thread = 32
```

可以让：

```text
Scene A
Scene B
Scene C
```

并行。

不能让：

```text
Scene A
```

自己同时使用 8 个 Worker 执行 Lua。

---

# 44. 为什么普通 MMO 仍适合一个 Scene 一个 Actor

因为一般会存在很多天然实例：

```text
新手村1
新手村2
主城1
主城2
副本1001
副本1002
副本1003
```

每个 Scene 一个 Service。

这样不同地图天然可以并行。

这比传统：

```text
整个 GameServer 单线程
```

的并行粒度更细。

---

# 45. 真正危险的是 Hot Scene

例如：

```text
沙巴克
跨服城战
世界Boss
万人主城
```

单个 Scene 可能成为 Hot Actor。

典型症状：

```text
Scene CPU高
Mailbox持续增长
Move延迟上涨
AOI广播暴涨
GC频率上升
```

增加 Worker 数通常不会解决单 Scene 自身瓶颈。

---

# 46. Hot Scene 第一层优化：先 Profile，不要急着 Region 化

先确认 CPU 花在哪：

```text
AOI Candidate过多
广播Fan-out过大
Monster AI全扫描
Lua临时Table太多
Skill/Buff Tick过密
同步RPC
字符串/协议编码
```

很多时候先把：

```text
O(N)
```

优化为：

```text
O(K)
```

就够了。

---

# 47. 第二层：分线 / 实例化

例如：

```text
主城1线
主城2线
主城3线
```

每条线一个 Scene Service。

优点：

```text
架构简单
几乎无跨Region同步
```

这是比 Region Partition 更优先考虑的扩展手段。

---

# 48. 第三层：Region Partition

真正超大世界可能：

```text
World
  |
  + Region 0
  + Region 1
  + Region 2
  + Region 3
```

每个 Region 一个 Scene Service。

优点：

```text
可以跨核
```

代价：

```text
边界AOI
Ghost Entity
跨区技能
玩家迁移
消息顺序
Epoch
Generation
```

复杂度会明显提高。

---

# 49. Region 边界为什么难

A 在 Region 1 边界，B 在 Region 2，但两人只相距 5 米。

即使属于两个 Service，也必须互相可见。

于是可能需要：

```text
Region1 保存 B 的只读 Ghost
Region2 保存 A 的只读 Ghost
```

攻击时还要决定：

```text
真正Authority是谁
```

这就是为什么 Region 化不能过早做。

---

# 50. Scene Transfer 为什么需要 Epoch / Generation

玩家从：

```text
Scene A
  ↓
Scene B
```

期间旧 Scene A 可能还有延迟：

```text
Timer
Response
Push
旧请求
```

新 Scene 已经接管后，旧消息不能影响新实例。

所以商业架构会使用：

```text
scene_epoch
transfer_id
entity_generation
```

例如：

```text
player_id = 10001
scene_epoch = 52
```

旧消息：

```text
epoch = 51
```

直接丢弃。

这和你以前 HANDLE + unique id 防止旧引用误操作新对象的思想非常接近。

---

# 51. AOI Benchmark：不要只凭感觉

当前仓库：

```text
tests/benchmark/aoi_bench.lua
```

默认参数：

```text
10000 entities
100000 queries
map_size = 4000
grid_size = 20
```

核心统计：

```text
elapsed
QPS
avg_candidates
cells
```

其中非常重要的是：

```text
avg_candidates
```

因为 Grid Query 真正成本主要受候选数量影响。

---

# 52. 现有 Benchmark 还不是商业 Benchmark

当前是学习版。

商业场景至少要加入：

## 不同分布

```text
均匀分布
主城聚集
世界Boss热点
单Cell极端聚集
```

## 不同 GridSize

```text
10
20
40
80
```

## 不同 ViewRadius

```text
10
20
30
50
```

## 不同 Entity 数量

```text
1000
5000
10000
50000
```

还要测：

```text
move + visible diff
```

而不只是 Query。

---

# 53. 建议新增真实 AOI Move Benchmark

文件建议：

```text
tests/benchmark/aoi_move_bench.lua
```

伪流程：

```text
创建 N Entity
建立 visible

循环 Move：
    更新位置
    grid.move
    query
    exact distance
    diff old/new
```

统计：

```text
Moves/sec
Avg Candidate
P99 Candidate
Avg Enter
Avg Leave
Max Candidate
Lua Memory
```

这个 Benchmark 比单纯 `query_3x3()` 更接近生产。

---

# 54. AOI 单元测试应该覆盖什么

当前：

```text
tests/unit/test_aoi_grid.lua
```

建议至少覆盖：

```text
Insert
Duplicate Insert
Remove
Move same cell
Move cross cell
3x3 query
Empty cell
Boundary
```

Scene 集成测试则应覆盖：

```text
A进入
B进入A视野
B离开A视野
A离场
Monster Spawn
Monster Death
Monster Respawn
```

---

# 55. Combat 为什么适合做纯 Lua 单元测试

文件：

```text
lualib/scene/combat.lua
```

没有 Skynet 依赖。

因此：

```text
tests/unit/test_combat.lua
```

可以直接测试：

```text
distance
range
damage
```

商业项目建议继续保持：

```text
Damage Formula
Skill Formula
Buff Formula
Drop Formula
```

尽量是纯算法模块。

---

# 56. Scene Service 最终应该负责什么

可以总结成：

```text
Scene Service

负责：
    Entity生命周期
    实时位置
    AOI
    Combat Commit
    Monster实时状态
    Scene规则
    实时广播

不负责：
    背包
    装备
    任务
    长期角色数据
    登录
    账号
    DB细节
```

这个边界非常重要。

---

# 57. 战斗奖励归谁

Monster 死亡：

```text
Scene
```

负责决定：

```text
谁击杀
是否死亡
掉落事件
```

但玩家长期资产：

```text
gold
bag
exp
```

更适合由 PlayerAgent Owner 修改。

因此可能是：

```text
Scene
  ↓ event
PlayerAgent
  ↓
AddReward
```

真正商业级还要加：

```text
operation_id
幂等
流水
重试/补偿
```

留到第四课。

---

# 58. 商业 Attack 链会复杂很多

当前学习工程：

```text
attack
→ damage
→ hp
→ dead
```

真实 ARPG 可能：

```text
Skill Request
    ↓
CD
    ↓
MP
    ↓
Target
    ↓
Range
    ↓
前摇
    ↓
Hit
    ↓
Damage
    ↓
Buff
    ↓
Threat
    ↓
Death
    ↓
Drop
```

但核心原则不变：

> **高频实时提交尽量留在 Scene Actor 内，本地函数调用完成。**

---

# 59. 为什么 ARPG 比 SLG 更难做 Service 划分

SLG 的典型状态：

```text
City
Alliance
March
WorldTile
```

很多更新是：

```text
秒级
事件驱动
```

ARPG：

```text
Move
AOI
Skill
Buff
AI
```

是：

```text
10~100ms 高频交互
```

所以 ARPG 不能为了 Service 化而 Service 化。

更适合：

```text
粗粒度实时 Actor
+
Actor内部本地Module
```

Scene 就是这个粗粒度实时 Actor。

---

# 60. Lua Scene 的内存和 GC 也要关注

当前：

```text
Entity = table
Visible = table
Cell = table
```

开发效率高。

但大量 Entity 时会有：

```text
Hash开销
GC开销
短命Table
Cache Locality较差
```

如果 Benchmark 证明热点严重，再考虑：

```text
复用Table
对象池
压缩结构
减少临时Set
C Module
C++ Scene
```

Skynet 从来没有要求所有逻辑必须用 Lua。

---

# 61. collect_visible 的临时 Table

当前：

```lua
local result = {}
```

每次查询都创建一个新 Table。

高频 Move 会产生大量短命对象。

学习工程没问题。

商业优化可以考虑：

```text
Table Pool
双Buffer
Set复用
直接Diff
```

但不要脱离 Profile 提前复杂化。

---

# 62. AOI 不只是用来“显示玩家”

同一 Grid Candidate 可以服务：

```text
玩家可见
怪物AI找目标
范围技能
附近掉落
NPC
附近频道
区域触发
```

但不要让所有业务共用同一 Radius。

例如：

```text
玩家视距 = 20
怪物警戒 = 10
技能范围 = 5
```

可以共用 Grid Broad Phase，然后各自做精确过滤。

---

# 63. Monster AI 怎样接入

建议未来增加：

```text
lualib/scene/monster_ai.lua
```

AI Module 不直接拥有 Scene 状态。

可以：

```text
Scene Tick
   ↓
Monster AI
   ↓
返回 Intent
   ↓
Scene Commit
```

例如返回：

```lua
{
    action = "attack",
    target_id = 10001,
}
```

最终状态修改仍由 Scene 完成。

---

# 64. Scene Tick 要有 CPU Budget

如果一个 Tick 一次处理：

```text
全部Monster AI
全部Buff
全部Skill
全部Drop
```

某帧工作突然很多，Tick 可能耗时过长。

Scene Mailbox 中其他请求都会延迟。

商业项目经常做：

```text
Budget
```

例如：

```text
本Tick最多处理500个Monster AI
剩余放到下一个Tick
```

核心目标不是“所有事情绝对同一时刻执行”，而是：

```text
延迟稳定
P99可控
```

---

# 65. Scene 绝对不要做慢 IO

错误示例：

```lua
function CMD.attack(...)
    ...
    skynet.call(db, "lua", "insert_combat_log", ...)
    ...
end
```

Scene 高频路径不应该等待：

```text
DB
HTTP
远程Redis
外部服务
```

正确思路：

```text
本地Commit
    ↓
异步send事件
```

例如：

```text
CombatLog
Analytics
Replay
```

可以异步处理。

---

# 66. Scene 与 PlayerAgent 的同步调用方向

高频主路径通常：

```text
PlayerAgent
    ↓ call
Scene
```

Scene 完成后：

```text
send Push
```

回 PlayerAgent。

尽量避免：

```text
Agent call Scene
Scene 又 call Agent
```

尤其 Agent 有 `skynet.queue` 时，很容易形成逻辑环路。

---

# 67. 一个潜在死锁例子

PlayerAgent：

```text
持有 serial
    ↓
call Scene.attack
```

Scene：

```text
attack处理中
    ↓
call PlayerAgent.add_reward
```

而 `add_reward` 也要进入同一个 `serial`。

于是：

```text
Agent原Coroutine
等待Scene

Scene
等待Agent新Coroutine

Agent新Coroutine
等待serial

serial
被原Coroutine占着
```

形成逻辑死锁。

所以：

```text
同步主调用尽量单向
反向派生通知优先 send
```

---

# 68. 当前仓库最值得保留的 Scene 设计

这套学习工程里，下面这些点是值得继续保留的：

```text
1. Scene拥有实时位置
2. Agent只在Scene成功后更新Snapshot
3. AOI/Combat/Movement是普通Module
4. Move提交段没有yield
5. Push使用send
6. Monster与Player共用空间索引
7. 静态配置通过sharedata发布
8. AOI有独立Benchmark
```

这些都符合商业架构继续演进的方向。

---

# 69. 当前工程还缺什么

第三课结束也还不是完整商业 Scene。

还缺：

```text
完整Skill系统
Buff
Monster AI
仇恨
碰撞/NavMesh
掉落
副本状态机
死亡复活
传送
Scene Transfer
断线残留规则
Tick Budget
AOI广播合并
协议压缩
Scene监控
热更
崩溃恢复
跨节点Scene
```

这些是第四课和后续工程深化内容。

---

# 70. 第三课建议实操顺序

## 实验 1：启动当前工程

观察：

```text
Scene initialized
Player enter
```

## 实验 2：两个 Client 登录

让两人互相进入视野。

观察：

```text
entity_enter
```

## 实验 3：离开视野

让 B 走出 A 的 `view_radius`。

观察：

```text
entity_leave
```

## 实验 4：跨 Grid

在：

```text
lualib/scene/aoi_grid.lua
Grid:move
```

观察：

```text
old_key
new_key
```

## 实验 5：攻击 Slime

观察：

```text
distance
damage
hp
observers
```

## 实验 6：击杀与刷新

观察：

```text
grid remove
entities remove
respawn timeout
spawn
```

---

# 71. 推荐调试位置

LuaPanda 重点：

```text
service/scene/scene.lua
    collect_visible
    spawn_monster
    CMD.enter
    CMD.leave
    CMD.move
    CMD.attack
```

以及：

```text
lualib/scene/aoi_grid.lua
    Grid:move
    Grid:query_3x3
```

不要长期开高频循环断点，因为调试器会显著改变调度时序。

---

# 72. Debug Console 观察 Scene

常用：

```text
list
stat
task :<scene_handle>
```

重点观察：

```text
mqlen
cpu
message
task
```

如果：

```text
Scene mqlen持续增长
```

说明 Scene 消费速度低于消息产生速度。

不要第一反应就是：

```text
增加Worker
```

先判断是否是单 Scene Hot Actor。

---

# 73. 第三课核心心智模型

```text
                    PlayerAgent
                        |
                        | call
                        v
                   Scene Service
                        |
        +---------------+----------------+
        |               |                |
        v               v                v
     Entity           Grid            Combat
        |               |                |
        +-------+-------+                |
                |                        |
                v                        |
             Visible                     |
                |                        |
                +-----------+------------+
                            |
                            v
                          Push
                            |
                            v
                       PlayerAgent
```

权威实时状态集中在：

```text
Scene
```

内部算法通过：

```text
普通Module
```

实现。

外部 Service 通过：

```text
Message
```

交互。

---

# 74. 与传统 C++ GameServer 的最终对照

以前：

```text
GameServer Thread

SceneManager
   |
   + Scene1
   + Scene2
   + Scene3
```

所有 Scene 可能在同一个 Game 线程串行跑。

Skynet：

```text
Worker Pool

SceneMgr Service
   |
   + Scene Service 1
   + Scene Service 2
   + Scene Service 3
```

不同 Scene：

```text
独立 Lua State
独立 Mailbox
独立 Entity状态
```

Skynet 对 MMO 最大的价值之一不是把 Scene 内部算法“变得不同”，而是：

```text
不同Scene天然获得更好的并行粒度
```

---

# 75. 第三课常见错误清单

## 错误 1

AOI 做成独立 Service，Move 每次 RPC。

## 错误 2

CombatService 独立，一次 Attack 跨多个 Service。

## 错误 3

PlayerAgent 先改坐标，再 call Scene。

## 错误 4

Move Commit 中途 call NavService，却没有 Version/Generation 校验。

## 错误 5

认为九宫格查询严格 O(1)。

## 错误 6

所有 Entity 每 Tick 全量 Update。

## 错误 7

Scene 同步写 DB。

## 错误 8

Scene 同步 call Agent，Agent 又同步 call Scene。

## 错误 9

把九宫格 Candidate 直接当 Visible。

## 错误 10

只测均匀随机 Benchmark，不测热点聚集。

---

# 76. 练习一：实现 nearby_count

修改：

```text
service/scene/scene.lua
```

增加：

```lua
CMD.nearby_count(player_id)
```

要求：

```text
不能扫描 entities
必须先使用 Grid
必须做精确距离过滤
```

返回：

```text
附近Player数量
附近Monster数量
```

目标：

```text
理解 Candidate + Exact Filter
```

---

# 77. 练习二：增加 Monster AI

新增：

```text
lualib/scene/monster_ai.lua
```

最简单逻辑：

```text
如果视野内有Player
    找最近Player
    如果攻击范围内
        Attack
    否则
        Move toward player
```

要求：

```text
monster_ai.lua 不直接修改 Scene 全局状态
```

它只返回 Action/Intent，最终由 Scene Commit。

---

# 78. 练习三：AOI Move Benchmark

新增：

```text
tests/benchmark/aoi_move_bench.lua
```

至少测试：

```text
1000 Entity
5000 Entity
10000 Entity
```

三种分布：

```text
均匀
中心聚集
单Cell极端聚集
```

输出：

```text
Moves/sec
Avg Candidates
Max Candidates
Avg Enter
Avg Leave
```

然后比较：

```text
grid_size = 10 / 20 / 40
```

---

# 79. 练习四：分析千人沙巴克

假设：

```text
1000 Player
全部集中在一个小区域
10Hz Move
```

回答：

```text
九宫格是否还有效？
Candidate会有多大？
Visible关系是什么量级？
广播消息量会怎样增长？
Scene会不会成为Hot Actor？
优先优化什么？
```

不要第一答案就写：

```text
Region Partition
```

先分析：

```text
广播频率
可见人数上限
消息合并
热点AOI
技能广播
客户端同步策略
```

---

# 80. 第三课自测题

1. 为什么 Scene 适合成为 Service，而 AOI Grid 不适合？
2. PlayerAgent 与 Scene 都保存坐标，为什么不一定违反唯一 Owner？
3. 九宫格为什么只是 Candidate Set，不是 Visible Set？
4. 为什么当前工程要求 `grid_size >= view_radius`？
5. 如果 `grid_size = 5`、`view_radius = 20`，还能只查 3×3 吗？
6. 玩家同 Cell 移动时 Grid 不变，为什么仍要更新 Visible？
7. 为什么 `distance_sq` 比 `sqrt` 更适合 AOI 热路径？
8. 为什么 Move 必须先由 Scene Commit，再更新 PlayerAgent Snapshot？
9. 为什么 Move 提交段中间不能随便加入 `skynet.call`？
10. 为什么 Monster 不适合一怪一 Service？
11. Combat 为什么适合放 Scene，而不是独立 CombatService？
12. 为什么 Scene Push 更适合 `send`？
13. 九宫格查询为什么不是严格 O(1)？
14. GridSize 太大和太小分别有什么问题？
15. 为什么热点聚集会让 Grid AOI 退化？
16. 为什么增加 Worker 数解决不了单 Scene Hot Actor？
17. 分线与 Region Partition 最大区别是什么？
18. Region Partition 为什么需要 Ghost Entity？
19. Scene Transfer 为什么需要 Epoch / Generation？
20. 为什么商业 Benchmark 不能只测均匀随机分布？

## 自测题参考答案

以下行号对应本课当前工作树。代码变动后应同时用完整仓库路径和函数名定位。

1. **Scene 适合成为 Service，AOI Grid 不适合的原因**

   Scene 拥有一个地图实例的实时状态：`service/scene/scene.lua:13-18` 中的 `scene_id`、`scene_cfg`、`grid`、`entities`、`visible` 和 `tick_count`。这些数据需要按消息顺序提交，而且不同 Scene 可以自然并行，因此“一地图实例一 Scene Service”有清晰的 Actor 边界。AOI Grid 只是 Scene 内部的空间索引，`lualib/scene/aoi_grid.lua:16-95` 只管 cell 成员关系，不拥有 Entity 业务生命周期。把它拆为 Service 会让每次 Move 在 Scene 与 AOI 之间 RPC，破坏原来无 yield 的原子提交段，却没有得到有用的状态隔离。

2. **PlayerAgent 和 Scene 的坐标为什么可以共存**

   Scene 是在线实时位置 Owner，它同时提交坐标、`move_state`、Grid 和 Visible Set，见 `service/scene/scene.lua:183-204`。PlayerAgent 中的 `player.x/y` 是供最终存档和重新进场使用的已提交快照；`service/player/player_agent.lua:142-147` 等 Scene 成功返回后才更新。如果 Agent 先信任客户端坐标并写入快照，或 Scene 失败后 Agent 仍提交，才会形成两份可独立变化的权威状态。

3. **九宫格只是 Candidate Set**

   `lualib/scene/aoi_grid.lua:82-95` 把查询点所在 Cell 及周围八个 Cell 的 Entity 都放入结果。方格覆盖区域和圆形视距不同，位于相邻 Cell 远角的 Entity 可能已超过 `view_radius`。`service/scene/scene.lua:43-56` 还要查 `entities`、排除自己，并用距离平方做 Exact Filter，才得到 Visible Set。

4. **`grid_size >= view_radius` 的作用**

   在这个成立条件下，与查询点欧氏距离不超过 `view_radius` 的 Entity，其 Cell 坐标在 x/y 两轴上最多相差 1，因此 3×3 不会漏掉真实可见对象。`service/scene/scene.lua:90-95` 在 Scene 初始化时验证这个前提，`lualib/scene/aoi_grid.lua:3-6` 也把它写成当前实现的设计条件。

5. **`grid_size = 5` 且 `view_radius = 20` 时不能只查 3×3**

   视距横跨四个完整 Cell，考虑查询点靠近 Cell 边界时，固定只查左右各一格会漏对象。一般应计算 `cell_radius = ceil(view_radius / grid_size)`，查 `(2 * cell_radius + 1)^2`，还要做精确距离过滤。该例 `cell_radius=4`，至少查 9×9；边界计算应用单元测试验证，不应只凭图形直觉。

6. **同 Cell 移动仍要更新 Visible**

   `Grid:move` 在 Cell key 没变时返回 false，见 `lualib/scene/aoi_grid.lua:58-64`，它只表示无需重链空间索引。Entity 在 Cell 内仍然可跨过某个玩家的圆形视距边界。`service/scene/scene.lua:200-204` 无论 Cell 是否改变都用新坐标重算 Visible，然后比较 old/new set 生成 Enter、Leave 和 Move Push。

7. **AOI 热路径使用 `distance_sq`**

   只需判断距离是否小于半径时，比较 `dx*dx + dy*dy <= radius*radius` 与先 `sqrt` 后比较结果等价。`lualib/scene/combat.lua:4-11` 避免了每个 Candidate 一次平方根计算。收益大小取决于 Candidate 数、查询频率和 Lua/CPU 环境，应在真实分布下用 Benchmark 确认，不应把它扩大成对整个 Scene 性能的绝对结论。

8. **Scene 先 Commit，Agent 后更新 Snapshot**

   移动同时受边界、Token Bucket、Entity 生命周期和 Scene 状态约束，只有 Scene 有足够信息判定是否接受。PlayerAgent 在 `service/player/player_agent.lua:142` 发起 call 后 yield，Scene 在 `service/scene/scene.lua:195-204` 提交，Agent 在 `service/player/player_agent.lua:143-147` 根据 Response 更新快照。如果先改 Agent，Scene 拒绝或崩溃时会把未生效坐标存档，登录后又以错误位置进场。

9. **Move 提交段中间不能随意 `skynet.call`**

   `call` 会让当前 Scene coroutine yield。等待期间，同一 Scene 可处理 leave、transfer、death 或另一次 move，使原 coroutine 读到的 Entity、`old_visible`、移动额度或 Scene generation 失效。当前 `service/scene/scene.lua:183-249` 在读取、校验、Grid/坐标/Visible 提交之间没有 yield。若必须异步查路，应拆成“捕获请求版本→yield 计算→恢复后重新查找并校验 generation→短提交”。

10. **Monster 不适合一怪一 Service**

    大量普通 Monster 和玩家共享 Scene 的空间、战斗和 Tick 规则。一怪一 Service 会将本地 table 访问改成大量跨 Mailbox 消息，每只怪还要付出 Context/Lua State/Mailbox/Timer 的基础成本；战斗时又要协调 Scene 权威坐标和 Monster HP，使一次 Attack 跨多 Actor 提交。当前 Monster 是 `service/scene/scene.lua:59-86` 创建的普通 Entity，与 Grid 和 Combat 在同一 Owner 内。只有极少数独立生命周期、高复杂且并行收益足够的 Boss 逻辑，才值得另行评估 Actor 边界。

11. **Combat 放在 Scene 内**

    Attack 需要在同一时点读取攻击者/目标的存活状态、权威坐标、攻击范围和 HP，并在成功后更新 Visible Set/Grid 与广播。`service/scene/scene.lua:252-309` 能在同一 Scene coroutine 的无 yield 提交段完成。`lualib/scene/combat.lua:4-17` 作为纯函数 Module 提供数学规则。独立 CombatService 若不拥有这些状态，必须向 Scene 取快照再回传结果，快照在 yield 期间可过期；若它也拥有 HP/坐标，则引入双 Owner。

12. **Scene Push 用 `send`**

    Push 是 Scene 已提交事实的通知，Scene 不依赖 Agent 的返回值完成 Move/Attack。`service/scene/scene.lua:36-40` 使用 `send`，避免 Scene 为每个观察者 yield，也避免 Agent 处理 Push 时反向 call Scene 造成同步环。但 `send` 只表示成功投递到 Runtime 路径，不是可靠到达。Agent 或 Socket 下游过慢时仍会积压，生产环境需要合并、限频、可见人数上限和 Mailbox 监控。

13. **九宫格查询不是严格 O(1)**

    访问的 Cell 数在当前 3×3 设计下是常数 9，但必须遍历这些 Cell 内的全部 Candidate，见 `lualib/scene/aoi_grid.lua:85-93`。复杂度更准确地写成 `O(9 + K)`，简化后是 `O(K)`，K 是候选对象数。均匀分布且局部密度有上限时 K 可以很小；全部人聚在一个 Cell 时 K 接近 Scene Entity 总数。

14. **GridSize 太大和太小的问题**

    GridSize 太大时，每格 Entity 多，3×3 Candidate 增大，Exact Filter 的 CPU 成本上升。GridSize 太小时，如果仍查 3×3 会漏目标；改成按 `ceil(radius/grid_size)` 扩圈后，访问 Cell 数、空 Cell lookup 和跨 Cell 重链频率上升。选型必须结合视距、局部密度、移动速度和广播上限实测；当前 `grid_size=20`、`view_radius=18` 在 `lualib/config/game_data.lua:8-10`，主要是让 3×3 边界条件清晰，不能直接当作所有地图的最优值。

15. **热点聚集会让 Grid AOI 退化**

    Grid 只能快速排除空间上较远的对象。如果 N 个玩家全在一个小区域，每次查询的 K 都近似 N，每个玩家的 Visible Set 也可能近似 N。1000 人、10 Hz Move 在没有可见上限和合并时，候选距离检查和潜在广播都可向每秒千万量级增长。Grid 还在工作，只是没有远处 Entity 可以剪枝，算法退化为密集局部的近全遍历。

16. **增加 Worker 解决不了单 Scene Hot Actor**

    Worker 能并行调度不同 Service，但同一 Scene 的 Mailbox 和权威状态仍由该 Service 串行提交。当一个 Scene 的消息到达率高于它的处理率时，多出来的 Worker 可以处理别的 Scene，却不能同时进入这一 Scene 修改 `entities/visible`。应先用 CPU profile、`mqlen`、单条消息耗时和 Candidate/Push 数确认成本，再做降频、合并、视野上限、分线/实例化或最后的 Region Partition。

17. **分线与 Region Partition 的核心区别**

    分线是把玩家放进多个逻辑上独立的地图副本；同一份 Scene 状态没有跨 Actor 切开，每条线仍可以单 Owner 提交。Region Partition 把同一个连续世界切给多个 Owner，边界附近的 AOI、移动、技能和 Entity 生命周期需跨 Region 协调。分线会改变“所有玩家同场”体验，但工程风险显著低于 Region。

18. **Region Partition 需要 Ghost Entity**

    本 Region 内的玩家视野和技能可跨过边界，但边界另一侧 Entity 的权威 Owner 在另一 Region。Ghost Entity 是远端权威 Entity 在本 Region 的带版本镜像，用于本地 AOI 和初步判定。它不应自行提交 HP/位置等权威变更；跨边界行为需按所有权和协议处理，同时应定义 Ghost 延迟、丢更新、离线和迁移时的失效规则。

19. **Scene Transfer 需要 Epoch / Generation**

    Transfer 会让同一 `player_id` 的当前 Scene Owner 从 A 变成 B。由于 leave、准备目标 Scene、路由更新和 enter 可能跨 yield/跨节点，A 的延迟 Move/Timer/Push 可在 B 接管后才到达。消息携带 epoch，接收方只接受与当前路由版本相同的消息，才能拒绝旧 Owner 的迟到提交。Epoch 应与稳定 Scene/Player ID 一起路由，不能只依赖可重建的 Service Address。

20. **商业 Benchmark 不能只测均匀随机分布**

    当前 `tests/benchmark/aoi_bench.lua:9-16` 把 Entity 均匀随机放在 4000×4000 地图，`tests/benchmark/aoi_bench.lua:18-31` 只测 `query_3x3` QPS 和平均 Candidate。这个基线能发现算法回归，但会隐藏主城、Boss 点和攻城区的局部高密度，也没包含 `Grid:move`、Exact Filter、Visible diff、Push 数和 table/GC 分配。可用的结论至少要同时报告均匀、中心聚集、单 Cell 极端聚集，多个 GridSize/视距/数量档位，并记录 P50/P95/P99、平均/最大 Candidate、Enter/Leave/Move Push 和 GC。

---

# 81. 第三课完成标准

进入第四课前，你应该可以独立：

1. 解释 Scene 为什么是合理 Actor；
2. 明确 Scene 与 PlayerAgent 的状态边界；
3. 从零实现一个 Grid AOI；
4. 解释 Grid Candidate 与 Visible Set 的区别；
5. 实现 Player Enter / Leave / Move；
6. 正确维护双向可视关系；
7. 实现 Monster Spawn / Death / Respawn；
8. 实现基础 Attack / Damage / Range Check；
9. 知道 Scene 高频路径为什么不能随便 yield；
10. 知道 Tick 与 Timer 各自适合什么业务；
11. 分析九宫格 AOI 的复杂度与退化条件；
12. 设计一个有意义的 AOI Benchmark；
13. 判断 Scene 是否成为 Hot Actor；
14. 知道什么时候先分线；
15. 理解什么时候才真正需要 Region Partition；
16. 能把传统单线程 C++ Scene 与 Skynet Scene Actor 做完整映射。

---

# 82. 第四课应该进入什么

前三课：

```text
第一课
Runtime / 启动链

        ↓

第二课
Service / Actor / Coroutine / State Owner

        ↓

第三课
Scene / AOI / Combat / Realtime World
```

第四课应该完成：

```text
如何从学习工程走向商业 MMO Server
```

重点包括：

```text
Cluster
多节点部署
Gate / Game / Scene / DB Node拆分
跨服
Scene Transfer
DB持久化
Dirty Save
关键交易
幂等
热更新
sharedata
Lua GC
PlayerAgent内存
监控
Profile
故障恢复
压测
容量规划
C/C++热点优化
```

这样四课体系才真正闭环：

```text
会运行Skynet
    ↓
会写Skynet业务
    ↓
会做MMO实时世界
    ↓
会设计商业化架构
```

---

# 附录 A：本课源码阅读顺序

建议按一名玩家进入、移动、攻击的执行链阅读：

```text
service/player/player_agent.lua
    ↓
REQUEST.move / REQUEST.attack

service/scene/scene_mgr.lua
    ↓
Scene路由与生命周期

service/scene/scene.lua
    ↓
CMD.enter
CMD.leave
CMD.move
CMD.attack

lualib/scene/movement.lua
    ↓
移动合法性

lualib/scene/aoi_grid.lua
    ↓
Grid空间索引

lualib/scene/combat.lua
    ↓
距离 / Damage

lualib/config/game_data.lua
    ↓
Scene配置

tests/unit/test_aoi_grid.lua
tests/unit/test_movement.lua
tests/unit/test_combat.lua
    ↓
算法单元测试

tests/benchmark/aoi_bench.lua
    ↓
AOI性能
```

---

# 附录 B：你应该重点反复看的函数

```text
service/scene/scene.lua

spawn_monster
collect_visible
CMD.enter
CMD.leave
CMD.move
CMD.attack
```

```text
lualib/scene/aoi_grid.lua

Grid.new
Grid.coords
Grid.insert
Grid.remove
Grid.move
Grid.query_3x3
```

```text
lualib/scene/movement.lua

new_state
try_move
```

```text
lualib/scene/combat.lua

distance_sq
in_range
player_damage
```

真正吃透这些以后，你已经不是“知道 Skynet API”，而是在用 Skynet 的 Actor 模型实现一个真实 MMO Scene。
