-- Pure-Lua combat math. Keeping the math Skynet-independent makes it easy to unit test.
local M = {}

function M.distance_sq(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by
    return dx * dx + dy * dy
end

function M.in_range(attacker, target, range)
    return M.distance_sq(attacker.x, attacker.y, target.x, target.y) <= range * range
end

function M.player_damage(player)
    -- Deterministic damage is intentional for a learning project and repeatable tests.
    return 10 + (player.level or 1) * 2
end

return M
