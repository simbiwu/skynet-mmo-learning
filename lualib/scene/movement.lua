-- 服务端权威移动校验。
--
-- 这是普通 Lua 模块而不是 Service：移动额度只属于 Scene 中的玩家实体，
-- 校验也不需要独立 Actor。保持它无 Skynet 依赖，便于直接做单元测试。
local M = {}

local TICKS_PER_SECOND = 100

function M.assert_config(cfg)
    assert(cfg.min_x <= cfg.max_x and cfg.min_y <= cfg.max_y, "地图边界配置无效")
    assert(cfg.move_speed > 0, "move_speed 必须大于 0")
    assert(cfg.move_burst_seconds > 0, "move_burst_seconds 必须大于 0")
end

local function in_bounds(cfg, x, y)
    return x >= cfg.min_x and x <= cfg.max_x
        and y >= cfg.min_y and y <= cfg.max_y
end

function M.new_state(cfg, x, y, now_tick)
    M.assert_config(cfg)
    if not in_bounds(cfg, x, y) then
        return nil, "INITIAL_POSITION_OUT_OF_BOUNDS"
    end
    return {
        x = x,
        y = y,
        -- 初始额度允许刚进入场景的玩家立即移动一小段；它不是可永久透支的距离。
        move_credit = cfg.move_speed * cfg.move_burst_seconds,
        last_move_tick = now_tick,
    }
end

function M.try_move(cfg, state, x, y, now_tick)
    if not in_bounds(cfg, x, y) then
        return false, "OUT_OF_BOUNDS"
    end

    -- Token Bucket 按经过时间补充可移动距离。即使本次被拒绝也更新时间，
    -- 因而重复发送非法请求不会重复领取同一段时间的额度。
    local elapsed_ticks = math.max(0, now_tick - state.last_move_tick)
    local capacity = cfg.move_speed * cfg.move_burst_seconds
    state.move_credit = math.min(capacity,
        state.move_credit + elapsed_ticks * cfg.move_speed / TICKS_PER_SECOND)
    state.last_move_tick = now_tick

    local dx = x - state.x
    local dy = y - state.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance > state.move_credit then
        return false, "MOVE_TOO_FAST"
    end

    state.move_credit = state.move_credit - distance
    state.x = x
    state.y = y
    return true, x, y
end

return M
