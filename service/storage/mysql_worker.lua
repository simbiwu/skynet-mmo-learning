-- MySQL persistence worker. This is optional; memory storage is the default learning mode.
local skynet = require "skynet"
local mysql = require "skynet.db.mysql"

local CMD = {}
local db

function CMD.start(conf, worker_index)
    db = mysql.connect {
        host = conf.host,
        port = conf.port,
        database = conf.database,
        user = conf.user,
        password = conf.password,
        charset = "utf8mb4",
    }
    assert(db, "mysql.connect returned nil")
    skynet.error("[MySQLWorker] connected index=", worker_index)
    return true
end

function CMD.load_player(player_id)
    player_id = assert(math.tointeger(player_id), "player_id must be integer")
    local sql = string.format([[
SELECT player_id, name, level, gold, hp, max_hp, scene_id, x, y
FROM player
WHERE player_id = %d
LIMIT 1]], player_id)

    local result = db:query(sql)
    if result.badresult then
        return false, result.err or "MYSQL_ERROR"
    end
    if #result == 0 then
        return false, "PLAYER_NOT_FOUND"
    end

    local row = result[1]
    return true, {
        player_id = tonumber(row.player_id),
        name = row.name,
        level = tonumber(row.level),
        gold = tonumber(row.gold),
        hp = tonumber(row.hp),
        max_hp = tonumber(row.max_hp),
        scene_id = tonumber(row.scene_id),
        x = tonumber(row.x),
        y = tonumber(row.y),
    }
end

function CMD.save_player(player)
    -- Numeric fields only in this teaching UPDATE, so format-string injection is avoided.
    -- Production DAOs should use a disciplined SQL builder/escaping layer for all strings.
    local sql = string.format([[
UPDATE player
SET level=%d, gold=%d, hp=%d, max_hp=%d, scene_id=%d, x=%d, y=%d
WHERE player_id=%d]],
        player.level,
        player.gold,
        player.hp,
        player.max_hp,
        player.scene_id,
        player.x,
        player.y,
        player.player_id)

    local result = db:query(sql)
    if result.badresult then
        return false, result.err or "MYSQL_ERROR"
    end
    return true
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command], "unknown mysql storage command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
