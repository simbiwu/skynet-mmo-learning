# Skynet MMO 学习课程总目录

这套课程面向有多年 MMO Server C++ 开发经验、熟悉 Lua 的工程负责人。目标不是“会运行 Demo”，而是能从源码解释 Skynet 的运行语义，能审查 Service 边界与 coroutine 正确性，并能把工程带到可诊断、可压测、可上线的状态。

课程不按天数安排。每一课都有能力验收：能解释、能操作、能调试、能验证之后再进入下一课。四课是完整主线，`docs/` 中其余专题文档作为实验手册和参考资料，不再与主线争夺入口。

## 第一课：启动链、构建与调试工具链

主教材：[`Skynet第一课_启动链源码导读_重写版.pdf`](Skynet第一课_启动链源码导读_重写版.pdf)

配套实操：[`Skynet第一课_启动链源码导读_实操.md`](Skynet第一课_启动链源码导读_实操.md)

从 `./third_party/skynet/skynet config/game.lua` 出发，建立第一张完整运行时地图：Native Build Artifact、配置临时 Lua State、`skynet_start`、Worker Thread、`snlua`、`loader.lua`、官方 `bootstrap.lua`，最终到项目 `service/main.lua`。同时完成 Windows VS Code + WSL2、LuaPanda、Debug Console 与 GDB 的开发环境闭环。

能力验收：

- 能从构建命令指出 `skynet` ELF、C Service、Lua C Module 和 Bundled Lua 的产物位置。
- 能不借助文档复述从进程入口到 `service/main.lua` 的启动链，并区分 `bootstrap` 与业务 `start`。
- 能在 Windows VS Code 中分别命中 Scene、PlayerAgent 的 LuaPanda 断点。
- 能使用 Debug Console 定位 Service 地址，使用 GDB 停在 Runtime C 层，并判断某个故障属于构建、配置、Service 装载还是业务初始化。

配套手册：`docs/09_WINDOWS_WSL2.md`、`docs/10_LINUX.md`、`docs/16_DEBUGGING.md`。

## 第二课：Service 模型与 Actor 架构

主教材：[`Skynet第二课_Service模型与MMO_Actor架构_重写版.md`](Skynet第二课_Service模型与MMO_Actor架构_重写版.md)

配套实操：[`Skynet第二课_Service模型与MMO_Actor架构_实操.md`](Skynet第二课_Service模型与MMO_Actor架构_实操.md)

从 `skynet_context`、Service 私有 Mailbox、Global Queue 和 Worker 调度开始，建立 Skynet Service 的准确语义。重点纠正“一个 Service 等于一个永不重入的单线程游戏循环”这一危险类比：消息处理 coroutine 一旦在 `skynet.call` 等位置 yield，同一 Service 的其他消息就可以继续执行并修改共享状态。

课程使用真实 `move` 请求验证 PlayerAgent 与 Scene 的边界，讨论 `call/send`、同步 RPC 链、`skynet.queue`、Generation Check、Manager 与 Hot Actor，并形成可执行的 Service 设计审查清单。

能力验收：

- 能从 C Runtime 到 Lua dispatcher 解释一条消息如何进入某个 Service coroutine。
- 能在任意 Service 修改前列出状态所有权、全部 yield 点和恢复后的失效条件。
- 能解释 PlayerAgent 为什么拥有持久角色快照、Scene 为什么拥有权威实时坐标，以及二者如何同步而不形成双主。
- 能识别不必要的同步 RPC、中心代理、过细 Service 和缺失 Generation Check。
- 能用 LuaPanda、Debug Console 的 `stat/task/trace` 和确定性测试验证判断。

## 第三课：完整 MMO 业务闭环与一致性

主教材：[`Skynet第三课_Scene九宫格AOI_Monster与Combat_重写版.md`](Skynet第三课_Scene九宫格AOI_Monster与Combat_重写版.md)

配套实操：[`Skynet第三课_Scene九宫格AOI_Monster与Combat_实操.md`](Skynet第三课_Scene九宫格AOI_Monster与Combat_实操.md)

以登录、重连、进场、AOI、移动、战斗、掉线保存为连续业务链，学习如何把 Service 模型变成可维护的 MMO 架构。主题包括 PlayerAgent 生命周期、Scene 分片、AOI 与 Tick Budget、Sproto 协议边界、内存/MySQL 存储、幂等与超时、跨 Service 事务取舍、优雅停服和状态恢复。

能力验收：

- 能画出每条业务链的消息方向、状态所有者、yield 点、失败补偿和客户端可见顺序。
- 能设计同账号顶号、fd 复用、延迟 timer、重复请求和 Service 退出时的版本校验。
- 能判断模块应留在 Service 内还是拆为新 Service，并能避免 Manager 成为永久数据面。
- 能为发现的竞态补充可重复回归测试，而不是只靠日志证明“这次没复现”。

配套专题：`docs/04_LOGIN_FLOW.md`、`docs/05_SCENE_AOI_COMBAT.md`、`docs/06_PROTOCOL.md`、`docs/07_STORAGE.md`、`docs/15_P0_AUTHORITATIVE_MOVEMENT.md`。

## 第四课：生产工程、故障诊断与性能

主教材：[`Skynet第四课_商业MMO生产架构_Cluster持久化热更GC监控与上线_完整版.md`](Skynet第四课_商业MMO生产架构_Cluster持久化热更GC监控与上线_完整版.md)

配套实操：[`Skynet第四课_商业MMO生产架构_实操.md`](Skynet第四课_商业MMO生产架构_实操.md)

把样例工程放进真实环境审视：结构化日志与 Trace/Context ID、Service 状态检查、Mailbox/延迟指标、录制回放、压测模型、Lua/C Profiling、Core Dump、GDB、容量规划、灰度与回滚。区分个人、共享、Staging 和 Production 环境中允许使用的工具与操作。

能力验收：

- 能从延迟分布、Mailbox、CPU、内存和消息路径区分排队、执行、下游 RPC 与网络问题。
- 能在无 LuaPanda 的生产进程上，用指标、Trace、Core Dump 和 GDB 形成证据链。
- 能设计接近真实玩家行为的负载，给出瓶颈位置和优化前后数字，而不是只报告 QPS。
- 能列出从当前仓库到正式项目的差距、风险、上线门槛和回滚方案。

配套专题：`docs/08_TESTING_AND_BENCHMARK.md`、`docs/11_PRODUCTION.md`、`docs/13_PRODUCTION_GAPS.md`。

## 统一学习方法

每个重要路径固定回答七个问题：相关源码在哪里；当前运行在哪个 Process/Thread/Service/coroutine；消息从哪里来、到哪里去；谁拥有被修改的状态；哪里可能 yield；失败时留下什么状态；如何用断点、Trace、指标或测试验证。

课程中的 C++ 类比只用来缩短理解路径，不代替语义证明。尤其看到“Actor 单线程”时，必须继续追问：单条 callback 是否会 yield，恢复前同一 Service 是否已处理其他消息。
