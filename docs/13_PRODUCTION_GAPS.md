# 13 - 当前工程与生产环境的差距

本仓库采用接近真实项目的 Service 边界，但还不是可以直接运营的 MMO Server。`integration smoke test` 通过只能证明当前 Happy Path，不等于完成生产验收。

至少需要补齐：

- LoginServer/Center 认证、一次性 Token、过期与 Replay Protection。
- Protocol Version、Packet Size、Rate Limit、Fuzz 与恶意输入处理。
- Collision/Pathfinding 和客户端 Prediction Correction；地图边界与权威速度校验已经由当前 P0 覆盖。
- 完整 Skill/Buff/Combat Tick 模型，以及 Monster AI、Pathfinding 和每 Tick CPU Budget。
- Dirty/Versioned Snapshot、定期保存及金币、道具、支付等关键数据的 Ledger/Journal 和幂等 Operation ID。
- Database Reconnect、Retry、Backpressure、Slow Query 和连接池指标。
- Structured Log、Trace/Context ID、Mailbox/RPC Latency、Profiling 与告警。
- Packet Record/Replay、Core Dump、GDB 和确定性故障注入流程。
- Scene Density/Hotspot 保护、分线/分片、Scene Transfer Saga 与 Epoch。
- Guild、World、Rank、Chat 和 Cluster 的 Owner、分片及失败协议。
- Config Validation、Versioned Hot Reload、Code Hotfix 与 State Migration。
- Graceful Shutdown、停止接入、批量玩家落盘、进程恢复和灰度回滚。
- Reconnect Session Security 与完整 State Resync，而不只是复用 PlayerAgent。

## 已确认的重连/离线竞态窗口

当前 `service/player/player_agent.lua` 的 60 秒 Grace Timer 能用 `offline_version` 拒绝“timer 触发前已经发生的重连”。但 `offline()` 开始后会依次 `call Scene.leave`、`call Storage.save` 和 `call PlayerMgr.remove`；这些位置都会 yield，而 `CMD.bind_client` 没有经过同一个 `serial`。

因此存在窄窗口：Offline Pipeline 已开始并在下游 RPC 等待时，新连接重新绑定；旧 coroutine 恢复后仍可能继续 remove 并退出 Agent。生产修复必须把 Offline Pipeline 变成带 Version 的多阶段状态机，每次 await 恢复后重新校验，或者让 bind/offline 使用同一互斥协议，并增加可确定打开该窗口的 Regression Test。

详细推导和验证实验见第三课 `docs/Skynet第三课_完整MMO业务闭环与一致性.md`。

生产证据体系、性能方法、故障剧本、能力矩阵与上线门禁集中见第四课 `docs/Skynet第四课_生产工程故障诊断与性能.md`。其中明确区分“当前仓库已实现”“Skynet 上游提供接口”和“正式项目仍需接入”，不能把教学用 Debug Console 或单次 Smoke Test 当作生产完成度。
