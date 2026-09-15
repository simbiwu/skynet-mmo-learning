-- Maps player_id -> unique PlayerAgent service.
-- 64 sharded skynet.queue locks prevent duplicate Agent creation without keeping
-- an unbounded one-lock-per-ever-seen-player table.
local skynet = require "skynet"
local queue = require "skynet.queue"

local CMD = {}
local players = {}
local login_locks = {}
local storage_mgr
local scene_mgr

for i = 1, 64 do
    login_locks[i] = queue()
end

local function player_lock(player_id)
    return login_locks[(player_id % #login_locks) + 1]
end

function CMD.init(conf)
    storage_mgr = assert(conf.storage_mgr)
    scene_mgr = assert(conf.scene_mgr)
    return true
end

function CMD.login(player_id)
    player_id = assert(math.tointeger(player_id), "player_id must be integer")
    return player_lock(player_id)(function()
        local existing = players[player_id]
        if existing then
            return existing, false
        end

        local agent = skynet.newservice("player/player_agent")
        local ok, err = skynet.call(agent, "lua", "load", {
            player_id = player_id,
            storage_mgr = storage_mgr,
            scene_mgr = scene_mgr,
            player_mgr = skynet.self(),
        })
        if not ok then
            skynet.send(agent, "lua", "shutdown")
            return nil, false, err
        end

        players[player_id] = agent
        return agent, true
    end)
end

function CMD.remove(player_id, agent)
    if players[player_id] ~= agent then
        return false
    end
    players[player_id] = nil
    return true
end

function CMD.get(player_id)
    return players[player_id]
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command], "unknown player_mgr command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
