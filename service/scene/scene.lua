-- One Scene service owns all real-time spatial state for one map instance.
-- It demonstrates grid AOI, player movement, monsters, combat and respawn.
local skynet = require "skynet"
local sharedata = require "skynet.sharedata"
local Grid = require "scene.aoi_grid"
local combat = require "scene.combat"
local movement = require "scene.movement"

local CMD = {}
local TYPE_PLAYER = 1
local TYPE_MONSTER = 2

local scene_id
local scene_cfg
local grid
local entities = {} -- key -> entity
local visible = {}  -- player_id -> set(entity_key=true)
local tick_count = 0

local function ekey(entity_type, id)
    return (entity_type == TYPE_PLAYER and "p:" or "m:") .. tostring(id)
end

local function public_info(e)
    return {
        entity_type = e.entity_type,
        entity_id = e.id,
        name = e.name,
        x = e.x,
        y = e.y,
        hp = e.hp,
        max_hp = e.max_hp,
    }
end

local function push_player(player_id, name, args)
    local p = entities[ekey(TYPE_PLAYER, player_id)]
    if p and p.agent then
        skynet.send(p.agent, "lua", "push", name, args)
    end
end

local function collect_visible(e)
    local candidates = grid:query_3x3(e.x, e.y)
    local result = {}
    local radius_sq = scene_cfg.view_radius * scene_cfg.view_radius
    local self_key = ekey(e.entity_type, e.id)
    for key in pairs(candidates) do
        if key ~= self_key then
            local other = entities[key]
            if other and combat.distance_sq(e.x, e.y, other.x, other.y) <= radius_sq then
                result[key] = true
            end
        end
    end
    return result
end

local function spawn_monster(cfg)
    local key = ekey(TYPE_MONSTER, cfg.id)
    if entities[key] then
        return
    end

    local monster = {
        entity_type = TYPE_MONSTER,
        id = cfg.id,
        name = cfg.name,
        x = cfg.x,
        y = cfg.y,
        hp = cfg.hp,
        max_hp = cfg.hp,
        spawn_cfg = cfg,
    }
    entities[key] = monster
    grid:insert(key, monster.x, monster.y)

    -- A newly spawned monster becomes visible to nearby players.
    for other_key in pairs(collect_visible(monster)) do
        local other = entities[other_key]
        if other and other.entity_type == TYPE_PLAYER then
            visible[other.id][key] = true
            push_player(other.id, "entity_enter", public_info(monster))
        end
    end
end

function CMD.init(id)
    scene_id = id
    local game_cfg = sharedata.query "game_config"
    scene_cfg = assert(game_cfg.scenes[id], "unknown scene id: " .. tostring(id))
    assert(scene_cfg.grid_size >= scene_cfg.view_radius,
        "this 3x3 AOI lesson requires grid_size >= view_radius")
    -- 配置错误应在 Scene 启动时立刻暴露，而不是等第一个移动请求才发现。
    movement.assert_config(scene_cfg)

    grid = Grid.new(scene_cfg.grid_size)
    for _, monster_cfg in ipairs(scene_cfg.monsters) do
        spawn_monster(monster_cfg)
    end

    -- A lightweight scene tick. Production AI can be split into budgeted phases.
    local function tick()
        tick_count = tick_count + 1
        skynet.timeout(10, tick) -- 10 ticks = 100 ms
    end
    skynet.timeout(10, tick)

    skynet.error("[Scene] initialized id=", scene_id, " grid=", scene_cfg.grid_size,
        " view=", scene_cfg.view_radius)
    return true
end

function CMD.enter(info)
    local key = ekey(TYPE_PLAYER, info.player_id)
    assert(not entities[key], "player already in scene: " .. tostring(info.player_id))

    -- Scene 同时拥有权威坐标和移动额度。PlayerAgent 中的坐标只是成功移动后的持久化快照。
    local move_state, move_error = movement.new_state(scene_cfg, info.x, info.y, skynet.now())
    if not move_state then
        return false, move_error
    end
    local player = {
        entity_type = TYPE_PLAYER,
        id = info.player_id,
        name = info.name,
        level = info.level,
        hp = info.hp,
        max_hp = info.max_hp,
        agent = info.agent,
        x = info.x,
        y = info.y,
        move_state = move_state,
    }
    entities[key] = player
    grid:insert(key, player.x, player.y)

    local now_visible = collect_visible(player)
    visible[player.id] = now_visible
    local snapshot = {}

    for other_key in pairs(now_visible) do
        local other = entities[other_key]
        if other then
            snapshot[#snapshot + 1] = public_info(other)
            if other.entity_type == TYPE_PLAYER then
                visible[other.id][key] = true
                push_player(other.id, "entity_enter", public_info(player))
            end
        end
    end

    skynet.error("[Scene] player enter scene=", scene_id, " player=", player.id)
    return true, snapshot
end

function CMD.leave(player_id)
    local key = ekey(TYPE_PLAYER, player_id)
    local player = entities[key]
    if not player then
        return false
    end

    local old_visible = visible[player_id] or {}
    for other_key in pairs(old_visible) do
        local other = entities[other_key]
        if other and other.entity_type == TYPE_PLAYER then
            local other_visible = visible[other.id]
            if other_visible then
                other_visible[key] = nil
            end
            push_player(other.id, "entity_leave", { entity_type = TYPE_PLAYER, entity_id = player_id })
        end
    end

    visible[player_id] = nil
    grid:remove(key)
    entities[key] = nil
    skynet.error("[Scene] player leave scene=", scene_id, " player=", player_id)
    return true
end

function CMD.move(player_id, x, y)
    local key = ekey(TYPE_PLAYER, player_id)
    local player = entities[key]
    if not player then
        return false, "PLAYER_NOT_IN_SCENE"
    end

    x = assert(math.tointeger(x), "x must be integer")
    y = assert(math.tointeger(y), "y must be integer")

    -- 从读取位置、校验额度到提交 AOI 变更之间没有 yield 点，因此同一 Scene 的
    -- 另一条协程不可能插入并消费同一份额度。校验失败时绝不能改动 AOI 和权威坐标。
    local accepted, reason = movement.try_move(scene_cfg, player.move_state, x, y, skynet.now())
    if not accepted then
        return false, reason
    end

    local old_visible = visible[player_id] or {}
    grid:move(key, x, y)
    player.x, player.y = x, y
    local new_visible = collect_visible(player)
    visible[player_id] = new_visible

    -- Entities leaving this player's view.
    for other_key in pairs(old_visible) do
        if not new_visible[other_key] then
            local other = entities[other_key]
            if other then
                push_player(player_id, "entity_leave", {
                    entity_type = other.entity_type,
                    entity_id = other.id,
                })
                if other.entity_type == TYPE_PLAYER then
                    if visible[other.id] then
                        visible[other.id][key] = nil
                    end
                    push_player(other.id, "entity_leave", {
                        entity_type = TYPE_PLAYER,
                        entity_id = player_id,
                    })
                end
            end
        end
    end

    -- Entities entering this player's view, plus movement broadcast to players who stayed visible.
    for other_key in pairs(new_visible) do
        local other = entities[other_key]
        if other then
            if not old_visible[other_key] then
                push_player(player_id, "entity_enter", public_info(other))
                if other.entity_type == TYPE_PLAYER then
                    visible[other.id][key] = true
                    push_player(other.id, "entity_enter", public_info(player))
                end
            elseif other.entity_type == TYPE_PLAYER then
                push_player(other.id, "entity_move", {
                    entity_type = TYPE_PLAYER,
                    entity_id = player_id,
                    x = x,
                    y = y,
                })
            end
        end
    end

    return true, x, y
end

function CMD.attack(player_id, target_id)
    local player = entities[ekey(TYPE_PLAYER, player_id)]
    local target_key = ekey(TYPE_MONSTER, target_id)
    local target = entities[target_key]
    if not player then
        return false, "PLAYER_NOT_IN_SCENE"
    end
    if not target then
        return false, "TARGET_NOT_FOUND"
    end
    if not combat.in_range(player, target, scene_cfg.attack_range) then
        return false, "OUT_OF_RANGE"
    end

    local damage = combat.player_damage(player)
    target.hp = math.max(0, target.hp - damage)

    local observers = collect_visible(target)
    observers[ekey(TYPE_PLAYER, player_id)] = true -- attacker must see its own result
    for observer_key in pairs(observers) do
        local observer = entities[observer_key]
        if observer and observer.entity_type == TYPE_PLAYER then
            push_player(observer.id, "entity_hp", {
                entity_type = TYPE_MONSTER,
                entity_id = target.id,
                hp = target.hp,
                max_hp = target.max_hp,
            })
        end
    end

    local dead = target.hp == 0
    if dead then
        local cfg = target.spawn_cfg
        for observer_key in pairs(observers) do
            local observer = entities[observer_key]
            if observer and observer.entity_type == TYPE_PLAYER then
                if visible[observer.id] then
                    visible[observer.id][target_key] = nil
                end
                push_player(observer.id, "monster_dead", {
                    monster_id = target.id,
                    killer_id = player_id,
                })
                push_player(observer.id, "entity_leave", {
                    entity_type = TYPE_MONSTER,
                    entity_id = target.id,
                })
            end
        end
        grid:remove(target_key)
        entities[target_key] = nil
        skynet.timeout(cfg.respawn_ticks, function()
            spawn_monster(cfg)
        end)
    end

    return true, target_id, target.hp, dead
end

function CMD.stats()
    local entity_count = 0
    local player_count = 0
    for _, e in pairs(entities) do
        entity_count = entity_count + 1
        if e.entity_type == TYPE_PLAYER then
            player_count = player_count + 1
        end
    end
    return {
        scene_id = scene_id,
        ticks = tick_count,
        players = player_count,
        entities = entity_count,
        cells = grid:count_cells(),
    }
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command], "unknown scene command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
