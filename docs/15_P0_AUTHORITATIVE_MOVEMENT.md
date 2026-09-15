# 15 - P0：服务端权威移动校验

## 为什么是 P0

客户端只能表达“我想移动到哪里”，不能直接决定角色的最终位置。旧实现只检查 `x/y` 是否为整数，随后立即修改 `Scene` 的坐标和 AOI；恶意客户端可以一次请求移动到任意位置，越界、瞬移并绕过攻击距离。

本项补齐两个最小但完整的规则：

- 地图边界：目标点必须位于 `min_x..max_x`、`min_y..max_y`。
- 移动速度：使用 Token Bucket 限制一段时间内可以移动的总距离。

碰撞、寻路和客户端预测/回滚仍是后续课程，不在本次 P0 中伪装成已经完成。

## 状态归属

每个在线玩家在 `Scene` 中拥有：

```text
x/y                 权威实时坐标
move_credit         当前还可移动的距离额度
last_move_tick      上一次结算额度的 Skynet tick
```

`PlayerAgent.player.x/y` 只在 `Scene` 接受移动后更新，用于最终持久化和重连恢复。客户端、`PlayerAgent` 与 `SceneMgr` 都不拥有实时移动判定权。

校验算法放在普通模块 `lualib/scene/movement.lua`，但状态仍存放于 `Scene` 的 entity 中。计算逻辑可复用，不等于需要创建一个新的 Actor。

## Token Bucket 如何工作

配置示例：

```lua
move_speed = 10          -- 每秒补充 10 个坐标单位
move_burst_seconds = 1   -- 最多储存 1 秒的额度
```

因此容量为 10。玩家进入场景时得到 10 单位初始额度；移动 6 单位后剩余 4。经过 0.5 秒会补充 5，但总额度永远不超过容量。每次移动按欧氏距离消费额度：

```text
distance = sqrt((new_x - old_x)^2 + (new_y - old_y)^2)
```

这比“每个请求最多移动 N 格”更可靠，因为客户端不能靠提高发包频率获得更高速度。`move_burst_seconds` 是对网络抖动的容忍窗口，不是额外的永久速度。

## Coroutine 与 yield 审查

`Scene.CMD.move` 的关键顺序是：

```text
读取 Scene entity
  -> 边界校验
  -> 补充并消费移动额度
  -> 修改 Grid AOI
  -> 提交权威坐标
  -> send AOI 通知
```

这段状态变更中没有 `skynet.call`、`skynet.sleep` 或其他 yield 点。`skynet.send` 只把通知放入目标 mailbox，不等待响应，因此无需用 `skynet.queue` 再包一层。若未来在校验中加入寻路 Service 的同步 RPC，必须重新审查：RPC 返回后，之前读取的坐标和额度是否已经过期。

本项没有定时回调消息；`skynet.now()` 只读取当前 tick，因此不需要新增 generation/version。已有的连接 `connection_id` 与离线 `offline_version` 规则不受影响。

## 错误与客户端处理

- `OUT_OF_BOUNDS`：目标点越过地图边界。
- `MOVE_TOO_FAST`：当前额度不足。

拒绝时 `Scene` 不修改权威坐标和 AOI。客户端收到失败响应后，应回到服务器最近确认的位置；本学习客户端目前只打印响应，预测与平滑纠正留给后续客户端课程。

场景在启动时校验移动配置；持久化出生点若已越界，`Scene.enter` 返回 `INITIAL_POSITION_OUT_OF_BOUNDS`，不会用 `assert` 把一次可预期的数据错误升级成挂起登录链路的 Service 异常。

## 测试

`tests/unit/test_movement.lua` 覆盖边界、瞬移拒绝、同 tick 重复消费、按时间补充和容量上限。集成 smoke test 还会通过真实 Gate/Sproto 链路发送越界请求，并验证服务器返回 `OUT_OF_BOUNDS`。
