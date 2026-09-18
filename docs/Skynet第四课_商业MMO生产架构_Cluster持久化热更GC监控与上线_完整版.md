# Skynet MMO 学习课程第四课：从学习工程到商业 MMO Server

> **工程基线**：`simbiwu/skynet-mmo-learning` 当前 `main` 分支
> **Skynet 基线**：Skynet v1.8.0 + Skynet Bundled Modified Lua 5.4.7
> **运行环境**：Linux / Windows 通过 WSL2
> **协议**：Sproto + 2-byte big-endian length framing
> **前置课程**：
>
> - 第一课：Skynet 启动链、构建与调试工具链
> - 第二课：Service、Actor、Coroutine、消息通信与状态所有权
> - 第三课：Scene、九宫格 AOI、Monster、Combat 与实时世界
>
> **本课定位**：最后一课。目标不是把当前教学工程包装成“已经商业可用”，而是建立一套从当前工程演进到商业 MMO Server 的完整判断框架，并给出关键代码、目录、消息链、失败协议、测试方法和上线门槛。

---

# 0. 四课学到这里，缺的已经不是 Skynet API

前三课结束以后，你已经应该能回答：

```text
Skynet 怎么启动
Service 怎么创建
一个 Lua Service 与 Lua State 是什么关系
Worker / Mailbox / Coroutine 怎么协作
call / send / dispatch / retpack 怎么工作
为什么 yield 后旧状态可能失效
PlayerAgent / Scene / Manager 的状态边界怎么划
Scene / AOI / Combat 怎么组织
Hot Actor 为什么不能靠增加 Worker 解决
```

这些已经覆盖了“会不会写 Skynet 业务”的核心。

第四课换一个问题：

> 如果现在让你负责一个准备上线的商业 MMO Server，当前仓库离“可运营”还差什么？

当前仓库已经有：

```text
Gate / Watchdog
PlayerMgr / PlayerAgent
SceneMgr / Scene
AOI / Movement / Combat
Memory / MySQL Storage
sharedata
Debug Console
LuaPanda / GDB
Unit Test
Integration Smoke Test
AOI Benchmark
```

这些结构足够学习，而且很多边界设计是对的。

但商业 MMO 还必须面对：

```text
多进程 / 多节点
跨节点路由
DB故障
数据版本
关键经济事务
重复请求
进程崩溃
Graceful Shutdown
配置热更新
代码热更
状态迁移
GC抖动
Lua State内存
Mailbox积压
慢SQL
线上诊断
压测
容量规划
灰度
回滚
灾难恢复
```

所以第四课不再增加很多“玩法代码”。

这一课关注的是：

```text
系统在出错时还能不能保持正确
系统在高负载时还能不能稳定
系统在升级时还能不能控制风险
```

---

# 1. 先给出最终目标架构

先不要急着学 `cluster.call`。

先画出商业 MMO 可能长成什么样。

结合你以前熟悉的：

```text
Gate
Game
Chat
DB
Center
公共服
```

Skynet 可以演进成：

```text
                       ┌──────────────────────┐
                       │    Login / Center    │
                       │ Auth / Token / Pay   │
                       └──────────┬───────────┘
                                  │
                                  ▼
Client ───────► Gate Node ─────► Player Node
                │                 │
                │                 ├── PlayerMgr
                │                 ├── PlayerAgent / PlayerWorker
                │                 └── Router Cache
                │
                └──────────────────────────────┐
                                               │
                                               ▼
                                     Scene Node(s)
                                     ├── SceneMgr
                                     ├── Scene 1
                                     ├── Scene 2
                                     └── Instance ...
                                               │
                          ┌────────────────────┼───────────────────┐
                          ▼                    ▼                   ▼
                      World Node           Social Node          DB Node
                     ├── WorldMgr         ├── Guild           ├── StorageMgr
                     ├── Rank             ├── Chat            ├── DBWorker 1
                     └── Activity         └── Mail            └── DBWorker N
                                               │
                                               ▼
                                              MySQL
```

实际项目不一定拆成这么多进程。

重点不是进程名字。

重点是：

```text
高频实时状态
Player / Scene

全局状态
World / Guild / Rank

外部资源
DB / Center

连接状态
Gate
```

有明确 Owner。

---

# 2. 当前工程为什么必须先保持单节点

当前：

```text
config/game.lua
```

是：

```lua
harbor = 0
```

当前：

```text
service/main.lua
```

直接在一个 Skynet Process 中创建：

```text
protocol loader
config service
storage mgr
scene mgr
player mgr
auth
watchdog
gate
```

这是教学阶段正确选择。

如果第一课就加入：

```text
Cluster
Redis
多节点配置
服务发现
跨机故障
```

你会很难分清一个 Bug 到底来自：

```text
Service逻辑
Coroutine
网络
Cluster
配置
节点生命周期
```

商业演进的正确顺序通常是：

```text
单节点逻辑正确
    ↓
状态Owner明确
    ↓
业务链可测
    ↓
Profile确定边界
    ↓
再拆节点
```

而不是：

```text
先画20个微服务框
```

---

# 3. 从单节点拆到多节点，第一原则仍然是状态所有权

单节点：

```text
PlayerAgent
    ↓
skynet.call(Scene)
```

多节点以后：

```text
PlayerAgent Node
    ↓
cluster.call(Scene Node)
```

表面只是 API 变化。

实际上失败模型完全不同。

单进程调用：

```text
目标Service存在
消息通常能进入目标Mailbox
```

跨节点以后增加：

```text
网络断开
对端进程崩溃
节点重启
路由过期
请求已执行但Response丢失
重复发送
消息乱序
跨版本协议
```

所以不要把：

```text
cluster.call
```

理解成“远程版 skynet.call”。

它是：

```text
跨节点RPC
```

需要完整失败协议。

---

# 4. Skynet v1.8.0 的 Cluster API

上游文件：

```text
third_party/skynet/lualib/skynet/cluster.lua
third_party/skynet/service/clusterd.lua
```

Skynet v1.8.0 提供的常用接口包括：

```lua
cluster.call(node, address, ...)
cluster.send(node, address, ...)
cluster.open(...)
cluster.reload(config)
cluster.register(name, addr)
cluster.unregister(name)
cluster.query(node, name)
cluster.proxy(node, name)
```

其中最常用的是：

```text
cluster.call
cluster.send
```

与本地：

```text
skynet.call
skynet.send
```

语义相似：

```text
call
等待Response

send
只发送，不等待Response
```

但业务层必须额外处理网络失败和重复执行。

---

# 5. 建议新增 Cluster 配置文件

下面是**第四课建议新增**的文件，当前仓库还没有。

完整路径：

```text
config/cluster.lua
```

示例：

```lua
gate1   = "127.0.0.1:9101"
player1 = "127.0.0.1:9102"
scene1  = "127.0.0.1:9103"
world1  = "127.0.0.1:9104"
db1     = "127.0.0.1:9105"
```

对应节点配置中需要让 Skynet 知道 Cluster 配置文件，并在目标节点开启对应监听。

学习时不需要一开始做动态服务发现。先固定两台 Node，确认：

```text
cluster.call
cluster.send
节点断开
节点重连
```

的真实行为。

---

# 6. 不建议让业务代码到处直接 cluster.call

最简单的写法：

```lua
local cluster = require "skynet.cluster"

cluster.call(
    "scene1",
    ".scene_router",
    "move",
    player_id,
    x,
    y
)
```

能跑。

但如果整个项目到处：

```text
cluster.call("scene1", ...)
cluster.call("world2", ...)
cluster.call("db3", ...)
```

以后：

```text
节点迁移
Scene换服
分片策略变化
故障转移
```

业务代码会和部署拓扑强绑定。

更好的做法：

```text
PlayerAgent
    ↓
Router Module / Router Service
    ↓
找到 node + service
    ↓
cluster.call
```

注意：

Router 不要变成所有高频消息永久经过的中央 Hot Actor。

---

# 7. 建议的 Router 设计

**建议新增文件**：

```text
lualib/router/service_router.lua
```

这是普通 Lua Module，不是必然要做成 Service。

```lua
local skynet = require "skynet"
local cluster = require "skynet.cluster"

local M = {}
local local_node

function M.init(node)
    local_node = node
end

function M.call(target, protocol, ...)
    if target.node == local_node then
        return skynet.call(target.address, protocol, ...)
    end

    return cluster.call(
        target.node,
        target.address,
        ...
    )
end

function M.send(target, protocol, ...)
    if target.node == local_node then
        return skynet.send(target.address, protocol, ...)
    end

    return cluster.send(
        target.node,
        target.address,
        ...
    )
end

return M
```

它只解决：

```text
Local RPC
Remote RPC
```

的路由选择。

不要在这里继续塞：

```text
自动重试
业务补偿
经济事务
状态机
```

Router 只负责路由。

---

# 8. Scene 路由不能只保存 Service Address

单节点时代：

```text
scene_id -> Service Address
```

足够。

多节点后：

```text
scene_id
    ↓
node
address
epoch
```

建议逻辑结构：

```lua
{
    scene_id = 1001,
    node = "scene2",
    address = ":01000023",
    epoch = 18,
}
```

为什么需要 `epoch`？

因为：

```text
scene2挂了
Scene重建到scene3
```

旧地址对应的延迟消息不能继续生效。

所以身份应该变成：

```text
Scene Identity
=
scene_id + epoch
```

和你以前的：

```text
HANDLE + generation
```

是同一个思想。

---

# 9. 跨 Scene Transfer 不能理解成“改一下路由”

玩家从：

```text
Scene A
```

去：

```text
Scene B
```

最危险的错误流程：

```text
A remove
    ↓
修改Player.scene_id
    ↓
B enter
```

如果 B enter 失败：

```text
玩家在哪？
```

已经不清楚。

更稳妥的思路：

```text
Prepare Target
    ↓
Target Scene确认可进入
    ↓
生成 transfer_id
    ↓
Source Scene冻结旧Entity
    ↓
Target Commit
    ↓
更新Route + Epoch
    ↓
Source Cleanup
```

失败时根据阶段：

```text
取消Target
或
恢复Source
```

这已经接近 Saga。

不需要为了术语而实现一个“Saga Framework”。

但必须明确：

```text
每一阶段谁是Owner
是否已提交
失败后谁负责恢复
```

---

# 10. Gate 与 PlayerAgent 跨节点后怎么设计

当前工程：

```text
Gate
  ↓ forward
PlayerAgent
```

都在同一 Skynet 节点。

多节点时，Gate 无法简单把官方 `gate.lua` 的本地 redirect 当成跨节点路由。

生产设计通常会选择：

```text
方案A
Gate和PlayerAgent放同一个Node

方案B
Gate只负责连接
业务包转发到Game/Player Node
```

对于你以前的传统 MMO 经验：

```text
Gate独立进程
GameServer独立进程
```

更接近方案 B。

这时 Gate 侧需要：

```text
fd / connection_id
    ↓
player_id
    ↓
target player node
```

消息通过 Cluster 或自定义内部协议转发。

---

# 11. 商业 MMO 中 Cluster 不应承担所有数据同步

Cluster 适合：

```text
RPC
控制消息
跨节点业务事件
```

不适合盲目承担：

```text
每帧海量位置广播
高频大包
全服Fan-out
```

例如：

```text
Scene Node
每100ms
给World Node同步所有玩家坐标
```

通常就是错误设计。

跨节点只同步：

```text
业务真正需要的最小状态
```

高频实时状态尽量局部化。

---

# 12. 当前 Storage 的真实结构

当前仓库：

```text
service/storage/storage_mgr.lua
```

创建固定 Worker Pool。

核心路由：

```lua
workers[(player_id % #workers) + 1]
```

所以：

```text
同一个player_id
```

稳定落到：

```text
同一个Storage Worker
```

这有两个好处：

```text
连接复用
同玩家DB操作更容易保持顺序
```

当前：

```text
service/storage/memory_worker.lua
service/storage/mysql_worker.lua
```

实现相同 RPC Surface：

```text
load_player
save_player
```

这层抽象非常适合教学，也适合作为正式 DAO 边界的起点。

---

# 13. 当前 MySQL 模式为什么仍然只是学习版

当前：

```text
service/storage/mysql_worker.lua
```

主要逻辑：

```text
mysql.connect
SELECT player
UPDATE player
```

它还没有：

```text
Reconnect
Retry Policy
Connection Health
Transaction
Version Check
Dirty Save
Batch Save
Slow Query
Backpressure
Ledger
Operation ID
```

所以：

```text
storage_driver = mysql
```

不能等同于：

```text
已经拥有商业持久化系统
```

---

# 14. 商业 MMO 不应该“每改一次属性就同步写 DB”

假设：

```text
玩家移动
```

每次都：

```lua
skynet.call(storage, "lua", "save_position", ...)
```

会导致：

```text
网络延迟进入业务链
DB吞吐压力
Coroutine等待
故障传播
```

更常见：

```text
内存是在线权威
DB是持久化副本
```

普通状态采用：

```text
Dirty + Periodic Snapshot
```

关键经济状态采用：

```text
Ledger / Operation
```

两种路径不要混为一谈。

---

# 15. Dirty Save 的基本模型

建议 PlayerAgent 增加：

```lua
local dirty = false
local state_version = 0
local saved_version = 0
```

例如金币变化：

```lua
local function add_gold(value)
    player.gold = player.gold + value

    state_version = state_version + 1
    dirty = true
end
```

定时：

```text
每30秒
```

如果：

```text
dirty == true
```

提交 Snapshot。

但这里还不够。

---

# 16. 为什么 Snapshot 必须带 Version

假设：

```text
Version 10
发起Save
    ↓ yield

等待期间
玩家又产生业务
Version 11
```

Save 10 返回以后，如果直接：

```lua
dirty = false
```

就错了。

正确：

```lua
local saving_version = state_version

local snapshot = build_snapshot(player, saving_version)

local ok = skynet.call(
    storage_mgr,
    "lua",
    "save_player",
    snapshot
)

if ok then
    saved_version = math.max(saved_version, saving_version)

    if state_version == saving_version then
        dirty = false
    end
end
```

如果当前已经：

```text
Version 11
```

则：

```text
Version10保存成功
```

只能说明 10 已持久化。

不能清掉 11 的 Dirty。

---

# 17. Snapshot 数据不要靠延迟读取 Player Table

建议显式构造：

```lua
local function build_snapshot(player, version)
    return {
        player_id = player.player_id,
        level = player.level,
        gold = player.gold,
        hp = player.hp,
        max_hp = player.max_hp,
        scene_id = player.scene_id,
        x = player.x,
        y = player.y,
        version = version,
    }
end
```

再发送。

这样可以明确：

```text
这次Save保存的是哪个版本
```

而不是把“未来再去读 Player 当前值”隐藏在异步队列里。

---

# 18. DB 里的 Version 有什么用

建议正式 `player` 表增加：

```sql
version BIGINT UNSIGNED NOT NULL DEFAULT 0
```

保存时：

```sql
UPDATE player
SET
    gold = ?,
    level = ?,
    version = ?
WHERE
    player_id = ?
    AND version < ?;
```

这是最简单的一类：

```text
Versioned Snapshot
```

目的：

```text
旧保存不能覆盖新保存
```

具体 SQL 条件、跨表一致性和重试策略要结合正式数据模型设计。

---

# 19. 你以前“后写覆盖前写”的模型怎么迁移

你以前 DBServer 的核心原则是：

```text
同一玩家
后面的写
覆盖前面的写
```

而 DBServer 内部按顺序执行。

Skynet 完全可以延续这个思想。

例如：

```text
player_id
    ↓ hash
固定Storage Worker
    ↓
Worker内部串行
    ↓
MySQL
```

再加：

```text
version
```

解决：

```text
跨Worker
重试
节点重建
延迟Response
```

下的旧写覆盖。

所以不需要为了 Skynet 把已有成熟经验全部推翻。

---

# 20. 关键经济数据不能只靠 Snapshot

假设：

```text
充值
商城购买
发放稀有道具
交易
```

如果只做：

```text
player.gold -= 100
dirty = true
```

然后等 30 秒 Snapshot。

进程在 10 秒后崩溃：

```text
这笔交易可能丢
```

对于普通位置可以接受。

对于付费资产通常不能。

所以商业 MMO 往往把状态分层。

---

# 21. 三类持久化数据

## A. 高频、可容忍少量回退

例如：

```text
位置
部分临时进度
```

可：

```text
Dirty Snapshot
```

## B. 重要角色状态

例如：

```text
等级
经验
装备
背包
任务
```

通常：

```text
较短周期Snapshot
关键节点立即Flush
```

## C. 关键经济操作

例如：

```text
充值
扣钻石
发稀有道具
玩家交易
```

需要：

```text
Operation ID
Ledger / Journal
Idempotency
Audit
```

---

# 22. Operation ID：商业经济系统最重要的基础之一

一次购买：

```text
player=10001
item=5001
```

客户端因为网络超时重试三次。

如果服务端每次都：

```text
扣100金币
发1个物品
```

就是严重事故。

所以：

```text
operation_id
```

必须稳定。

例如：

```text
shop:10001:20260918:00001234
```

服务端保存：

```text
operation_id
player_id
type
before
delta
after
status
created_at
```

相同 Operation：

```text
只执行一次
```

---

# 23. 建议的 Ledger 表

这是教学示例，不是固定生产 Schema。

**建议新增**：

```text
sql/ledger.sql
```

```sql
CREATE TABLE economy_ledger (
    operation_id VARCHAR(64) NOT NULL,
    player_id BIGINT UNSIGNED NOT NULL,
    op_type VARCHAR(32) NOT NULL,
    currency VARCHAR(16) NOT NULL,
    delta BIGINT NOT NULL,
    before_value BIGINT NOT NULL,
    after_value BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY(operation_id),
    KEY idx_player_time(player_id, created_at)
) ENGINE=InnoDB;
```

唯一键：

```text
operation_id
```

就是幂等屏障之一。

---

# 24. 一次关键购买应该怎样思考

不要把流程简化成：

```text
扣金币
加物品
save_player
```

更完整：

```text
Client request
    ↓
PlayerAgent serial
    ↓
校验 request_id / operation_id
    ↓
读取价格 / 配置
    ↓
重新检查当前金币
    ↓
准备经济变更
    ↓
写 Ledger / Transaction
    ↓
Commit
    ↓
更新内存权威状态
    ↓
返回结果
```

也可以设计成：

```text
先内存Commit
再写Journal
```

但必须明确：

```text
Crash在哪一步发生
恢复时以谁为准
```

没有唯一通用答案。

---

# 25. 不要把“数据库事务”误认为解决了分布式事务

假设：

```text
PlayerAgent
    ↓
DB事务成功
    ↓
Response返回前
PlayerAgent进程崩溃
```

客户端没收到成功。

它重试。

DB 已经 Commit。

如果没有：

```text
operation_id
```

数据库事务也救不了重复扣费。

所以：

```text
DB Transaction
```

解决的是：

```text
数据库内部原子性
```

而：

```text
Idempotency
```

解决的是：

```text
跨请求 / 跨重试
```

两者是不同问题。

---

# 26. PlayerAgent 下线保存的当前竞态

当前：

```text
service/player/player_agent.lua
```

断线后：

```text
60秒 grace
    ↓
offline()
    ↓
Scene.leave
    ↓
Storage.save
    ↓
PlayerMgr.remove
    ↓
exit
```

问题在于：

```text
Scene.leave
Storage.save
PlayerMgr.remove
```

全部可能 yield。

如果：

```text
offline已经开始
```

之后玩家重新登录并：

```text
bind_client
```

旧 offline Coroutine 恢复后仍可能继续退出 Agent。

这是当前仓库已经明确记录的生产缺口。

---

# 27. 正确方向：Offline Pipeline 状态机

建议 PlayerAgent 增加：

```lua
local lifecycle = {
    state = "ONLINE",
    version = 0,
}
```

状态：

```text
ONLINE
DISCONNECTED
OFFLINING
EXITED
```

断线：

```text
ONLINE
  ↓
DISCONNECTED
```

Timer 到：

```text
DISCONNECTED
  ↓
OFFLINING
```

每一个 yield 前保存：

```text
version
```

每一次恢复：

```text
重新验证
```

例如：

```lua
local my_version = lifecycle.version

local ok = skynet.call(
    scene_service,
    "lua",
    "leave",
    player.player_id
)

if lifecycle.version ~= my_version then
    return false, "LIFECYCLE_CHANGED"
end
```

这就是第二课讲的：

```text
yield = 状态失效边界
```

在生产生命周期中的真实应用。

---

# 28. Graceful Shutdown 不能直接 kill 进程

上线维护时：

```text
kill -9
```

只能作为最后手段。

正常停服流程建议：

```text
进入 DRAINING
    ↓
停止新连接 / 新登录
    ↓
通知 Gate 摘流量
    ↓
停止创建新副本
    ↓
等待关键业务结束
    ↓
批量 Flush Dirty Player
    ↓
停止 Scene
    ↓
停止 World
    ↓
停止 Storage
    ↓
进程退出
```

必须设置：

```text
总超时
```

不能无限等。

超时以后：

```text
记录未保存玩家
落恢复文件 / Journal
强制退出
```

具体策略由业务风险决定。

---

# 29. Graceful Shutdown 建议新增 Service

建议：

```text
service/system/shutdown_mgr.lua
```

职责：

```text
维护 RUNNING / DRAINING / STOPPING
协调各 Manager
统计剩余玩家
等待 Dirty Flush
输出最终结果
```

它不应该：

```text
直接修改 Player State
```

它只是协调者。

---

# 30. 配置为什么不能每个 PlayerAgent require 一份

第二课讨论过：

```text
1 PlayerAgent = 1 Lua State
```

如果：

```text
10000 PlayerAgent
```

每个都：

```lua
local cfg = require "huge_config"
```

而该模块返回大型 Lua table，

会产生非常明显的重复内存。

当前仓库已经采用：

```text
service/config/config_service.lua
```

调用：

```lua
sharedata.new("game_config", game_data)
```

Scene：

```lua
sharedata.query("game_config")
```

这是正确方向。

---

# 31. Skynet v1.8.0 sharedata 的运行方式

上游：

```text
third_party/skynet/lualib/skynet/sharedata.lua
third_party/skynet/service/sharedatad.lua
```

常用：

```lua
sharedata.new(name, value)
sharedata.query(name)
sharedata.update(name, value)
sharedata.delete(name)
sharedata.flush()
sharedata.deepcopy(name)
```

`query` 返回共享对象包装。

多个 Lua Service 不需要各自维护完整深拷贝。

这对：

```text
ItemConfig
SkillConfig
MonsterConfig
ActivityConfig
MapConfig
```

很有价值。

---

# 32. sharedata.update 不等于“业务热更完成”

假设：

```lua
sharedata.update(
    "game_config",
    new_config
)
```

只是发布新配置版本。

业务还要回答：

```text
老Skill实例用旧配置还是新配置？
正在进行的副本是否切换？
已经生成的Monster属性是否重算？
活动截止时间改变如何处理？
```

这些属于：

```text
State Migration
```

所以：

```text
Config Reload
```

和：

```text
Live State Migration
```

必须分开。

---

# 33. 配置热更应该带版本

建议配置结构：

```lua
return {
    version = 20260918001,
    scenes = {...},
    items = {...},
    skills = {...},
}
```

Service 持有：

```text
config_version
```

关键状态创建时记录：

```text
skill_config_version
activity_version
```

这样线上排查才能知道：

```text
这个Monster是按哪版配置创建的
```

---

# 34. 配置发布建议流程

```text
加载新文件
    ↓
语法校验
    ↓
Schema校验
    ↓
业务约束校验
    ↓
生成Version
    ↓
Staging验证
    ↓
sharedata.update
    ↓
通知受影响Service
    ↓
观察Metric
    ↓
确认 / 回滚
```

不要：

```text
线上直接覆盖lua配置文件
然后require
```

没有版本、没有校验、没有回滚。

---

# 35. Code Hotfix 与 Config Hot Reload 不是一回事

Config：

```text
改变数据
```

Code Hotfix：

```text
改变函数实现
```

Code Hotfix 风险更大。

例如：

```lua
function Combat.calc_damage(...)
```

换了实现。

但现有 Coroutine：

```text
可能已经在旧函数栈里
```

现有状态：

```text
可能是旧结构
```

所以热更必须考虑：

```text
代码版本
状态版本
函数引用缓存
Coroutine执行中
闭包Upvalue
Module Cache
```

---

# 36. 不建议一开始做“万能热更框架”

教学项目最容易犯：

```text
为了商业化
先做一个万能Hotfix Framework
```

复杂度非常高。

更实际：

```text
第一阶段
只允许无状态函数替换

第二阶段
支持显式Module Reload

第三阶段
需要时写专门State Migration
```

每次 Hotfix：

```text
明确受影响Service
明确旧状态到新状态转换
```

---

# 37. 一个最小 Hotfix Manager 应该负责什么

建议新增：

```text
service/system/hotfix_mgr.lua
```

职责：

```text
接收版本
校验目标Service
执行预检查
分批发送Hotfix命令
收集结果
失败停止
记录变更
```

不要负责：

```text
自动猜测所有Lua State要怎么迁移
```

状态迁移必须业务显式实现。

---

# 38. Lua State 多意味着 GC 也多

如果：

```text
1 Player = 1 PlayerAgent
```

那么：

```text
10000 Agent
```

意味着：

```text
大量独立 Lua Heap
大量独立 GC 状态
```

好处：

```text
单个玩家GC影响范围小
```

代价：

```text
VM基础内存
Module状态重复
Coroutine
Table
GC元数据
```

都会累计。

所以商业项目必须实际测：

```text
Idle Agent KB
Loaded Agent KB
Active Agent KB
```

而不是凭感觉。

---

# 39. PlayerAgent 内存应该怎样 Benchmark

建议新增：

```text
tests/benchmark/player_agent_memory.lua
```

目标不是启动完整网络。

可以：

```text
创建100
创建1000
创建5000 PlayerAgent
```

每阶段读取：

```text
Lua Heap
C Memory
RSS
```

计算：

```text
ΔMemory / Agent
```

至少分：

```text
空Agent
加载玩家数据后
require业务Module后
进入Scene后
```

才能知道：

```text
到底是谁占内存
```

---

# 40. 不要只看 collectgarbage("count")

Lua：

```lua
collectgarbage("count")
```

只代表 Lua VM 看到的 Lua Heap 量级。

整个进程还有：

```text
Skynet C Allocation
Socket Buffer
jemalloc Arena
C Module
网络包
数据库Buffer
```

所以要同时看：

```text
Lua Heap
Skynet C Memory
jemalloc
RSS
```

当前 Skynet Debug Console 已经提供：

```text
mem
cmem
jmem
```

对应不同口径。

---

# 41. GC 优化的正确顺序

不要一开始调 GC 参数。

先找：

```text
分配量为什么这么大
```

Scene 常见来源：

```text
每Move创建临时Table
每广播构造大量Payload
Visible Set重建
字符串拼接
短命Coroutine
配置深拷贝
```

PlayerAgent：

```text
请求临时Table
重复配置
任务/背包结构
```

顺序应该：

```text
减少无意义Allocation
    ↓
复用热点Buffer
    ↓
sharedata
    ↓
再调GC策略
```

---

# 42. Scene GC 与 PlayerAgent GC 的关注点不同

PlayerAgent：

```text
很多Service
每个Heap较小
```

关注：

```text
总内存
Idle成本
模块重复
```

Scene：

```text
少量Service
单个Heap可能很大
高频分配
```

关注：

```text
Pause
Allocation Rate
Hot Path
```

所以不要全项目统一一组 GC 参数然后结束。

---

# 43. 监控先看 Service，不先看机器平均 CPU

一个 Skynet Process：

```text
CPU = 40%
```

不能说明健康。

可能：

```text
Scene A 单核100%
其它Worker很闲
```

平均仍然不高。

所以必须有：

```text
Service CPU
Mailbox Length
Message Rate
Handler Latency
RPC Latency
```

---

# 44. Skynet v1.8.0 已经能提供什么

上游：

```text
third_party/skynet/lualib/skynet/debug.lua
third_party/skynet/service/debug_console.lua
```

`STAT` 已经提供：

```text
task
mqlen
cpu
message
```

Debug Console 还能查看：

```text
list
stat
task
info
ping
mem
cmem
jmem
netstat
trace
```

这些是：

```text
诊断入口
```

不是完整监控平台。

正式环境还需要周期采集和时序存储。

---

# 45. 建议最小 Metric 集合

## Node

```text
CPU
RSS
FD
Network In/Out
Process Uptime
```

## Service

```text
mqlen
message rate
cpu delta
active coroutine
error rate
```

## RPC

```text
target
command
P50
P95
P99
timeout
error
```

## Scene

```text
players
entities
AOI candidates
AOI visible relations
tick cost
move/sec
attack/sec
broadcast/sec
```

## Storage

```text
queue
in-flight
query latency
slow query
retry
disconnect
dirty player count
oldest dirty age
```

## Player

不要把：

```text
player_id
```

直接作为 Metrics Label。

这会造成高基数。

玩家级问题用：

```text
Log / Trace
```

定位。

---

# 46. Trace ID / Request ID / Operation ID 必须区分

这三个 ID 用途不同。

## trace_id

一次端到端调用链。

例如：

```text
Login
Move
Attack
```

## request_id

客户端一次请求。

主要用于：

```text
请求对应
重试定位
```

## operation_id

业务幂等操作。

例如：

```text
支付订单
商城购买
发奖
交易
```

重试时：

```text
operation_id不变
```

---

# 47. 一个 Move Trace 应该长什么样

```text
trace_id = T123

Gate
recv move
    ↓

PlayerAgent
request move
player=10001
state_version=52
    ↓ call

Scene
scene=1
epoch=8
move commit
old=(100,100)
new=(101,100)
    ↓ response

PlayerAgent
snapshot update
version=53
    ↓

Client Response
```

日志能串起来以后，

你才可以回答：

```text
慢在哪里
失败在哪里
恢复时状态是什么
```

---

# 48. 生产日志不应该只写自然语言

当前学习工程大量：

```lua
skynet.error(
    "[Scene] player enter scene=",
    scene_id,
    " player=",
    player.id
)
```

学习够用。

正式项目建议结构化：

```text
event=scene_player_enter
scene_id=1
player_id=10001
scene_epoch=8
trace_id=T123
build=abc123
```

不一定必须 JSON。

重点是：

```text
字段稳定
机器可检索
```

---

# 49. Mailbox 是 Skynet 最重要的背压信号之一

如果：

```text
mqlen
```

持续上升：

```text
输入 > 消费
```

系统已经不稳定。

例如：

```text
Scene
每秒收到15000消息
只能处理10000
```

那么：

```text
每秒积压5000
```

无论客户端 Timeout 调多大，

最终都会崩。

---

# 50. Mailbox 积压的四类原因

## 消息量突然增加

例如：

```text
世界Boss
开服
活动
攻击流量
```

## 单条消息变慢

例如：

```text
新技能算法
AOI退化
同步DB
```

## 下游 RPC 变慢

虽然当前 Handler yield，

但会增加：

```text
Coroutine数量
内存
状态等待
```

## Hot Actor

一个 Service 成为串行瓶颈。

---

# 51. Backpressure 不能只靠“多开 Worker”

对于 Scene：

```text
多Worker
```

不能并行同一个 Scene Actor。

可用手段：

```text
限流
合并位置包
丢弃过期非关键消息
降低广播频率
分线
分片
```

例如移动：

```text
同一玩家队列里
如果有10个未处理位置
```

可能只需要：

```text
最新一个
```

但：

```text
购买
交易
发奖
```

不能这样丢。

---

# 52. 为什么需要 Deadline

一个请求：

```text
PlayerAgent -> World
```

已经排了 2 秒。

客户端 1 秒前已经断开。

下游继续执行可能没有意义。

所以跨 Service RPC 可以携带：

```text
deadline
```

目标收到：

```text
如果已过期
直接拒绝
```

尤其适合：

```text
查询
非关键刷新
```

关键写操作不能简单超时即取消。

---

# 53. Debug Console 在线上为什么危险

当前：

```text
debug_console_port = 8000
```

开发环境非常有用。

但 Debug Console 支持的某些命令可以：

```text
执行call
inject
kill
exit
trace
```

如果暴露到公网，

等于给了：

```text
远程控制入口
```

正式配置：

```text
默认关闭
```

需要时：

```text
loopback
管理网络
权限
审计
```

---

# 54. LuaPanda 为什么不能作为生产诊断工具

LuaPanda：

```text
Hook Coroutine
改变执行时序
暂停Service
增加通信
```

非常适合：

```text
个人开发
```

不适合：

```text
生产常驻
```

生产更应该依赖：

```text
Metric
Trace
Structured Log
Core Dump
Profile
```

---

# 55. Core Dump 与 GDB 解决什么

如果进程：

```text
Crash
SIGSEGV
C Module内存错误
```

Lua 日志可能什么都没有。

需要：

```text
Core Dump
```

保存崩溃瞬间：

```text
C Stack
Thread
Register
Memory
```

GDB：

```bash
gdb ./third_party/skynet/skynet core.xxx
```

然后：

```gdb
thread apply all bt
```

先确认：

```text
Crash在哪个Native Thread
哪个C Module
```

---

# 56. Lua 死循环和 Native Crash 是两类问题

Lua Service：

```lua
while true do
end
```

可能：

```text
占用一个Worker
```

Skynet Monitor / Debug 工具可以帮助发现。

C Module：

```text
非法指针
越界
```

可能直接：

```text
Process Crash
```

需要：

```text
Core Dump / ASan / GDB
```

诊断方法完全不同。

---

# 57. Record / Replay 对 MMO 很有价值

有些线上 Bug：

```text
特定技能顺序
特定移动时序
特定断线
特定重复包
```

靠日志很难完整还原。

可以设计：

```text
按玩家录制输入命令
```

例如：

```text
timestamp
protocol
payload
connection_generation
scene_epoch
```

然后：

```text
在测试环境重放
```

注意：

```text
Replay ≠ 录所有生产包永久保存
```

要考虑：

```text
隐私
容量
采样
权限
```

---

# 58. 测试体系应该分层

当前：

```text
tests/unit
tests/integration
tests/benchmark
```

这个方向很好。

商业项目继续扩展：

```text
Unit
Integration
Regression
Load
Soak
Chaos
Replay
```

各自回答不同问题。

---

# 59. Unit Test

适合：

```text
AOI算法
Movement
Damage
Drop
Config Validator
Version比较
```

特点：

```text
快
确定
不启动完整Skynet
```

---

# 60. Integration Test

当前：

```text
tests/integration/smoke.sh
```

验证：

```text
真实Skynet
Gate
Sproto
登录
业务链
```

正式项目要加入：

```text
重连
顶号
切Scene
DB失败
重复请求
停服
```

---

# 61. Regression Test

每发现一个线上 Bug：

```text
先构造可稳定复现
```

然后：

```text
修复
```

最后把它留下。

例如 Offline Race：

```text
不能靠sleep碰运气
```

应该加 Barrier：

```text
Offline Coroutine
卡在Scene.leave后
    ↓
测试线程执行Reconnect
    ↓
释放Barrier
    ↓
验证旧Offline被取消
```

这种测试才可靠。

---

# 62. Benchmark 与 Load Test 要分开

Benchmark：

```text
测局部算法
```

例如：

```text
AOI Query
Serialize
Damage
```

Load Test：

```text
测完整系统
```

例如：

```text
10000连接
1000 move/sec
200 attack/sec
登录洪峰
```

两者不能互相替代。

---

# 63. MMO 压测不能只做“10000个连接不动”

这种只能证明：

```text
Socket连接数
Idle Agent内存
```

真实模型应该包含：

```text
登录
移动
AOI聚集
攻击
聊天
掉线
重连
保存
活动
```

并且比例接近业务。

---

# 64. 建议的负载模型

例如：

```text
10000 Online

70%
持续移动

10%
战斗

10%
挂机

5%
切图

5%
频繁上下线
```

同时设计：

```text
主城热点
Boss热点
副本分散
```

这比：

```text
随机均匀坐标
```

更接近真实 MMO。

---

# 65. 开服洪峰要单独压测

你以前也很熟悉这个现象：

```text
开服几分钟
```

压力不只是在线人数。

而是同时：

```text
登录
创建/加载玩家
配置初始化
活动
排行榜
邮件
DB查询
```

所以必须有：

```text
Login Ramp Test
```

例如：

```text
0 → 5000登录
60秒完成
```

观察：

```text
PlayerMgr
Storage
MySQL
Gate
CPU
mqlen
P99 login latency
```

---

# 66. Soak Test

短压测：

```text
10分钟
```

看不出：

```text
内存缓慢增长
GC恶化
Timer泄漏
Coroutine泄漏
连接泄漏
```

需要：

```text
6h
12h
24h
```

甚至更长。

观察：

```text
RSS趋势
Service数量
Coroutine
Mailbox
FD
DB连接
```

---

# 67. Chaos Test

故障注入：

```text
杀Scene
杀StorageWorker
断Cluster连接
MySQL延迟
MySQL断开
Gate重启
World重启
```

观察：

```text
玩家看到什么
状态是否正确
是否自动恢复
是否重复奖励
是否丢数据
```

Chaos 的重点不是：

```text
系统永不报错
```

而是：

```text
失败后状态边界明确
```

---

# 68. 容量规划不能只说“单机可以10万在线”

这种数字没有意义。

必须说明：

```text
硬件
Lua版本
Service模型
玩家业务量
AOI密度
消息频率
DB模式
```

例如：

```text
32 Core
64GB RAM
10000 Online
3 move/s/player
平均可见30
```

才有可比较性。

---

# 69. 容量模型可以怎样估

先拆：

```text
Memory
CPU
Network
DB
```

## Memory

```text
Base Process
+ Agent Count × Agent Memory
+ Scene Memory
+ Visible Relations
+ Socket Buffer
+ Queue
```

## CPU

```text
Move Cost
Attack Cost
AOI Fan-out
Serialize
GC
```

## Network

```text
C2S
S2C Push
AOI Broadcast
```

## DB

```text
Login Read
Periodic Save
Critical Operation
```

---

# 70. PlayerAgent 模型最终要不要改成 PlayerWorker

第二课讨论过。

不要凭：

```text
“10000 Lua State听起来很多”
```

就改。

正确流程：

```text
Benchmark
```

如果：

```text
每Agent 150KB
3000在线
```

约：

```text
450MB
```

可能完全可以接受。

如果：

```text
每Agent 1MB
20000在线
```

就明显不合理。

然后考虑：

```text
N Player / PlayerWorker
```

---

# 71. PlayerWorker 的代价

假设：

```text
128 PlayerWorker
```

每个管理：

```text
100~500 Player
```

优点：

```text
Lua State数量大幅减少
配置/Module重复减少
```

代价：

```text
玩家级串行要自己实现
单Worker Hotspot
一个Lua State GC影响多个玩家
故障影响面变大
```

所以没有绝对答案。

---

# 72. C/C++ 优化应该放在哪里

Skynet 并不要求：

```text
所有业务都Lua
```

非常适合 C/C++ 的部分：

```text
高密度AOI
Pathfinding
Collision
复杂技能计算
压缩
加密
协议Codec
大规模空间查询
成熟Native库
```

前提：

```text
Profile证明它是热点
```

---

# 73. C Module 不应该偷偷拥有业务权威状态

如果 C++ Module：

```text
自己保存Player HP
```

Lua Scene：

```text
也保存HP
```

又回到双 Owner。

更合理：

```text
Lua Scene拥有状态
C Module做算法
```

或者：

```text
C++完整拥有某类状态
Lua只通过明确接口访问
```

不能一半一半。

---

# 74. C++ Scene 与 Skynet Scene 的混合方案

对于非常重的 ARPG Scene，可以：

```text
Skynet
负责：
Node管理
Service路由
业务编排
World
Guild
Player业务

C++ Scene Module / C Service
负责：
AOI
Pathfinding
Combat Runtime
AI
```

这种混合架构是合理的。

你过去：

```text
C++底层
Lua玩法
```

的经验仍然有效。

Skynet 的价值可以集中在：

```text
Actor隔离
Service调度
跨模块通信
多节点组织
```

而不要求实时核心全部改成 Lua。

---

# 75. Hot Actor 的诊断顺序

发现：

```text
Scene P99变高
```

先看：

```text
mqlen
CPU
message rate
tick cost
AOI candidates
visible relations
GC
```

然后：

```text
Profile
```

确定热点。

再选择：

```text
算法优化
减少广播
降频
分线
Region
C/C++
```

不要先：

```text
加机器
```

---

# 76. Redis 要不要上

Redis 不是 Skynet 必选组件。

适合：

```text
跨进程短期共享
排行榜
Token
Session
缓存
```

不适合：

```text
每个Player实时状态全部塞Redis
Scene实时坐标
高频AOI
```

如果单节点/单服业务不需要：

```text
不要为了“商业架构”硬上
```

---

# 77. Rank 怎么做

你以前：

```text
SkipList + map
```

非常合理。

Skynet 中：

```text
Rank Service
```

可以成为 Owner。

如果：

```text
全服Rank
数据量中等
```

单 Rank Actor 可能够。

如果：

```text
大量实时排行榜
```

再：

```text
按榜分片
按区服分片
Redis ZSET
```

根据 Benchmark 选。

---

# 78. Guild 怎么做

错误：

```text
一个Guild = 一个Service
```

然后：

```text
100000 Guild
```

默认创建 100000 Lua State。

更实际：

```text
GuildShard 1
GuildShard 2
...
```

```text
guild_id % N
```

一个 Service 管多个 Guild。

当单 Guild 战争业务特别重时：

```text
再单独Actor化
```

Service 粒度仍然是容量参数。

---

# 79. Chat 怎么做

Chat 与 Scene：

```text
不要同步强耦合
```

聊天：

```text
World / Chat Service
```

适合异步。

附近聊天可能需要 Scene 提供：

```text
附近玩家列表
```

但不要：

```text
每条聊天同步call Scene再call几十个Agent
```

应该设计更低成本的分发方式。

---

# 80. Rank / Guild / Mail / Chat 的共同原则

这些系统的核心问题都不是：

```text
怎么写一个Service
```

而是：

```text
Owner是谁
Shard怎么分
高频路径有没有中央瓶颈
失败是否允许重试
消息是否需要可靠
```

第四课以后你应该用同一套方法审查所有系统。

---

# 81. 线上版本必须有 Build ID

日志和 Metric 至少记录：

```text
git commit
build time
config version
protocol version
```

否则线上出现：

```text
Player A正常
Player B异常
```

最后发现：

```text
两台机器不是同一版本
```

排查会非常痛苦。

---

# 82. Protocol Version

当前教学协议比较简单。

正式客户端上线以后必须考虑：

```text
Client Version
Protocol Version
Backward Compatibility
灰度
```

例如：

```text
v101客户端
v102服务器
```

是否还能登录？

必须有明确规则。

---

# 83. 灰度发布

不要：

```text
所有Game Node同时更新
```

建议：

```text
1台
    ↓
少量玩家
    ↓
观察
    ↓
扩大
```

监控：

```text
登录成功率
Crash
P99
Mailbox
DB Error
经济异常
```

异常：

```text
停止灰度
回滚
```

---

# 84. 回滚为什么不只是“换回旧二进制”

如果新版：

```text
修改了DB Schema
修改了玩家状态结构
修改了配置语义
```

直接运行旧版本可能无法读取。

所以发布设计必须同时考虑：

```text
Code Rollback
Data Compatibility
Config Rollback
State Migration
```

---

# 85. DB Schema Migration

推荐：

```text
向前兼容优先
```

例如新增字段：

```text
先DB增加Nullable/Default字段
    ↓
发布新代码
    ↓
稳定后再清理旧字段
```

不要在同一步：

```text
删旧字段
发布新代码
```

导致无法快速回滚。

---

# 86. 故障恢复：PlayerAgent Crash

如果单 PlayerAgent 异常退出：

```text
连接怎么办
Scene Entity怎么办
PlayerMgr映射怎么办
Dirty数据怎么办
```

商业项目必须定义。

可能：

```text
Gate断开玩家
Scene按Agent Down清理
PlayerMgr移除
玩家重连重新加载
```

不要假设：

```text
Service不会崩
```

---

# 87. Scene Crash

Scene Crash 比 PlayerAgent 严重。

要决定：

```text
Scene是否可重建
玩家是否踢回安全点
副本是否直接失败
世界Boss状态是否恢复
```

一般需要：

```text
Scene元数据
持久化checkpoint
或
明确“场景崩溃即失败”的业务规则
```

不是所有 Scene 都值得恢复。

---

# 88. Node Crash

整个 Node Crash：

```text
几千PlayerAgent同时消失
```

恢复策略可能：

```text
Gate检测断开
玩家客户端重连
路由重新分配
Agent重新加载
Scene重新进入
```

这和你以前：

```text
GameServer崩溃
玩家统一掉线
重新登录
```

非常接近。

商业系统不一定要做：

```text
无感现场恢复
```

恢复成本要和产品需求匹配。

---

# 89. 不要追求“所有故障都自动恢复”

对于：

```text
普通H5 MMO
```

可能：

```text
玩家断线重登
日志补偿
```

已经足够。

对于：

```text
高价值跨服赛事
```

可能需要：

```text
Checkpoint
Replay
State Replication
```

工程投入完全不同。

架构要服从业务价值。

---

# 90. 生产前必须有故障表

建议每个重要 Service 都写：

```text
Owner State
Failure Effect
Recovery
Data Loss Window
Retry Safety
Monitoring
```

例如：

```text
PlayerAgent

Owner:
玩家在线状态

Crash:
单玩家掉线

Recovery:
重新登录重新load

Data Loss:
最后一次Snapshot以后普通状态

Critical Economy:
由Ledger恢复
```

这种表比画更多架构图更实用。

---

# 91. 一个商业 MMO 的 Service Review Checklist

每增加 Service，检查：

```text
1. 它拥有哪份独占可变状态？
2. 为什么必须独立生命周期？
3. 哪些调用是call？
4. 哪些调用是send？
5. 所有yield点在哪里？
6. 恢复后哪些数据可能失效？
7. 它会不会成为Hot Actor？
8. 它的失败影响多少玩家？
9. 是否需要分片？
10. 是否需要Version / Epoch？
11. 是否可以重试？
12. 重试是否幂等？
13. 如何监控？
14. 如何压测？
15. 如何停服？
```

能回答完，再拆。

---

# 92. 从当前仓库到生产架构的推荐演进顺序

## Phase 1：保持单节点

补齐：

```text
Player生命周期状态机
Versioned Snapshot
Dirty Save
Structured Log
Metrics
更多Regression Test
```

## Phase 2：经济可靠性

补：

```text
Operation ID
Ledger
关键事务
重复请求
审计
```

## Phase 3：生产可观测

补：

```text
Trace
Dashboard
Alert
Core Dump
Profile
Replay
```

## Phase 4：多节点

先拆：

```text
DB Node
World Node
```

再根据 Profile：

```text
Scene Node
Player Node
Gate Node
```

## Phase 5：容量优化

根据数据决定：

```text
PlayerAgent → PlayerWorker？
Scene分线？
Region？
C/C++？
Redis？
```

而不是提前决定。

---

# 93. 推荐的生产目录演进

当前：

```text
service/
lualib/
config/
tests/
```

可以继续演进：

```text
service/
├── gateway/
├── player/
├── scene/
├── storage/
├── world/
├── guild/
├── rank/
├── chat/
├── system/
│   ├── shutdown_mgr.lua
│   ├── hotfix_mgr.lua
│   └── monitor.lua
└── router/

lualib/
├── protocol/
├── scene/
├── config/
├── router/
├── persistence/
├── economy/
├── metrics/
└── common/

config/
├── game.lua
├── cluster.lua
├── production.lua
└── staging.lua

tests/
├── unit/
├── integration/
├── regression/
├── benchmark/
├── load/
└── chaos/
```

这只是建议结构。

不要为了目录漂亮先创建一堆空模块。

---

# 94. 建议的生产启动链

当前：

```text
service/main.lua
```

直接启动所有模块。

多节点后应该按 Node Role：

```text
ROLE=gate
ROLE=player
ROLE=scene
ROLE=world
ROLE=db
```

启动不同 Service。

例如：

```text
main.lua
    ↓
读取node_role
    ↓
common services
    ↓
role bootstrap
```

建议：

```text
service/bootstrap/gate_node.lua
service/bootstrap/player_node.lua
service/bootstrap/scene_node.lua
service/bootstrap/db_node.lua
```

不要把：

```text
if role == ...
```

写成几百行 main.lua。

---

# 95. 一个 Node Bootstrap 示例

**建议新增**：

```text
service/bootstrap/scene_node.lua
```

```lua
local skynet = require "skynet"
local cluster = require "skynet.cluster"

local M = {}

function M.start(conf)
    local scene_mgr =
        skynet.uniqueservice("scene/scene_mgr")

    skynet.call(
        scene_mgr,
        "lua",
        "start"
    )

    cluster.register(
        "scene_mgr",
        scene_mgr
    )

    return true
end

return M
```

这里只展示思路。

正式项目还要：

```text
cluster.open
节点注册
健康状态
优雅停服
```

---

# 96. Cluster Name 不是完整服务发现系统

Skynet：

```text
cluster.register
cluster.query
```

可以做节点间名字访问。

但商业项目还要处理：

```text
节点上下线
动态Scene
Shard
负载
故障转移
版本
```

这些通常需要自己的：

```text
Router / Registry逻辑
```

不要假设：

```text
有cluster.register
就自动拥有完整Service Discovery
```

---

# 97. 跨节点调用的 Retry 原则

最重要规则：

```text
读操作
通常更容易Retry

写操作
不能盲Retry
```

例如：

```text
query_rank
```

超时可以重试。

但：

```text
deduct_gold
```

如果：

```text
目标已经执行
Response丢了
```

重试会重复扣。

所以写操作必须：

```text
Operation ID + Idempotency
```

以后才能安全重试。

---

# 98. Timeout 也不等于“目标没执行”

这是分布式系统最容易误判的问题。

```text
Caller Timeout
```

只说明：

```text
Caller没有及时收到Response
```

不能推出：

```text
Target没执行
```

所以：

```text
超时后回滚本地
```

之前必须知道目标的业务协议。

---

# 99. 跨节点 Scene Transfer 建议测试的故障点

依次注入：

```text
Target Prepare后断线
Source Freeze后Target崩溃
Target Commit后Route更新失败
Route更新后Source Cleanup失败
Client重连发生在Transfer中
```

每种情况都回答：

```text
玩家在哪个Scene
哪个Epoch有效
谁负责清理旧Entity
```

能回答清楚，协议才算设计完成。

---

# 100. 最终生产架构并不一定比你以前复杂很多

你以前：

```text
Gate
Game
Chat
DB
Center
公共服
```

已经包含商业服务器最重要的边界。

Skynet 的变化更多是：

```text
Game
```

内部可以进一步拆：

```text
PlayerActor
SceneActor
WorldActor
```

并让它们共享 Worker Pool。

所以学 Skynet 的目的不应该是：

```text
把所有旧经验换掉
```

而是：

```text
把Actor隔离
Coroutine
Mailbox
Service调度
Cluster
```

这些能力加入你已有架构判断里。

---

# 101. 四课最终能力检查

学完四课以后，你应该能独立回答以下问题。

## Runtime

```text
Skynet从main到service/main.lua怎么启动？
snlua是什么？
一个Lua Service怎样创建Lua State？
Worker怎样调度Mailbox？
```

## Actor

```text
Service和线程什么关系？
call为什么会yield？
Service为什么仍然会出现逻辑竞态？
queue解决什么，不解决什么？
```

## MMO

```text
PlayerAgent和Scene谁拥有什么状态？
为什么AOI/Combat留在Scene？
Hot Scene怎么判断？
Grid如何退化？
```

## Storage

```text
为什么普通状态用Snapshot？
为什么关键经济数据需要Ledger？
Version和Operation ID分别解决什么？
```

## Cluster

```text
什么时候该拆Node？
cluster.call为什么不能当成本地call？
Scene Transfer如何处理失败？
```

## Production

```text
怎么监控Mailbox？
怎么定位P99？
怎么分析Lua内存？
怎么做Core Dump？
怎么压测？
怎么灰度？
怎么回滚？
```

如果这些问题可以不看文档独立分析，

你已经具备：

```text
用Skynet负责一个真实MMO Server项目
```

所需要的核心知识框架。

---

# 102. 最后一个完整案例：玩家购买道具后切图，期间节点故障

把四课内容全部串起来。

玩家：

```text
10001
```

在：

```text
PlayerNode1
```

发送：

```text
BUY item 5001
```

## Step 1：Gate

```text
Gate收到Sproto
```

验证：

```text
connection_id
```

路由：

```text
PlayerAgent
```

## Step 2：PlayerAgent

进入：

```text
serial
```

避免同玩家业务重入。

生成/读取：

```text
operation_id
```

## Step 3：读取价格

如果价格来自共享配置：

```text
sharedata
```

本地读取。

不要为静态价格：

```text
call Shop Service
```

## Step 4：校验当前金币

不能使用：

```text
yield之前缓存的old_gold
```

而应在提交前：

```text
重新读当前player.gold
```

## Step 5：关键经济落盘

发送：

```text
operation_id
player_id
before
after
item
```

给 Storage/Economy Owner。

DB 使用：

```text
Transaction
+ Unique operation_id
```

## Step 6：DB Commit 成功但 Response 丢失

PlayerAgent：

```text
call timeout
```

不能判断：

```text
“DB没执行”
```

重试时：

```text
相同operation_id
```

DB 返回：

```text
已执行结果
```

避免重复扣。

## Step 7：购买成功

PlayerAgent：

```text
更新内存金币/背包
state_version++
dirty=true
```

返回 Client。

## Step 8：玩家请求切图

PlayerAgent 查询：

```text
Scene Route
```

目标：

```text
SceneNode2
Scene 2001
Epoch 8
```

## Step 9：Transfer

```text
Target Prepare
Source Freeze
Target Commit
Route Update
Source Cleanup
```

每阶段使用：

```text
transfer_id
scene_epoch
```

## Step 10：SceneNode2 在 Commit 后崩溃

Router发现：

```text
Scene Epoch 8失效
```

恢复策略由业务定义：

```text
重建Scene
或
把玩家送安全地图
```

旧 Epoch 消息全部拒绝。

## Step 11：玩家重连

Gate 获得：

```text
new connection_id
```

PlayerAgent 如果仍在：

```text
重新bind
```

如果 PlayerNode 也已重启：

```text
重新load Snapshot
```

关键购买不会丢：

```text
Ledger已Commit
```

普通最后位置是否回退取决于：

```text
最近Snapshot
```

## Step 12：线上排查

如果玩家投诉：

```text
“买了东西，切图后掉线”
```

查：

```text
trace_id
operation_id
player_id
scene_epoch
build_id
```

可以得到完整链：

```text
Purchase Commit
    ↓
Transfer Commit
    ↓
SceneNode Crash
    ↓
Reconnect
```

而不是只能翻几千行文本日志。

这就是第四课的最终目标：

```text
业务正确性
+
失败可恢复
+
问题可定位
+
性能可测
+
版本可控制
```

---

# 103. 第四课实操一：给 PlayerAgent 加 Versioned Dirty Save

修改：

```text
service/player/player_agent.lua
```

增加：

```text
state_version
saved_version
dirty
```

要求：

```text
任何持久状态修改
state_version++

Save时记录saving_version

Response回来
只有当前version仍相同时
才能clear dirty
```

测试：

```text
Save进行中
插入一次金币变化
Save返回
dirty仍然必须为true
```

---

# 104. 第四课实操二：实现 Operation ID 幂等购买

建议新增：

```text
lualib/economy/operation.lua
service/economy/economy_service.lua
tests/regression/test_duplicate_purchase.lua
```

要求：

```text
相同operation_id请求10次
最终只扣一次
只发一次
```

模拟：

```text
DB Commit成功
Response故意丢失
Caller Retry
```

---

# 105. 第四课实操三：实现 Config Version

修改：

```text
service/config/config_service.lua
lualib/config/game_data.lua
```

配置增加：

```text
version
```

实现：

```text
validate
publish
rollback
```

测试：

```text
非法grid_size
非法monster id
非法version回退
```

必须在发布前拒绝。

---

# 106. 第四课实操四：建立 Service Metrics

建议新增：

```text
service/system/monitor.lua
lualib/metrics/metrics.lua
```

至少周期收集：

```text
Scene players
Scene entities
Scene tick cost
Storage latency
Player count
```

再从 Debug API 采样：

```text
mqlen
cpu
message
```

注意 Metric Label 基数。

---

# 107. 第四课实操五：设计一个 Cluster 双节点实验

新增：

```text
config/cluster.lua
config/player_node.lua
config/scene_node.lua
```

启动：

```text
Player Node
Scene Node
```

让：

```text
PlayerAgent
```

通过：

```text
cluster.call
```

执行一次：

```text
Scene.move
```

然后：

```text
杀Scene Node
```

观察：

```text
call错误
PlayerAgent状态
Client Response
```

不要先做自动 Retry。

先理解真实失败。

---

# 108. 第四课实操六：完整压测

至少三组：

```text
Idle Online
Move Heavy
Hot Scene
```

记录：

```text
硬件
Commit
配置
Online
QPS
P50/P95/P99
CPU
RSS
Mailbox
GC
Network
DB
```

没有这些条件的：

```text
“支持X万人”
```

不进入结论。

---

# 109. 第四课自测题

1. `cluster.call` 与 `skynet.call` 最大的失败模型差异是什么？
2. 为什么跨节点写操作不能超时后直接重试？
3. Scene Route 为什么需要 `epoch`？
4. Scene Transfer 为什么不能简单 `leave -> enter`？
5. Dirty Save 为什么需要 `state_version`？
6. `saved_version` 与 `state_version` 分别是什么？
7. Operation ID 解决什么，DB Transaction 解决什么？
8. 为什么位置数据和付费数据不能采用完全相同的持久化策略？
9. 为什么 `sharedata.update` 不等于完整热更新？
10. Config Hot Reload 与 State Migration 有什么区别？
11. Code Hotfix 为什么比 Config Reload 风险高？
12. 为什么大量 PlayerAgent 会带来 Lua State 基础内存问题？
13. 为什么 `collectgarbage("count")` 不能代表进程总内存？
14. Scene GC 与 PlayerAgent GC 的优化重点有什么区别？
15. `mqlen` 持续增长说明什么？
16. 为什么单 Scene Hot Actor 加 Worker 没用？
17. 什么数据适合 Metric，什么数据适合 Log/Trace？
18. 为什么 `player_id` 通常不应该作为 Metric Label？
19. LuaPanda 为什么不适合 Production？
20. Core Dump 能解决哪些 Lua 日志解决不了的问题？
21. Benchmark 与 Load Test 的区别是什么？
22. 为什么 MMO 压测必须加入热点聚集？
23. PlayerWorker 能降低什么成本，又会引入什么风险？
24. 哪些热点适合 C/C++，哪些状态不应该偷偷搬进 C++？
25. Redis 为什么不是 Skynet 商业化的必选项？
26. Guild 为什么不一定一 Guild 一 Service？
27. 灰度发布为什么必须记录 Build ID / Config Version？
28. 回滚为什么不仅仅是换旧二进制？
29. PlayerAgent Crash 与 Scene Crash 的恢复策略为什么不同？
30. 什么情况下“不做现场恢复、让玩家重登”反而是合理商业选择？

## 自测题参考答案

当前仓库尚未实现 Cluster、Versioned Dirty Save、Operation Ledger、生产 Metrics 和热更管理器。下面对已有代码标明准确路径与行号；未实现部分给出应有的协议、状态机和验证条件，不把设计稿写成现有功能。

1. **`cluster.call` 与 `skynet.call` 的主要失败模型差异**

   本地 `skynet.call` 仍可因目标 Service 退出、错误或不回复而失败，但请求和回复在同一 Runtime 内用 session 匹配。`cluster.call` 增加了名字解析、跨节点连接、网络分区、远端节点重启、路由变更和 Response 在网络上丢失等不确定性。调用方看到超时/断线时，只能确认“没有收到可用 Response”，不能确认远端业务没执行。

2. **跨节点写超时后不能直接重试**

   超时可发生在请求到达前、远端执行中、Commit 后回复前或 Response 返回途中。如果“扣金币并发道具”已 Commit，无幂等保护的重试会再执行一次。写请求应携带稳定 `operation_id`，服务端在同一事务中记录 Operation 与业务变更，重试先查原结果。不能幂等的命令要进入 `UNKNOWN`/对账流程，不应由通用 Router 无脑重发。

3. **Scene Route 需要 `epoch`**

   Service Address 只能表示当前实例，不能区分迁移前后的所有权代次。Route 应至少包含 `{scene_id, node, address, epoch}`。Scene 重建或迁移时 epoch 单调增长，Move、Timer、Transfer Commit 等消息携带它；新 Owner 拒绝低于当前 epoch 的迟到消息，避免旧 Scene 在路由更新后继续写状态。

4. **Scene Transfer 不能简化为 `leave -> enter`**

   直接 leave 会先丢掉源 Scene 的可恢复现场；随后目标 Scene enter 若超时或失败，玩家可能同时不属于任何 Scene。反过来先 enter 再 leave，又可形成双 Owner。可用协议是 Source Freeze/Prepare→Target Prepare（创建不可见副本）→持久化或 Router CAS Commit 新 epoch→Target Activate→Source Retire。每步都要幂等，并定义超时后查询当前 epoch 的恢复方式。

5. **Dirty Save 需要 `state_version`**

   Save 发出时 Agent 会 yield，期间新消息可修改玩家状态。如果任何 Save 成功都直接 `dirty=false`，则新变更会被误标为已落盘。发送不可变 Snapshot 时记录 `saving_version = state_version`，Response 返回后只推进 `saved_version` 到该版本；仅当 `saved_version == state_version` 才能清 dirty。当前 `service/player/player_agent.lua:193-210` 只有下线最终 Save，没有这套保护，是第四课实操要补的部分。

6. **`saved_version` 与 `state_version`**

   `state_version` 表示 Agent 内存中最新已提交持久状态的版本，每次这类状态变更后增加。`saved_version` 表示已被 Storage 确认持久的最高版本。`state_version > saved_version` 就是 dirty的真正来源；`dirty` 可作缓存标志，但不应成为唯一真相。DB 更新还应用 `WHERE version = expected_version` 或等价 CAS，防止多实例时的旧 Snapshot 覆盖。

7. **Operation ID 与 DB Transaction 解决不同问题**

   DB Transaction 保证一次尝试中多条数据库变更的原子性和隔离性，例如扣金币、增道具、写 ledger 同成同败。Operation ID 识别“这次重试是否是上次同一个业务操作”，用唯一约束和已存结果屏蔽重复执行。事务没有 Operation ID，连续两次重试可以各自成功提交；Operation ID 没有事务，则可出现幂等记录与业务变更部分成功。

8. **位置与付费数据需要不同持久化策略**

   位置是高频、可从检查点或安全点恢复、通常可容忍少量回退的 Snapshot 数据，可 Dirty Save 合并写。付费、交易、金币消耗要求可审计、幂等和可对账，应使用 Operation ID、Ledger 以及事务性更新。用每次 Move 同步 DB 会让 DB 进入 Scene 热路径；用定时 Snapshot 保存付费结果，崩溃时则可丢资产或重复发货。

9. **`sharedata.update` 不等于完整热更**

   `sharedata.update` 解决的是同节点多 Lua State 看到新共享配置的发布机制。它不自动做 Schema 验证、引用完整性检查、版本单调、业务原子切换、已创建 Entity 迁移、跨节点一致发布和回滚。当前 `service/config/config_service.lua:6-10` 只用 `sharedata.new` 发布启动配置，`lualib/config/game_data.lua` 也没有 version，还不具备热更流程。

10. **Config Hot Reload 与 State Migration**

    Config Reload 是让后续读取获得新规则，例如新怪物模板或掉落表。State Migration 是把已存在的运行态对象从旧 Schema/旧语义转成新形态，例如已出生 Monster 的 HP 如何处理、已在冷却的技能是否重算。发布新配置不会自动改变 Scene 内已复制的 `spawn_cfg`、Timer 或 PlayerAgent 状态；每个配置类型必须定义“仅新对象生效”还是执行明确迁移。

11. **Code Hotfix 风险高于 Config Reload**

    代码热修会替换正在运行的函数和可能被 upvalue 引用的 Module table，而不同 coroutine 可分别停在旧函数与新函数中。运行态 table 的形状、协议前后置条件和已注册 callback 也可能不兼容。Config Reload 也有语义风险，但更容易约束为不可变数据版本切换。代码热修应限制范围、校验 Build ID/函数签名，记录审计，并在无法证明安全时用滚动重启代替。

12. **大量 PlayerAgent 的 Lua State 基础内存**

    每个 snlua Service 由 `third_party/skynet/service-src/service_snlua.c:502-511` 创建自己的 `lua_State`，还有 Context、Mailbox、coroutine、Module table、Sproto 对象和 Agent local 状态。一玩家一 Agent 时，这些固定成本与在线人数近似线性增长，即使玩家空闲也存在。应分别测空 Agent 增量、加载玩家后增量、GC 费用和创建/销毁洪峰，再判断是保留 Agent 还是分片 PlayerWorker。

13. **`collectgarbage("count")` 不等于进程总内存**

    它主要反映当前 Lua State 由 Lua GC 跟踪的 KB 数。进程 RSS 还包含其他 Service 的 Lua State、C Runtime、socket buffer、数据库库、C Module 自行分配、线程栈、allocator 碎片和已释放但尚未还给 OS 的页。Skynet 的 snlua allocator 在 `third_party/skynet/service-src/service_snlua.c:482-499` 单独统计 Service Lua 分配，但生产分析仍要结合 Debug Console `mem/cmem`、进程 RSS/PSS 和 native profiler。

14. **Scene GC 与 PlayerAgent GC 优化重点**

    Scene 是高频集中 Actor，关注 Move/Tick/AOI 热路径临时 table、候选集和 Push payload 的分配率，以及单次 GC 停顿对 Mailbox 和 Tick budget 的影响。例如 `service/scene/scene.lua:43-56` 每次 `collect_visible` 都创建 result，`lualib/scene/aoi_grid.lua:82-95` 还创建 Candidate table。PlayerAgent 数量多但单个通常低频，更关注每 Lua State 常驻基线、长寿命玩家 table、pending pushes 和大量 Agent 分散 GC 对总 CPU/RSS 的累计成本。

15. **`mqlen` 持续增长的含义**

    它表示该 Service 消息到达速率在观测窗口内持续高于处理速率，是排队与延迟增长的证据，不直接等于 CPU 不足。原因可以是流量洪峰、单条消息计算变慢、下游 `call` 长时间等待、GC 或单 Actor 超载。应把 `mqlen` 与消息进/出速率、handler 耗时、当前 task 等待图、CPU 和下游延迟放在同一时间线上判断。

16. **单 Scene Hot Actor 加 Worker 无效的原因**

    单 Scene 的权威 table 和 Mailbox 仍只能由该 Service 串行提交，Worker 数提高的是多 Service 间的并行度。单 Scene 在没有 yield 的 CPU 热路径上已经吃满一个执行时间片时，其他 Worker 不能同时修改它的 `entities/visible`。先做 profile 和负载整形，再考虑分线、实例化或 Region Partition；盲目加 Worker 还可能增加调度与 cache 干扰。

17. **Metric 与 Log/Trace 的分工**

    Metric 适合可聚合、低基数、需持续看趋势和告警的值，如 Scene `mqlen`、玩家数、Move latency histogram、Storage error counter。Log 适合记录离散事件、错误上下文和审计事实；Trace 适合还原一次请求跨 Gate、Agent、Scene、Storage 的时序和 yield 等待。高基数 ID 作为 Log/Trace 字段便于查询，不应进入 Metric label。

18. **`player_id` 不应作为 Metric Label**

    Label 组合会生成时间序列。10 万或数百万玩家 ID 会使指标存储、索引、聚合查询和传输成本失控，离线后序列仍可长期留存。指标用 node、service_type、scene_bucket、result_code 等有界 label；某个玩家的详情用带 `trace_id/request_id/player_id` 的结构化日志或 Trace 查。

19. **LuaPanda 不适合 Production**

    调试器需要加载额外 Lua/C 组件、建立调试端口，并通过 hook/断点改变 coroutine 调度和时序。断在 Scene 热路径会阻断业务处理，调试端口还扩大了攻击面。本工程只有显式选择 `scripts/linux/run_luapanda_server.sh` 和 `config/debug_luapanda.lua` 才启用，正常/测试/生产启动路径不应包含它。生产使用结构化日志、Metrics、Trace、受控状态检查、Profile 和 Core Dump。

20. **Core Dump 能补足 Lua 日志的部分**

    Native Crash、SIGSEGV、C Module 越界、栈损坏、allocator 状态、线程死锁和崩溃时所有 native 线程栈，往往来不及由 Lua 日志完整记录。带匹配 Build ID/符号的 Core Dump 可由 GDB 查 backtrace、寄存器、栈帧和内存。它不会自动还原长时间的业务时序，对纯 Lua 逻辑错误也仍需要 Log/Trace/Record-Replay 补充。

21. **Benchmark 与 Load Test**

    Benchmark 通常隔离某个算法或组件，固定输入、预热和环境，用于比较修改前后的 throughput、latency、allocation。`tests/benchmark/aoi_bench.lua` 就是 AOI query 微基准。Load Test 驱动完整服务链，关注在线、流量模型、P95/P99、错误率、Mailbox、DB/网络瓶颈和背压。微基准快不证明整服务可承载目标在线。

22. **MMO 压测必须包含热点聚集**

    均匀分散的玩家会把流量分到多个 Scene/Cell，掩盖世界 Boss、主城和攻城战中的单 Scene Hot Actor。聚集时 Candidate/Visible 可接近 N，每次 Move/技能的广播也可接近 N，总成本趋近事件率与可见人数的乘积。压测应分 Idle Online、均匀 Move、中心聚集、单 Cell 极端聚集和开服登录洪峰，否则得到的“支持 X 万人”不包含最重要的战斗场景。

23. **PlayerWorker 的收益和风险**

    将多个玩家分片到一个 PlayerWorker 可减少 Lua State、Service Context、Mailbox 和重复 Module/Sproto 常驻内存，降低 Agent 创建销毁洪峰。代价是多个玩家共用一个 Mailbox/GC 域，某个玩家的慢路径可拖累整个分片；需自己维护每玩家串行 queue、生命周期、Timer generation 和错误隔离。应先以 10 万 Agent 的 RSS/GC/延迟实测证明固定成本是瓶颈，再接受集中化带来的故障域扩大。

24. **适合 C/C++ 的热点与不应偷偷迁移的状态**

    适合的是 profile 确认的纯计算或紧凑数据路径，如大批量几何查询、路寻找、压缩/解压、序列化和特定索引；输入输出应清晰，可做确定性测试。Player 持久状态、Scene 权威 Entity/HP/位置、Operation Ledger 状态不应在无版本和生命周期协议的 C++ singleton/cache 中另存一份。C Module 应是可替换的计算加速层，权威 Owner 仍在架构上显式可见。

25. **Redis 不是 Skynet 商业化的必选项**

    Redis 可用于具体需求：带 TTL 的共享临时状态、跨节点缓存、某些排行榜结构或协调数据。但 Skynet 已有 Service/Mailbox/Timer，稳定持久化仍可由 MySQL 和 Ledger 完成。没有明确访问模式就引入 Redis，只会增加新的双写一致性、内存容量、过期、集群故障和运维成本。先说清 Owner、一致性级别、失效恢复和容量，再决定是否需要它。

26. **Guild 不一定一 Guild 一 Service**

    低活跃公会数量可非常大，一公会一 Lua State/Context 的常驻成本可高于业务计算，大量冷 Guild 也没有并行价值。可以按 `guild_id` 分片到 GuildWorker，每个 Guild 内串行，热 Guild 再单独迁移/升级。一 Guild 一 Service 何时合理，取决于在线 Guild 数、消息频率、单 Guild 状态量、需要的故障隔离和实测内存，不是概念名称。

27. **灰度发布要记录 Build ID / Config Version**

    灰度期同时运行多个代码与配置组合。每条结构化日志、Trace 和核心 Metric 需带低基数版本字段，才能把错误率/延迟回归精确归因到某个二进制或配置。玩家路由或 Scene 迁移还要检查 Protocol/State Schema 兼容。没有版本证据时，即使看到灰度组异常，也无法区分代码、配置、数据迁移或流量分布差异。

28. **回滚不只是换旧二进制**

    新版可能已写入旧代码不识别的 DB Schema/枚举/状态，发布新 Protocol，更新配置，或已执行不可逆经济操作。直接启旧进程可读错数据、破坏幂等约束或无法与新客户端通信。发布设计要优先采用 expand/migrate/contract 的向前向后兼容迁移，为代码、配置、协议、Schema 和状态各自定义回退或向前修复策略。

29. **PlayerAgent Crash 与 Scene Crash 的恢复策略不同**

    PlayerAgent 主要 Owner 是单玩家持久状态，可从最新 Versioned Snapshot + Ledger 重建，再向当前 Scene 查询或重进场；故障域通常是一名玩家。Scene 拥有大量玩家/怪物的实时位置、Visible Set、战斗和 Timer，这些可能没有逐帧持久化；Scene Crash 的故障域是整个地图实例。无完整 Event Log/检查点时，更可靠的策略往往是宣告该 epoch 失效，让玩家回安全点或重登，而不是伪造一个看似连续的 Scene。

30. **让玩家重登可以是合理选择**

    当故障影响范围可控，重登能从经过校验的持久状态重建，且强行现场恢复可能引入双 Owner、重复奖励、错误 HP/坐标或更长停服时，主动中断会比猜测现场更安全。前提是重登路径本身已压测，Operation 可幂等，客户端能给出明确反馈，服务端记录原因和影响玩家，并有补偿/对账流程。对付费扣款、交易和稀有道具等不可模糊的操作，仍必须查 Operation Ledger，不能用“重登”掩盖未知提交结果。

---

# 110. 四课最终验收项目

如果你真的想确认自己已经掌握，而不是“看完了四份文档”，建议最后独立完成一个小型商业形态工程：

```text
2个Skynet Node

Node A
Gate
Player

Node B
Scene
Storage

MySQL

功能：
登录
顶号
重连
移动
AOI
战斗
怪物
购买
Dirty Save
Operation ID
Scene Transfer
Graceful Shutdown

工程：
Unit Test
Regression Test
Integration Test
Load Test
Metrics
Structured Log
Core Dump
GDB
Config Version
```

再故意做：

```text
杀Scene Node
杀Player Node
断MySQL
重复购买
切图中断线
Save过程中修改状态
```

如果你可以：

```text
预测结果
定位问题
解释状态Owner
修复并留下Regression Test
```

四课的学习目标才真正完成。

---

# 附录 A：当前仓库已存在与第四课建议新增的边界

## 当前已经存在

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
service/config/config_service.lua
lualib/config/game_data.lua
tests/unit/
tests/integration/
tests/benchmark/
scripts/linux/test.sh
scripts/linux/benchmark_aoi.sh
```

## 本课建议新增，但当前仓库并不存在

```text
config/cluster.lua

service/bootstrap/gate_node.lua
service/bootstrap/player_node.lua
service/bootstrap/scene_node.lua
service/bootstrap/db_node.lua

service/system/shutdown_mgr.lua
service/system/hotfix_mgr.lua
service/system/monitor.lua

service/economy/economy_service.lua

lualib/router/service_router.lua
lualib/economy/operation.lua
lualib/metrics/metrics.lua

tests/regression/
tests/load/
tests/chaos/

sql/ledger.sql
```

不要因为教程列出了这些文件，就一次性全部创建。

按实际练习逐步增加。

---

# 附录 B：本课重点上游源码

Skynet v1.8.0：

```text
third_party/skynet/lualib/skynet/cluster.lua
third_party/skynet/service/clusterd.lua

third_party/skynet/lualib/skynet/sharedata.lua
third_party/skynet/service/sharedatad.lua

third_party/skynet/lualib/skynet/debug.lua
third_party/skynet/service/debug_console.lua

third_party/skynet/lualib/skynet/db/mysql.lua
```

建议阅读顺序：

```text
cluster.lua
    ↓
clusterd.lua

sharedata.lua
    ↓
sharedatad.lua

debug.lua
    ↓
debug_console.lua

service/storage/mysql_worker.lua
    ↓
skynet/db/mysql.lua
```

---

# 附录 C：一次生产 Review 固定回答的问题

以后不管你写：

```text
Guild
Rank
Mail
Trade
Auction
CrossServer
Activity
```

都可以固定回答：

```text
1. 状态Owner是谁？
2. Service边界为什么这样划？
3. 高频路径是什么？
4. 哪些地方yield？
5. yield后哪些数据会过期？
6. call是否必须？
7. send能不能替代？
8. 是否需要Version？
9. 是否需要Operation ID？
10. 失败时留下什么状态？
11. 重试安全吗？
12. 如何恢复？
13. 如何监控？
14. 如何压测？
15. 容量上限由什么决定？
16. 如何灰度？
17. 如何回滚？
```

如果这些问题都回答不出来，

架构图画得再漂亮也没有意义。

---

# 附录 D：四课总路线

```text
第一课
Skynet怎么启动
Native / Lua / snlua / bootstrap / Worker

        ↓

第二课
Skynet业务怎么组织
Service / Actor / Mailbox / Coroutine / State Owner

        ↓

第三课
MMO实时世界怎么运行
Scene / AOI / Move / Monster / Combat / Tick

        ↓

第四课
怎么把学习工程变成可运营系统
Cluster / Storage / Idempotency / Hot Reload
GC / Observability / Failure / Load / Release
```

完成第四课以后，下一阶段不应该继续“第五课讲更多 Skynet API”。

更有价值的是：

```text
直接做一个完整子系统
```

例如：

```text
Guild
交易行
跨服战场
世界Boss
```

然后按四课建立的同一套方法做：

```text
设计
实现
测试
压测
故障注入
上线评审
```

到这里，Skynet 才从“学习对象”变成你的工程工具。
