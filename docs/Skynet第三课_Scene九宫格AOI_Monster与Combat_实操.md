# Skynet 第三课配套实操：从双客户端 AOI 到 Hot Scene 基准

实操沿一名玩家进场、移动、离开视野、攻击 Slime 和怪物刷新的实际消息路径展开。Scene 中 `entities/grid/visible/move_state` 的提交段不增加 `skynet.call`，所有观测代码也要考虑热路径成本。行号以当前工作树为准。

## 1. 先验证纯 Lua 算法层

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
./third_party/skynet/3rd/lua/lua tests/unit/run.lua
```

逐个对照：

- `tests/unit/test_aoi_grid.lua:9-25` 覆盖插入、3×3 Candidate、跨 Cell、同 Cell 不重链和重复 remove。
- `tests/unit/test_movement.lua:12-35` 覆盖出生点边界、越界、超速、同 tick 重复消耗和 Token Bucket 补充上限。
- `tests/unit/test_combat.lua:3-7` 覆盖 3-4-5 距离边界与确定性伤害。

`lualib/scene/aoi_grid.lua`、`movement.lua`、`combat.lua` 都是普通 Module，可在没有 Skynet Runtime 的独立 Lua 进程中测试。这里只证明算法契约，不证明 Service 消息顺序和 Push 正确，后者由集成实验覆盖。

逐个函数建立输入、Owner 和副作用表：

| 完整仓库路径与函数 | 输入 | 修改的状态 | 是否可能 yield |
|---|---|---|---|
| `lualib/scene/aoi_grid.lua::Grid.insert` | entity key、坐标 | `cells`、`entity_cell` | 否 |
| `lualib/scene/aoi_grid.lua::Grid.move` | entity key、新坐标 | 跨 Cell 时修改索引 | 否 |
| `lualib/scene/aoi_grid.lua::Grid.query_3x3` | 查询坐标 | 只创建 Candidate table | 否 |
| `lualib/scene/movement.lua::try_move` | Scene 配置、Entity move_state、目标坐标、tick | 成功时提交移动额度和坐标；拒绝时也更新额度时间 | 否 |
| `lualib/scene/combat.lua::in_range` | 两个 Entity Snapshot、范围 | 无 | 否 |
| `lualib/scene/combat.lua::player_damage` | Player Snapshot | 无 | 否 |

这些 Module 在 Scene Lua State 内普通调用。它们没有 Address、Mailbox 和独立生命周期；把 Grid 或伤害公式拆成 Service，会把当前无 yield 的提交段改成跨 Actor RPC。

## 2. 启动服务器并捕获 Scene 基线

Terminal A：

```bash
./scripts/linux/run_server.sh
```

启动日志应包含 `[Scene] initialized id=1 grid=20 view=18`，对应 `service/scene/scene.lua:88-111`。初始化先在 `:90-95` 获取 sharedata 配置并验证 `grid_size >= view_radius`，`:97-100` 建 Grid 并出生三只 Monster，`:102-107` 启动 100 ms 轻量 Tick。

Terminal B：

```bash
./scripts/linux/debug_console.sh
```

```text
list
stat
call :<scene_handle> stats
```

未登录时 `stats` 应显示 `players=0`、`entities=3`，`ticks` 持续增长。这些字段来自 `service/scene/scene.lua:312-327`，不是 Runtime 自带的 `stat`；Runtime `stat` 用于看 Service CPU、message 和 `mqlen`。

## 3. 两个客户端验证 Enter 和双向 Visible

Terminal C：

```bash
./scripts/linux/run_client.sh --player=10001
```

Terminal D：

```bash
./scripts/linux/run_client.sh --player=10002
```

内存 Storage 的出生点在 `service/storage/memory_worker.lua:27-30`：10001 位于 `(100,100)`，10002 位于 `(108,100)`，距离 8，小于视距 18。第二人进场时：

1. PlayerAgent 在 `service/player/player_agent.lua:79-99` 调 SceneMgr，获得 Scene Address 和 Snapshot。
2. SceneMgr 在 `service/scene/scene_mgr.lua:31-34` 只做首次路由，不留在后续 Move 热路径。
3. Scene `CMD.enter` 在 `service/scene/scene.lua:114-136` 建 Entity、Movement State 并插入 Grid。
4. `scene.lua:138-150` 计算新玩家的 Visible，为新玩家返回 Snapshot，同时把新玩家写入旧玩家的 Visible 并 `send entity_enter`。
5. Watchdog 在 Login Response 入 socket queue 后才于 `service/gateway/watchdog.lua:165-167` 发 `client_ready`，Agent 在 `service/player/player_agent.lua:114-120` 冲刷登录期间缓存的 Push。

客户端只在 `client/test_client.lua:85-100` 的 `wait_response` 内读 socket。如 A 的 Terminal 暂时没打印 B 的 Push，在 A 输入 `ping`，它会先处理已到达 Push，再等 ping Response。这是测试客户端的读循环特性，不是 Scene 没发送。

## 4. 离开视野与跨 Cell

10002 初始 x=108，Token Bucket 初始额度是 10，见 `lualib/scene/movement.lua:20-31`。在 10002 客户端：

```text
move 118 100
```

距离 10001 恰为 18，`distance_sq <= radius_sq` 仍可见。等待至少 0.2 秒补充额度后：

```text
move 120 100
```

x=118 在 Grid x=5，x=120 在 Grid x=6，因此这次同时跨 Cell 并超出 A 的视距。`lualib/scene/aoi_grid.lua:58-79` 将 key 从旧 Cell 移到新 Cell，Scene 仍在 `service/scene/scene.lua:200-204` 用新坐标重算 Visible，`:206-225` 向双方发 Leave。在 10001 客户端输入 `ping` 读出 `entity_leave`。

再用同 Cell 例子验证“Grid 没重链不等于 Visible 不变”。`Grid:move` 在 `lualib/scene/aoi_grid.lua:62-64` 同 Cell 返回 false，但 Scene 不用这个返回值跳过 Visible 计算。边界测试应固定两个 Entity 仍在同 Cell，却从距离 18 内移到 18 外。

### 把边界判断固化成 Unit Test

不要只保留 Terminal 截图。先在 `tests/unit/test_aoi_grid.lua` 补空间索引契约：同 Cell 移动返回 false，但查询应继续包含移动后的 key；跨 Cell 后旧区域不再包含它。Grid 不保存精确坐标，所以“18 内/18 外”的 Exact Visible 不能只靠 Grid Unit Test 证明，这部分应放到 Scene 级测试或抽出的纯函数测试。

`tests/unit/test_movement.lua` 已经用显式 tick 验证 Token Bucket。新增边界时继续传固定 `now_tick`，不要用 `skynet.now()` 或 `sleep`：

```lua
-- 仓库路径：tests/unit/test_movement.lua
local before_x, before_y = state.x, state.y
local accepted, reject_reason = movement.try_move(cfg, state, 1000000, 100, 1201)
assert(not accepted and reject_reason == "OUT_OF_BOUNDS")
assert(state.x == before_x and state.y == before_y,
    "拒绝移动不能改动权威坐标")
```

这段测试只检查 Movement State。Scene 还要保证拒绝时 Grid、`entities` 和 `visible` 不变化。更完整的回归应新增测试专用 Scene Harness 或把“计算 Visible diff”抽成无 Skynet 依赖的 Module，再对输入 Entity 集合做确定性断言。不要为了测试直接暴露生产 Service 的内部 table 给任意调用方。

### 记录一次 Move 的不变量

在 `service/scene/scene.lua::CMD.move` 前后记录以下内容，日志只用于个人实验分支：

```text
player_id
old authoritative x/y
requested x/y
old Grid Cell
movement.try_move result/reason
new Grid Cell
old_visible count
new_visible count
enter/leave/move push count
```

成功移动满足：Movement State 坐标、Entity 坐标、Grid Cell 和 Visible Set 对应同一次提交。拒绝移动满足：除 Token Bucket 的时间/额度计算规则外，Entity 坐标、Grid 与 Visible 不变。正式代码不要在每个 Candidate 上打印自然语言日志；热路径观测应使用计数器或采样。

## 5. 追踪 Attack、Death 和 Respawn

10001 与 Green Slime 100001 的出生点分别是 `(100,100)` 和 `(104,100)`，小于 `lualib/config/game_data.lua:10` 的攻击距离 5。10 级玩家伤害由 `lualib/scene/combat.lua:14-17` 计算为 30，Slime HP 是 50，所以两次攻击死亡：

```text
attack 100001
attack 100001
```

Scene `CMD.attack` 的检查顺序应按 `service/scene/scene.lua:252-309` 记录：攻击者存在→目标存在→类型为 Monster→距离→扣 HP→通知 observers→死亡时从 Visible/Grid/entities 移除→注册 respawn Timer。`game_data.lua:19` 的 `respawn_ticks=500`，Skynet 每 tick 0.01 s，因此约 5 s 后 `scene.lua:304-306` 调用 `spawn_monster`。再输入 `ping` 使客户端读取 `monster_dead`、`entity_leave` 和后续 `entity_enter`。

这条 Timer 当前捕获 `cfg`，Scene 未实现销毁/热更 generation。生产化时如果 Scene 可重置或 Monster 配置可热更，Timer 回调需携带 Scene/Monster generation，回来后重新查找当前状态。

### 攻击链的状态提交顺序

在 LuaPanda 或测试日志中按下面顺序核对 `service/scene/scene.lua::CMD.attack`：

```text
查 attacker Entity
  -> 查 target Monster Entity
  -> 读取双方权威坐标并检查范围
  -> 计算 damage
  -> 提交 target.hp
  -> 计算 observers
  -> send entity_hp
  -> hp == 0 时 send monster_dead/entity_leave
  -> 从每名玩家 Visible 移除 Monster
  -> Grid.remove
  -> entities[target_key] = nil
  -> 注册 respawn Timer
```

这段没有主动 yield，`send` 只投递消息。死亡提交完成后，即使某个 Agent 暂时处理不了 Push，Monster 也已经从 Scene 权威状态移除。不能因为客户端尚未播放死亡表现，就允许下一次攻击继续命中已经移除的目标。

Timer 回调是未来的另一条 coroutine。当前 Scene 永不销毁的学习前提下，捕获 `cfg` 可工作；加入 Scene 重载、实例回收或配置热更后，回调必须校验 Scene generation、Monster spawn generation 和当前配置版本。旧 Timer 不应在新 Scene 实例里复活旧怪物。

### Combat 回归需要覆盖的边界

现有 `tests/unit/test_combat.lua` 只覆盖范围边界和伤害公式。后续 Scene Harness 至少补：

- 攻击者不存在、目标不存在、目标已死亡；
- 距离恰好等于 `attack_range` 与略大于范围；
- 第一次攻击不死亡，第二次死亡；
- 死亡后 Grid、`entities`、所有相关 `visible` 同时移除；
- 重生前不能再次攻击，重生后生成同 ID 的新 Entity；
- 旧 Timer/generation 不能覆盖新实例。

每个用例固定坐标、HP、tick 和 random seed。不要用“sleep 5 秒再看看”作为唯一自动化验证。

## 6. 用断点和受控观测理解 Candidate + Exact Filter

LuaPanda 仅选 `.vscode/launch.json:5-20` 的 Scene 调试配置。低频断点放在：

- `service/scene/scene.lua:43-56`：对比 `candidates` 和 `result`。
- `lualib/scene/aoi_grid.lua:82-95`：记录 gx/gy 与访问的 9 个 Cell。
- `service/scene/scene.lua:200-204`：对比 old/new Visible。

不要长时在每个 Candidate 循环体内停住，调试器会显著改变 Tick、Timer 和 Mailbox 时序。需要可重复数据时，在专用测试构建中增加计数器，不在生产高频路径打每 Entity 自然语言日志。

同时打开 Debug Console，记录 Scene Address：

```text
stat
task :<scene_address>
call :<scene_address> "stats"
trace :<scene_address> lua on
```

发送一条 Move 后立即关闭：

```text
trace :<scene_address> lua off
```

三类信息不要混用：Runtime `stat` 的 `mqlen/cpu/message` 说明调度与排队；`task` 说明 coroutine 当前执行或等待位置；`CMD.stats` 的 players/entities/cells/ticks 是 Scene 业务状态。只有把它们放在同一时间窗口，才能判断是业务量增加、单条 Handler 变慢、下游等待还是 GC。

LuaPanda 断点适合看单条消息的数据变化，不适合测 Tick 时长和 Race。Benchmark 与并发复现必须在关闭 LuaPanda 的正常配置下执行。

## 7. 基准、退化条件与报告格式

先跑现有基线：

```bash
./scripts/linux/benchmark_aoi.sh 1000 100000
./scripts/linux/benchmark_aoi.sh 5000 100000
./scripts/linux/benchmark_aoi.sh 10000 100000
```

`tests/benchmark/aoi_bench.lua:4-7` 固定 map=4000、grid=20，`:9-16` 用固定 seed 均匀生成 Entity，`:18-31` 只测 query QPS、平均 Candidate 和 Cell 数。报告必须标出这是 Query Microbenchmark，不是 Scene Move/Push 容量。

练习版 `tests/benchmark/aoi_move_bench.lua` 应增加：

1. Entity 数 1000/5000/10000，GridSize 10/20/40。
2. 均匀、中心聚集、单 Cell 聚集三种可重复分布，每种固定 random seed。
3. 预热轮与正式采样轮分开，记录 Lua 版本、CPU、Commit 和命令。
4. 每次 Move 记录 Candidate、Exact Visible、Enter/Leave 和是否跨 Cell；汇总 Moves/s、P50/P95/P99、Avg/Max Candidates、Avg Enter/Leave。
5. 修改 AOI 算法时同时跑 `./scripts/linux/test.sh` 和 `./scripts/linux/benchmark_aoi.sh`，报告修改前后同机器数据。

对 1000 人集中在小区域、10 Hz Move 的分析，不应先写 Region Partition。先根据 `O(K)` Candidate、每人 Visible 上限、事件率×观察者数估算 Push，再依次评估降频、合并、优先级、视野人数上限、分线/实例化。只有 profile 与压测证明仍无法满足同场需求时，才进入需要 Ghost Entity、Epoch 和跨边界协议的 Region 方案。

### 先读懂现有 Microbenchmark 的边界

`tests/benchmark/aoi_bench.lua` 测量 `Grid:query_3x3`，输入由固定 seed 生成。它没有覆盖：

```text
movement.try_move
Grid:move
Exact Distance Filter
old/new Visible diff
Sproto pack
跨 Service send
Socket write
Lua GC 对整条 Scene Handler 的影响
```

因此报告标题应写“AOI Query Microbenchmark”，不能写“Scene 每秒支持 X 次移动”。修改 Grid 实现时它很有价值；判断整张地图容量时，需要新增 Move Benchmark 或端到端 Load Test。

### Move Benchmark 的建议文件和数据结构

新增 `tests/benchmark/aoi_move_bench.lua` 时，把 Entity 分布生成、单次 Move 和统计分开：

```text
build_entities(case, count, seed)
run_one_move(state, entity_id, target_x, target_y)
record_sample(cost, candidates, visible, enters, leaves, pushes)
report_percentiles(samples)
```

每个 Case 至少输出：

| 字段 | 说明 |
|---|---|
| Commit / Lua / CPU | 复现环境 |
| Entity / Grid / Radius | 算法输入 |
| Distribution / Seed | 均匀、中心聚集、单 Cell |
| Warmup / Samples | 预热与正式采样量 |
| Moves/s | 吞吐 |
| P50/P95/P99 | 单次 Move 延迟 |
| Avg/Max Candidate | 退化程度 |
| Avg Visible / Push | 广播规模 |
| GC KB/次数 | 分配压力 |

做算法改动时，在同一机器、同一 Commit 基线配置上先跑 Before，再应用修改跑 After。若修改同时改变数据分布或日志级别，数据不能直接比较。

### 从数据决定优化顺序

若 Candidate 很高而 Push 较低，先检查 GridSize 与分布；Candidate 与 Visible 都高时，问题来自真实高密度视野，换一种索引也消不掉广播规模。若 Candidate/Visible 正常但 P99 高，继续查临时 table、GC、Sproto pack、日志和 Worker 调度。只有单 Scene 已经达到单 Actor 上限，并且业务必须保持大量玩家同场，才评估 Region Partition。

## 8. Scene Service 的固定 Review

对 `service/scene/scene.lua::CMD.move` 和 `CMD.attack` 各做一次 Review：

| 检查项 | Move | Attack |
|---|---|---|
| Owner | 坐标、移动额度、Grid、Visible | HP、位置、Monster 生命周期、Visible |
| 主动 yield | 当前提交段无 | 当前提交段无；死亡后只注册 Timer |
| `call` 是否需要 | Handler 内不需要 | Handler 内不需要 |
| `send` 用途 | AOI Enter/Leave/Move | HP/Death/Leave Push |
| stale message 风险 | 未来 Transfer 需 Scene/Entity epoch | Respawn Timer 需 generation |
| Hot Actor 风险 | Move Hz × Candidate/Visible | 技能频率 × observers |

如果以后在提交段加入异步导航、跨服技能或数据库调用，表中“主动 yield”就要改变。恢复后必须重新查 Entity 并校验 epoch，不能继续使用 yield 前保存的 table 引用。

## 9. 回归与验收

```bash
./scripts/linux/test.sh
./scripts/linux/benchmark_aoi.sh
git status --short
```

进入第四课前，应交付以下证据：

1. 双客户端 Enter/Leave/Move Push 输出，每条能对到 `service/scene/scene.lua` 的提交步骤。
2. 一次跨 Cell 与一次同 Cell 但 Visible 改变的确定性测试，不依赖人工时机。
3. Attack→HP→Death→Grid/entities/visible remove→Timer→Respawn 的完整时序图。
4. 对 `CMD.move` 做完整 yield 审查，证明当前 `service/scene/scene.lua:183-249` 提交段为什么没有主动 yield。
5. 一份带环境、Commit、分布、GridSize、样本量和 P95/P99 的 AOI Move Benchmark，能展示单 Cell 聚集时的退化。
6. Debug Console 中 Scene `mqlen/cpu/message/task` 与业务 `stats` 的对照，能区分 Runtime 排队与 Scene 业务数量。

第三课重写版末尾的 20 道自测题已经逐题附上参考答案。完成实操后，重点重答第 3～9、12～20 题，并把答案和本次 Candidate、Visible、Push、Benchmark、Mailbox 数据对应起来。没有负载条件的“九宫格是 O(1)”或“增加 Worker 可以扩 Scene”都不能作为验收结论。
