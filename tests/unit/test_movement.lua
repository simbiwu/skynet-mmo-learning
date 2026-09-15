local movement = require "scene.movement"

local cfg = {
    min_x = 0,
    max_x = 200,
    min_y = 0,
    max_y = 200,
    move_speed = 10,
    move_burst_seconds = 1,
}

local state = movement.new_state(cfg, 100, 100, 1000)
local invalid_state, invalid_reason = movement.new_state(cfg, -1, 100, 1000)
assert(not invalid_state and invalid_reason == "INITIAL_POSITION_OUT_OF_BOUNDS",
    "损坏的持久化出生点应返回可处理错误，不能创建非法状态")

local ok, reason = movement.try_move(cfg, state, 201, 100, 1000)
assert(not ok and reason == "OUT_OF_BOUNDS", "必须拒绝地图边界外坐标")
assert(state.x == 100 and state.y == 100, "越界请求不能修改权威坐标")

ok, reason = movement.try_move(cfg, state, 111, 100, 1000)
assert(not ok and reason == "MOVE_TOO_FAST", "必须拒绝超过初始突发额度的瞬移")
assert(state.x == 100 and state.y == 100, "超速请求不能修改权威坐标")

ok = movement.try_move(cfg, state, 110, 100, 1000)
assert(ok and state.x == 110 and state.move_credit == 0, "合法移动应消费额度并提交坐标")

ok, reason = movement.try_move(cfg, state, 111, 100, 1000)
assert(not ok and reason == "MOVE_TOO_FAST", "同一 tick 内不能重复使用已消费额度")

ok = movement.try_move(cfg, state, 115, 100, 1050)
assert(ok and state.move_credit == 0, "0.5 秒应按 10 单位/秒补充 5 单位额度")

ok = movement.try_move(cfg, state, 105, 100, 1200)
assert(ok and state.move_credit == 0, "空闲补充量不能超过 Token Bucket 容量")

print("PASS test_movement")
