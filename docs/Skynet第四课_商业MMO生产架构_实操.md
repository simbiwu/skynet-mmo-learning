# Skynet 第四课配套实操：持久化一致性、可观测性与故障边界

当前仓库是可运行的单节点学习基线，尚未实现 Cluster、Versioned Dirty Save、Operation Ledger、生产 Metrics 和通用热更。本实操把这些作为可分步评审、实现和验证的工程任务，不宣称仓库已具备这些能力。每个阶段都要保持单节点基线可运行，不在一个提交中同时引入 Cluster、DB Schema、热更和监控。

命令默认从 WSL2/Linux 仓库根目录执行。任何行为改动完成后都要跑 `./scripts/linux/test.sh`；AOI 算法改动还要跑 `./scripts/linux/benchmark_aoi.sh` 并报告前后数据。

## 1. 先建生产化基线档案

```bash
cd /mnt/g/simbi/dev/skynet-mmo-learning
git status --short
git rev-parse HEAD
./scripts/linux/test.sh
./scripts/linux/benchmark_aoi.sh 10000 100000
```

档案至少记录：Commit/Build ID、Skynet v1.8.0、Lua 5.4.7、WSL 内核、CPU/内存、`config/game.lua:13` Worker 数、Storage Driver/Pool、单元/集成测试结果和 AOI 基准命令。没有这份档案，后续的延迟、RSS 和吞吐变化无法归因。

在写代码前完成四张表：

| 表 | 必填字段 |
|---|---|
| State Owner | 状态、权威 Service、派生副本、持久化位置 |
| Yield Review | 函数、yield 点、yield 前读取、恢复后重新校验 |
| Failure Matrix | 故障点、请求是否可能已执行、剩余状态、恢复/对账 |
| Capacity | 负载模型、QPS、P50/P95/P99、CPU、RSS、Mailbox、GC、Network、DB |

先区分仓库现状与本课建议新增的文件。下表中“现有”路径可以立即运行；“建议新增”只有完成实现和测试后才能写成项目能力。

| 状态 | 完整仓库路径 | 用途 |
|---|---|---|
| 现有 | `service/player/player_agent.lua` | 玩家状态、连接绑定、下线最终保存 |
| 现有 | `service/storage/storage_mgr.lua` | 按 player_id 路由 Storage Worker |
| 现有 | `service/storage/memory_worker.lua` | 零依赖学习存储 |
| 现有 | `service/storage/mysql_worker.lua` | MySQL 读写接口 |
| 现有 | `service/config/config_service.lua` | 启动时发布 sharedata |
| 现有 | `service/scene/scene.lua` | Scene 权威实时状态 |
| 建议新增 | `lualib/persistence/player_snapshot.lua` | Snapshot 复制、版本和字段白名单 |
| 建议新增 | `tests/regression/test_dirty_save_version.lua` | Save Response 竞态回归 |
| 建议新增 | `service/economy/economy_service.lua` | 经济操作协调边界 |
| 建议新增 | `lualib/economy/operation.lua` | Operation ID、状态转换、参数 Hash |
| 建议新增 | `tests/regression/test_duplicate_purchase.lua` | 幂等和 Commit 后丢 Response |
| 建议新增 | `lualib/config/validator.lua` | Candidate Config 验证 |
| 建议新增 | `lualib/metrics/metrics.lua` | Service 本地低成本指标累计 |
| 建议新增 | `service/system/monitor.lua` | 周期拉取/汇总 Snapshot |
| 建议新增 | `service/router/scene_router.lua` | `{scene_id,node,address,epoch}` 路由 |

每个阶段单独提交和验证。不要在 Dirty Save 尚未稳定时同时引入 Cluster 与热更，否则失败现场无法归因。

## 2. Versioned Dirty Save：先证明旧 Response 不能清新 Dirty

当前 `service/player/player_agent.lua:193-210` 只在下线时将整个 `player` table 同步传给 Storage，`service/storage/memory_worker.lua:53-55` 直接覆盖，`service/storage/mysql_worker.lua:52-72` 也没有 version 条件。第一步先不接 MySQL，用 MemoryWorker 建可确定的竞态测试。

在 PlayerAgent 的持久状态区增加：

```lua
local state_version = 0
local saved_version = 0
local save_inflight = false
```

不要只靠一个手动 `dirty` 布尔值；定义 `dirty := state_version > saved_version`。每次金币、等级、HP、scene_id 和已确认位置等持久状态提交后调用统一 `mark_dirty()`，不把 Scene 的 `visible/grid/move_state` 纳入 Player Snapshot。

Save 必须传不可变快照，不能把 `player` table 传出后在 yield 期间继续修改它：

```lua
local function make_snapshot()
    return {
        player_id = player.player_id,
        name = player.name,
        level = player.level,
        gold = player.gold,
        hp = player.hp,
        max_hp = player.max_hp,
        scene_id = player.scene_id,
        x = player.x,
        y = player.y,
        version = state_version,
    }
end

local function save_once()
    if save_inflight or state_version <= saved_version then
        return true
    end
    save_inflight = true
    local snapshot = make_snapshot()
    local saving_version = snapshot.version
    local ok, err = skynet.call(storage_mgr, "lua", "save_player", snapshot)
    save_inflight = false
    if ok then
        saved_version = math.max(saved_version, saving_version)
    end
    return ok, err
end
```

这段伪代码省略了定时调度、退出状态机和 DB CAS，不可直接当作完整上线实现。下线不能在一次 Save 返回后无条件 `exit`；应进入 `ONLINE -> DRAINING -> SAVING -> REMOVED -> EXITED`，停止接受新业务，循环至 `saved_version == state_version`，再从 PlayerMgr 删除当前 `{player_id, agent, generation}`。

回归测试必须用 barrier 控制顺序：

```text
state_version=1，开始 Save(snapshot v1)
Storage 收到后阻塞，不立即 Response
PlayerAgent 提交金币变更，state_version=2
释放 Storage，让 v1 Response 返回
断言 saved_version=1，state_version=2，dirty=true
再 Save v2，成功后断言 dirty=false
```

这个测试不用 `sleep` 猜时机。MySQL 版再为 `sql/schema.sql` 加 version，用 `UPDATE ... SET ..., version=? WHERE player_id=? AND version=?`，检查 affected rows；CAS 失败不能被宽泛 Retry 覆盖，要报出双 Owner/旧 Writer 冲突。

### 实现顺序和断点位置

第一步只改 Memory Driver，避免把 Lua 时序问题和 MySQL 事务混在一起：

1. 在 `lualib/persistence/player_snapshot.lua::copy_from_player` 集中列出允许持久化的字段。不要把 `client_fd`、Service Address、`pending_pushes`、Scene `visible/grid/move_state` 写入 Snapshot。
2. 在 `service/player/player_agent.lua` 所有持久状态提交点调用 `mark_dirty`。当前 Move 成功后的 `player.x/y` 是一个提交点；未来金币、等级、背包也要走统一入口。
3. 在 `service/player/player_agent.lua::save_once` 发出不可变 Snapshot，记录 `saving_version`，然后 `skynet.call` Storage。该行是 yield 点。
4. Response 返回后只推进 `saved_version`，再比较当前 `state_version`。不要直接清布尔 dirty。
5. `offline` 改成有截止时间的排空循环。进入 DRAINING 后拒绝新业务，保存追平后才从 PlayerMgr 删除 Address 并退出。

LuaPanda 断点建议放在 `make_snapshot`、`skynet.call(storage_mgr,...)` 前后和推进 `saved_version` 的分支。竞态正确性仍由 barrier 测试证明，断点只用于核对状态。

测试用 Storage Stub 需要两个命令：`save_player` 收到 v1 后向测试驱动报告 `ARRIVED` 并 `skynet.wait()`；测试驱动提交 v2 后再发 `release(v1)`。这样顺序由协议控制，不依赖机器速度。测试输出至少包含：

```text
before save: state=1 saved=0
v1 arrived and blocked
after mutation: state=2 saved=0
v1 response: state=2 saved=1 dirty=true
v2 response: state=2 saved=2 dirty=false
```

进入 MySQL 阶段后，`sql/schema.sql` 的 version 和 Agent `state_version` 要定义清楚初始值、递增规则和 CAS 冲突处理。affected rows 为 0 属于业务冲突信号，不应吞掉后返回成功。

## 3. Operation ID：验证 Commit 成功但 Response 丢失

新增的 `lualib/economy/operation.lua` 只定义 Operation ID 校验、状态转移和结果编码，不自己拥有玩家金币。`service/economy/economy_service.lua` 可做用例协调，但扣金币、增道具、插 Operation/Ledger 必须在同一可证明的事务边界内，不能在多个 Service 内存各改一半。

最小表应有唯一 `(player_id, operation_id, operation_type)`，保存 request hash、status、result payload、created/committed time。同 Operation ID 却参数 hash 不同必须拒绝，不能把误用 ID 视为成功重试。

`tests/regression/test_duplicate_purchase.lua` 要求：

1. 并发发送同一 Operation ID 10 次，最终只扣一次、只增一份道具，10 个响应的业务结果一致。
2. 在 DB Commit 后、Response 发送前故意丢弃 Response，Caller 超时后用同 ID 重试，服务端返回已保存结果。
3. 同 ID 换 item/count 后请求，必须返回参数冲突，不执行新购买。
4. 进程在 Commit 后重启，重试仍能从 DB 找到 Operation；只在 Lua table 去重不合格。

### 写清事务边界

建议新增表时在 `sql/schema.sql` 明确唯一约束：

```sql
-- 仓库路径：sql/schema.sql（建议新增，字段名可按最终 Schema 调整）
UNIQUE KEY uk_player_operation (player_id, operation_type, operation_id)
```

一次购买事务的顺序应固定：

```text
BEGIN
  -> SELECT/INSERT operation，占住唯一 Operation ID
  -> 若已 COMMITTED，校验 request_hash 后返回历史 result
  -> 校验余额和商品
  -> 扣金币
  -> 增道具
  -> 写 ledger
  -> operation.status = COMMITTED，保存 result payload
COMMIT
  -> 向 Caller 发 Response
```

“Commit 后丢 Response”故障点必须放在 `COMMIT` 成功与 `skynet.retpack` 之间。第一次调用方应看到超时或连接失败；第二次用相同 Operation ID 和相同参数调用时，从已提交 Operation 返回原结果。换参数但复用 ID 时，request hash 不一致，明确返回冲突。

对这条链做 yield 审查：Economy Service 等 DB 时 coroutine 会 yield；同一玩家的第二个经济命令是否允许进入，取决于事务和玩家串行边界。不能只依赖 Lua table 的 `processing[operation_id]`，因为进程重启后它会丢失。

## 4. Config Version：验证后再 Publish

当前 `service/config/config_service.lua:6-10` 在启动时直接 `require "config.game_data"` 并 `sharedata.new`，`lualib/config/game_data.lua` 没有 version。把流程拆成：

```text
load candidate
  -> schema/type/range validation
  -> cross-reference validation
  -> compatibility and migration policy
  -> publish immutable version N
  -> subscribers acknowledge/apply at a defined boundary
  -> observe
  -> rollback means publish an allowed new version or select retained snapshot
```

验证器至少拒绝 `grid_size <= 0`、当前 3×3 算法下 `grid_size < view_radius`、边界反转、`move_speed <= 0`、重复 Monster ID、Monster 越界、非法 respawn_ticks、引用不存在的 Scene/Monster 和版本回退。`sharedata.update` 只负责发布共享数据，不代替这些验证，也不会迁移 Scene 中已创建 Entity、Timer 和 `spawn_cfg`。

建立表格写清每个字段是“仅对新对象生效”、“下一 Tick 原子切换”还是“需 State Migration”。没有这张表不进行热发布。

### Validator 与 Publisher 分开测试

建议 `lualib/config/validator.lua` 提供纯函数：

```text
validate_schema(candidate)
validate_ranges(candidate)
validate_references(candidate)
validate_compatibility(current, candidate)
```

它不调用 `sharedata.update`，所以可以用 Skynet Bundled Lua 直接跑 Unit Test。`tests/unit/test_config_validator.lua` 至少覆盖：

```text
grid_size <= 0
grid_size < view_radius（当前 3×3 实现）
min > max
move_speed <= 0
重复 Monster ID
Monster 坐标越界
respawn_ticks <= 0
引用不存在 Scene/Template
candidate.version <= current.version
```

只有全部验证通过，`service/config/config_service.lua::publish` 才调用 sharedata 发布不可变 Version。Scene 是否立即采用新值要按字段定义：攻击伤害表可以在下一请求读新版本；已出生 Monster 的 HP、当前 Timer 和 `spawn_cfg` 涉及运行态迁移，不能由 `sharedata.update` 自动解决。

故障注入应验证发布前失败：传入非法 Candidate，断言当前 Version、Scene 已有 Entity 和新登录玩家看到的配置都未变化。回滚也作为一次有版本的发布操作记录，不在文件系统上悄悄覆盖旧配置。

## 5. Metrics 和 Trace：先建最小闭环

`service/system/monitor.lua` 是采集/汇总 Service，不应变成每个 Move 同步经过的中央代理。`lualib/metrics/metrics.lua` 应在本 Service 内用 counter/gauge/histogram 累计，周期批量交换 Snapshot。

最小指标集：

- Node：Build ID、Config Version、process uptime/RSS/CPU、socket connection/error。
- Service：type/address、mqlen、message rate、CPU、Lua memory、active/waiting task。
- RPC：caller type、callee type、command、result class、latency histogram，不使用 player_id 作 label。
- Scene：players/entities/cells、tick cost、candidate/visible/push、rejected move/attack。
- Storage：pool queue、query latency、error/CAS conflict、dirty backlog、oldest dirty age。

Debug Console `stat/mem/task/info` 可用于个人或受控 staging 核对，不是生产监控存储。生产端点必须限制网络、认证、授权和审计，默认不暴露能执行 `call/kill/inject` 的原始 Console。

一次 Move 的 Trace 要区分：`trace_id` 连接整条路径，`request_id` 区分某次请求/重试，`operation_id` 只用于需幂等的业务操作。Move 通常不需 Operation ID；付费购买必须有。

### 在 Move 链上做一次最小埋点

先只对一条链埋点，避免一开始造完整监控框架：

```text
Gate/PlayerAgent 收包：request_count +1，记录 request_id
PlayerAgent call Scene 前：rpc_start
Scene CMD.move：handler_start/handler_end、result_class
Scene Push：push_count，按消息类型聚合
PlayerAgent resume：rpc_latency
Socket 写入：response_count
```

`lualib/metrics/metrics.lua` 在当前 Service Lua State 内累计 Counter/Gauge/Histogram。Scene Move 不同步 call Monitor；Monitor 周期拉取或各 Service 周期 send Snapshot。Histogram bucket 在设计时固定，例如 1/2/5/10/20/50/100 ms，不能把每个原始延迟值变成 label。

Trace Context 随 Service 消息显式传递或放入统一 Envelope。若只用 coroutine local，要确认 `skynet.call`、`send`、Timer 和 fork 的传播规则。日志至少带 Build ID、Config Version、service_type/address、trace_id、request_id、command、result、cost；Metric label 不带 player_id、trace_id、request_id。

验证时人为让 Scene Handler 延迟，再比较：PlayerAgent RPC latency 上升、Scene handler 时间、Scene mqlen 和 Worker CPU。若 handler 时间很低而 RPC latency 高，继续查排队和下游；不要把所有等待都算成 Scene CPU。

## 6. Cluster 双节点：先观察失败，不自动 Retry

第一个双节点实验只拆 Player Node 和 Scene Node，保持 Memory Storage，避免同时调试 DB。建议新增 `config/cluster.lua`、`config/player_node.lua`、`config/scene_node.lua`，两端使用不同 Gate/Debug Console 端口和独立日志。

业务代码不到处直接 `cluster.call`。Router 输入稳定 `scene_id`，返回 `{node, address/name, epoch}`，记录 deadline 和失败分类。PlayerAgent 的 Move 仍保持“Scene Commit 成功后才更新 Snapshot”，但超时结果是 `UNKNOWN`，不能直接认定 Scene 没执行。

故障注入顺序：

1. 双节点启动，完成 Login 和一次 Move，保留两端 Build ID、Route epoch 和 Trace。
2. Move 到达 Scene 前停 Scene Node，记录 Caller error、Agent Snapshot 和 Client Response。
3. Scene 已 Commit、回复发送前停 Node，证明 Caller 无法从超时判断是否执行。
4. 重启 Scene Node，Route epoch 必须增长；向新 Scene 发送旧 epoch Move，断言被拒绝。
5. 实验期间不开启通用自动 Retry。只有读请求或有 Operation ID/去重记录的写请求才能制定明确重试政策。

### 双节点实验文件和端口

建议把公共配置放在 `config/cluster.lua`，节点文件只覆盖角色、监听和 Debug Console 端口：

```text
config/cluster.lua       节点名到地址的静态学习配置
config/player_node.lua   Gate 18888 / Debug Console 18000
config/scene_node.lua    无公网 Gate / Debug Console 18001
```

启动时使用两个独立 Terminal 和日志：

```bash
# 当前目录：仓库根目录；文件完成后再执行
./third_party/skynet/skynet config/scene_node.lua
```

```bash
# 当前目录：仓库根目录；文件完成后再执行
./third_party/skynet/skynet config/player_node.lua
```

第一条跨节点 Move 成功后，记录 PlayerAgent Address、Scene Node、远端 Scene Address/Name、route epoch 和 trace_id。随后按“请求到达前停节点”和“Scene Commit 后停节点”两个注入点分别演练。后一种场景必须得到 `UNKNOWN`，因为 Caller 没有足够信息判断远端是否执行。

Router 缓存不能只保存 Address。最少保存 `{scene_id,node,address_or_name,epoch}`；Scene Node 重启后 epoch 增长，旧 epoch 消息被新 Owner 拒绝。无 Operation ID 的 Move 是否重试，要结合下一次客户端位置同步和 Scene 查询设计，不能套用经济操作的幂等协议。

## 7. 三类负载与容量报告

压测工具需要独立于 `client/test_client.lua` 的阻塞式交互循环，能使用固定 seed 产生可重复负载。至少三组：

| 场景 | 需固定的输入 | 主要观测 |
|---|---|---|
| Idle Online | 连接数、Agent 数、心跳周期 | RSS/Agent、GC、socket memory、心跳 P99 |
| Move Heavy | 每玩家 Hz、Scene 数、均匀分布 | Move P50/P95/P99、Scene CPU/mqlen、candidate/push、network |
| Hot Scene | 单 Scene 人数、中心/单 Cell 聚集、移动/技能比例 | 单 Scene CPU/mqlen、max candidate、push fanout、GC/tick overrun |

每次报告包含硬件、Commit/Build ID、Config Version、Worker 数、Storage Driver/Pool、预热/采样时间、Online/QPS、latency histogram、错误率、CPU/RSS、Mailbox、GC、Network、DB。容量结论应写成“在这组条件下，当 P99/错误率/mqlen 首次超阈值时的负载”，不只报最大连接数。

### 压测执行顺序

每个场景按同一流程执行：

```text
空载启动并记录 RSS/Service 数
  -> 逐级升载
  -> 每级先预热
  -> 固定采样窗口
  -> 记录客户端与服务端指标
  -> 停止加压，观察 backlog 恢复时间
  -> 保存日志、配置、命令和原始结果
```

Idle Online 用于测每连接/每 Agent 基础成本；Move Heavy 用于测多个 Scene 的并行和正常 AOI；Hot Scene 用于测单 Actor 上限。三组数据不能互相替代。Hot Scene 达到瓶颈时若整个进程 CPU 尚有空闲核而单 Scene mqlen 上升，证据支持 Hot Actor；若所有 Worker 与 Socket/DB 都饱和，则故障层次不同。

现有 `tests/benchmark/aoi_bench.lua` 只是 AOI Query Microbenchmark。它用于算法 Before/After，不包含网络、PlayerAgent、Scene dispatcher、Push 与 GC 全链路。容量报告不能引用它的 QPS 作为服务器 Move QPS。

## 8. 内存、GC、Profile 与 Core Dump

### 先做在线只读观察

正常开发配置启动后，Debug Console 中执行：

```text
stat
mem
cmem
jmem
task :<hot_service_address>
```

`mem` 反映各 Lua Service 内存，`cmem` 查看 C 侧统计，`jmem` 查看 jemalloc 统计。进程层同时记录：

```bash
# 当前目录：仓库根目录；PID 取实际 Skynet 进程
ps -o pid,rss,vsz,%cpu,cmd -p <pid>
cat /proc/<pid>/status
cat /proc/<pid>/smaps_rollup
```

`collectgarbage("count")` 只覆盖当前 Lua State 的 GC 内存，不能代替 RSS/PSS。若 RSS 高而各 Service Lua memory 不高，继续检查 C Module、socket buffer、线程栈、allocator arena/碎片和未归还页。

### GC 实验要控制变量

选一个隔离环境固定在线数、消息率和数据分布，记录默认 GC 参数下的 P95/P99、Scene mqlen、Lua memory 与 RSS。每次只改一个参数或一种分配模式，再跑同样负载。LuaPanda、详细 trace 和每请求日志必须关闭，否则时序与分配已经改变。

Scene 关注 Move/AOI/Push 热路径临时 table 的分配率和单次 GC 停顿；大量 PlayerAgent 关注每 Lua State 常驻基线与分散 GC 的累计成本。优化结论需注明在线数、Scene 分布、Lua 版本、GC 参数和采样窗口。

### Native Crash 与 Core Dump

个人或 Staging 环境先确认 Core 策略：

```bash
ulimit -c
ulimit -c unlimited
cat /proc/sys/kernel/core_pattern
```

若发行版由 systemd-coredump 管理，使用 `coredumpctl list` 和 `coredumpctl gdb <pid-or-exe>`；WSL 环境不一定启用该服务，此时按 `core_pattern` 指定的位置取文件。不要在生产上临时修改全局 Core 路径和磁盘策略，先由部署配置控制容量、权限和保留时间。

分析命令：

```bash
# 当前目录：仓库根目录
gdb ./third_party/skynet/skynet /path/to/core
```

```gdb
set pagination off
info threads
thread apply all bt full
info sharedlibrary
```

报告必须记录二进制 Build ID、匹配的 `.so` 和调试符号。Core 可回答崩溃信号、native 线程栈、C Module/allocator 现场；它不能还原几分钟前的业务消息顺序，仍要与结构化日志、Trace 和必要的 Record/Replay 对齐。

## 9. 发布、灰度和回滚演练

一次发布包至少绑定：

```text
Build ID / Git Commit
Skynet/Lua 基线
Config Version
Protocol Version
DB Schema Version
Migration ID
启动参数与 Feature Flag
```

灰度先限制节点/玩家比例，比较同一负载窗口的错误率、P95/P99、RSS、GC、Mailbox 和 DB 冲突。回滚前检查新版是否已经写入旧版无法读取的 Schema、枚举、Operation 或状态。若存在不可逆数据变化，应向前修复或运行明确的兼容迁移，不能只替换旧二进制。

演练报告应包含触发阈值、停止扩灰条件、回滚决策人、回滚命令、数据兼容检查和恢复验证。发布成功的判断依据是业务与系统指标稳定，不是进程成功启动。

## 10. Graceful Shutdown 和故障恢复演练

当前不实现完整 Shutdown Service 前，先画清状态机：

```text
RUNNING
  -> DRAINING: Gate 停止接新连接，路由停止分配新玩家
  -> QUIESCING: 玩家业务停止进入，已接受请求完成或超时
  -> SAVING: Dirty Save 追平，Operation Ledger 对账
  -> LEAVING: Scene 移除 Player，PlayerMgr 按 generation 删路由
  -> STOPPED
```

演练 SIGTERM 与强杀进程是两类用例：前者验证有 deadline 的排空，后者验证从 Snapshot/Ledger 重建。PlayerAgent Crash 可将故障域限在一个玩家；Scene Crash 会丢失大量未持久的实时状态。没有 Event Log/检查点时，宣告 Scene epoch 失效并让玩家重登/回安全点，通常比猜测现场安全。

对每个故障留下：注入时间、Build/Config Version、trace/request/operation ID、受影响 Service/Player、最后持久 version、当前 route epoch、恢复耗时和人工操作。不用宽泛 catch 把失败改写成“成功但数据不确定”。

### 分阶段验证 Shutdown

不要一次实现完整状态机后再测试。按以下顺序加能力：

1. Gate 停止 accept，新连接得到明确拒绝；旧连接仍可完成已接受请求。
2. PlayerAgent 进入 DRAINING，拒绝新的会改变持久状态的命令，允许必要的 Response/Push 排空。
3. Dirty Save 追平，记录未保存玩家数和 oldest dirty age。
4. Scene 移除玩家并停止新 Transfer；Timer callback 使用 generation 拒绝旧事件。
5. PlayerMgr 只删除匹配 `{player_id,agent,generation}` 的当前路由。
6. 达到 deadline 后输出未完成清单，按策略强制退出；不能无限等待一个失联 DB。

每个阶段用 barrier 或可观察计数证明已完成。SIGTERM 路径验证排空；`kill -9` 用于验证下一次启动从 Snapshot/Ledger 恢复，两者预期不同。

## 11. 最终验收

第四课不以“Cluster 能 ping通”为验收。需交付：

1. Dirty Save 确定性回归：Save v1 期间产生 v2，v1 Response 不能清 dirty；MySQL CAS 冲突可观测。
2. 重复购买回归：同 Operation ID 并发 10 次、Commit 后丢 Response、重启后重试，均只执行一次。
3. Config 发布回归：非法 Grid/Monster/reference/version 在 Publish 前失败；能说清已存 Entity 是否迁移。
4. 监控面板和一次 Move Trace：Metric 无 player_id 高基数 label，Trace 能区分 Handler CPU 与下游 call 等待。
5. Cluster 故障矩阵：到达前失败、Commit 后 Response 丢失、节点重启/epoch 变更都有实际证据，没有无条件重试写请求。
6. Idle Online、Move Heavy、Hot Scene 三份可复现报告，含 P95/P99、RSS、Mailbox、GC、Network 和 DB，明确首个容量瓶颈。
7. Graceful Shutdown 与强杀的不同恢复证据，并为 PlayerAgent/Scene/Node Crash 分别写 Owner、持久点、故障域与不可恢复状态。

所有行为改动结束后执行：

```bash
./scripts/linux/test.sh
git status --short
```

设计文档、测试、故障证据和监控查询需与实现同一次变更交付。只有代码或只有架构图都不足以证明已可生产运行。

第四课重写版末尾的 30 道题已经逐题附上参考答案。验收时从 Cluster、持久化、热更、内存、监控、压测、发布和恢复各抽至少两题，答案必须引用本次实现的文件、测试、Metric/Trace 查询或故障注入证据。对于仓库尚未实现的能力，应明确写“设计与验收条件”，不能用计划中的文件冒充现有功能。
