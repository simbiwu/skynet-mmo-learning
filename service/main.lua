-- Application bootstrap service. It creates dependencies in safe order, opens the
-- public gate last, then exits; the other services keep the Skynet process alive.
local skynet = require "skynet"

local function getenv(name, default)
    local value = skynet.getenv(name)
    if value == nil or value == "" then
        return default
    end
    return value
end

local function getenv_int(name, default)
    return assert(tonumber(getenv(name, tostring(default))))
end

skynet.start(function()
    skynet.error("========== Skynet MMO Learning Server ==========")

    skynet.uniqueservice("protocol/protoloader")
    skynet.uniqueservice("config/config_service")

    local storage_mgr = skynet.uniqueservice("storage/storage_mgr")
    skynet.call(storage_mgr, "lua", "start", {
        driver = getenv("storage_driver", "memory"),
        pool = getenv_int("storage_pool", 4),
        host = getenv("db_host", "127.0.0.1"),
        port = getenv_int("db_port", 3306),
        database = getenv("db_name", "mmo"),
        user = getenv("db_user", "mmo"),
        password = getenv("db_password", "123456"),
    })

    local scene_mgr = skynet.uniqueservice("scene/scene_mgr")
    skynet.call(scene_mgr, "lua", "start")

    local player_mgr = skynet.uniqueservice("player/player_mgr")
    skynet.call(player_mgr, "lua", "init", {
        storage_mgr = storage_mgr,
        scene_mgr = scene_mgr,
    })

    local auth_service = skynet.uniqueservice("auth/auth")
    local watchdog = skynet.uniqueservice("gateway/watchdog")
    local address, port = skynet.call(watchdog, "lua", "start", {
        address = getenv("gate_host", "0.0.0.0"),
        port = getenv_int("gate_port", 8888),
        maxclient = getenv_int("max_client", 10000),
        player_mgr = player_mgr,
        auth_service = auth_service,
    })

    local debug_port = getenv_int("debug_console_port", 8000)
    if debug_port > 0 then
        skynet.newservice("debug_console", debug_port)
    end

    skynet.error("[Main] gate listening at ", tostring(address), ":", tostring(port))
    skynet.error("[Main] storage=", getenv("storage_driver", "memory"))
    skynet.error("[Main] startup complete")
    skynet.exit()
end)
