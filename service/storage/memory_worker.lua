-- In-memory persistence worker used by default for zero-dependency learning/tests.
-- It deliberately mimics the same RPC surface as mysql_worker.lua.
local skynet = require "skynet"

local CMD = {}
local players = {}

local function clone_player(p)
    if not p then
        return nil
    end
    return {
        player_id = p.player_id,
        name = p.name,
        level = p.level,
        gold = p.gold,
        hp = p.hp,
        max_hp = p.max_hp,
        scene_id = p.scene_id,
        x = p.x,
        y = p.y,
    }
end

function CMD.start(conf, worker_index)
    -- Seed players are deterministic so tutorials and tests have known data.
    local seed = {
        [10001] = { player_id = 10001, name = "Knight10001", level = 10, gold = 10000, hp = 100, max_hp = 100, scene_id = 1, x = 100, y = 100 },
        [10002] = { player_id = 10002, name = "Mage10002", level = 8, gold = 8000, hp = 90, max_hp = 90, scene_id = 1, x = 108, y = 100 },
        [10003] = { player_id = 10003, name = "Rogue10003", level = 6, gold = 6000, hp = 95, max_hp = 95, scene_id = 1, x = 118, y = 100 },
    }

    -- storage_mgr hashes a player to one worker. Seed only the players owned by us.
    for id, p in pairs(seed) do
        if (id % conf.pool) + 1 == worker_index then
            players[id] = clone_player(p)
        end
    end

    skynet.error("[MemoryWorker] started index=", worker_index)
    return true
end

function CMD.load_player(player_id)
    local p = players[player_id]
    if not p then
        return false, "PLAYER_NOT_FOUND"
    end
    -- Clone on load: caller must not accidentally share mutable Lua tables with storage.
    return true, clone_player(p)
end

function CMD.save_player(player)
    players[player.player_id] = clone_player(player)
    return true
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command], "unknown memory storage command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
