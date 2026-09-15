-- Creates a fixed storage worker pool and hashes each player to one worker.
-- The manager is used for routing in this learning version; later lessons can cache
-- the selected worker address inside PlayerAgent to remove the extra hop.
local skynet = require "skynet"

local CMD = {}
local workers = {}

local function get_worker(player_id)
    assert(#workers > 0, "storage pool is not started")
    return workers[(player_id % #workers) + 1]
end

function CMD.start(conf)
    assert(conf.pool and conf.pool > 0, "storage pool must be > 0")
    local service_name
    if conf.driver == "memory" then
        service_name = "storage/memory_worker"
    elseif conf.driver == "mysql" then
        service_name = "storage/mysql_worker"
    else
        error("unsupported storage driver: " .. tostring(conf.driver))
    end

    for i = 1, conf.pool do
        local worker = skynet.newservice(service_name)
        skynet.call(worker, "lua", "start", conf, i)
        workers[i] = worker
    end

    skynet.error("[StorageMgr] driver=", conf.driver, " workers=", #workers)
    return true
end

function CMD.load_player(player_id)
    return skynet.call(get_worker(player_id), "lua", "load_player", player_id)
end

function CMD.save_player(player)
    return skynet.call(get_worker(player.player_id), "lua", "save_player", player)
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command], "unknown storage_mgr command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
