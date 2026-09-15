-- One online player = one PlayerAgent service.
-- This service owns persistent player state and serializes client business requests.
local skynet = require "skynet"
local socket = require "skynet.socket"
local sprotoloader = require "sprotoloader"
local queue = require "skynet.queue"
local frame = require "protocol.frame"

local CMD = {}
local REQUEST = {}

local player
local storage_mgr
local scene_mgr
local player_mgr
local scene_service
local client_fd
local client_watchdog
local client_connection_id
local client_ready = false
local offline_version = 0
local pending_pushes = {}
local serial = queue()
local host
local send_request

local function send_package(payload)
    if not client_fd then
        return false
    end
    return frame.write(client_fd, payload)
end

local function do_push(name, args)
    return send_package(send_request(name, args))
end

local function push(name, args)
    if not client_fd then
        return false
    end
    if not client_ready then
        pending_pushes[#pending_pushes + 1] = { name = name, args = args }
        return true
    end
    return do_push(name, args)
end

function CMD.load(conf)
    storage_mgr = assert(conf.storage_mgr)
    scene_mgr = assert(conf.scene_mgr)
    player_mgr = assert(conf.player_mgr)

    local ok, result = skynet.call(storage_mgr, "lua", "load_player", conf.player_id)
    if not ok then
        return false, result
    end
    player = result
    skynet.error("[PlayerAgent] loaded player=", player.player_id)
    return true
end

function CMD.bind_client(conf)
    -- If a second connection arrives, the old connection is kicked, but the same
    -- PlayerAgent is reused. Player identity and connection lifetime are separate.
    if client_fd and client_fd ~= conf.fd then
        skynet.send(client_watchdog, "lua", "kick", client_fd, client_connection_id, "REPLACED")
    end

    client_fd = conf.fd
    client_watchdog = conf.watchdog
    client_connection_id = conf.connection_id
    client_ready = false
    pending_pushes = {}
    offline_version = offline_version + 1
    return true
end

function CMD.enter_world()
    if not scene_service then
        local ok, scene, snapshot = skynet.call(scene_mgr, "lua", "enter", {
            player_id = player.player_id,
            name = player.name,
            level = player.level,
            hp = player.hp,
            max_hp = player.max_hp,
            agent = skynet.self(),
            scene_id = player.scene_id,
            x = player.x,
            y = player.y,
        })
        if not ok then
            return false, "ENTER_SCENE_FAILED"
        end
        scene_service = scene
        for _, entity in ipairs(snapshot or {}) do
            pending_pushes[#pending_pushes + 1] = { name = "entity_enter", args = entity }
        end
    end

    return true, {
        player_id = player.player_id,
        name = player.name,
        level = player.level,
        gold = player.gold,
        hp = player.hp,
        max_hp = player.max_hp,
        scene_id = player.scene_id,
        x = player.x,
        y = player.y,
    }
end

function CMD.client_ready()
    client_ready = true
    local list = pending_pushes
    pending_pushes = {}
    for _, item in ipairs(list) do
        do_push(item.name, item.args)
    end
    return true
end

function CMD.push(name, args)
    return push(name, args)
end

function REQUEST.ping(args)
    return { code = 0, server_time = math.floor(skynet.time()) }
end

function REQUEST.move(args)
    if not scene_service then
        return { code = 1, message = "NOT_IN_SCENE" }
    end
    local x = math.tointeger(args.x)
    local y = math.tointeger(args.y)
    if not x or not y then
        return { code = 2, message = "INVALID_POSITION" }
    end

    local ok, rx, ry = skynet.call(scene_service, "lua", "move", player.player_id, x, y)
    if not ok then
        return { code = 3, message = rx or "MOVE_FAILED" }
    end
    player.x, player.y = rx, ry
    return { code = 0, message = "OK", x = rx, y = ry }
end

function REQUEST.attack(args)
    if not scene_service then
        return { code = 1, message = "NOT_IN_SCENE", target_id = args.target_id, target_hp = 0, dead = false }
    end
    local target_id = math.tointeger(args.target_id)
    if not target_id then
        return { code = 2, message = "INVALID_TARGET", target_id = 0, target_hp = 0, dead = false }
    end

    local ok, a, b, c = skynet.call(scene_service, "lua", "attack", player.player_id, target_id)
    if not ok then
        return { code = 3, message = a or "ATTACK_FAILED", target_id = target_id, target_hp = 0, dead = false }
    end
    return { code = 0, message = "OK", target_id = a, target_hp = b, dead = c }
end

function REQUEST.logout(args)
    -- Delay the close by one Skynet tick. The request dispatcher can therefore encode
    -- and queue the logout response before Watchdog closes the socket.
    local watchdog = client_watchdog
    local fd = client_fd
    local connection_id = client_connection_id
    if watchdog and fd then
        skynet.timeout(1, function()
            if client_fd == fd and client_connection_id == connection_id then
                skynet.send(watchdog, "lua", "kick", fd, connection_id, "LOGOUT")
            end
        end)
    end
    return { code = 0 }
end

local function dispatch_request(name, args)
    local fn = REQUEST[name]
    if not fn then
        return { code = 404, message = "UNKNOWN_REQUEST" }
    end

    -- skynet.queue is essential here: even when fn() yields inside skynet.call,
    -- the next client business request for this player waits for the first one.
    return serial(fn, args)
end

local function offline()
    if client_fd then
        return
    end

    if scene_service then
        skynet.call(scene_service, "lua", "leave", player.player_id)
        scene_service = nil
    end

    local ok, err = skynet.call(storage_mgr, "lua", "save_player", player)
    if not ok then
        skynet.error("[PlayerAgent] final save failed player=", player.player_id, " err=", err)
    end

    skynet.call(player_mgr, "lua", "remove", player.player_id, skynet.self())
    skynet.error("[PlayerAgent] offline player=", player.player_id)
    skynet.exit()
end

function CMD.client_closed(fd, connection_id)
    -- fd alone is not safe because an OS descriptor can be reused. The logical
    -- connection_id is the generation check that rejects stale close messages.
    if fd ~= client_fd or connection_id ~= client_connection_id then
        return false
    end

    client_fd = nil
    client_watchdog = nil
    client_connection_id = nil
    client_ready = false
    pending_pushes = {}
    offline_version = offline_version + 1
    local version = offline_version

    skynet.timeout(6000, function() -- 60 seconds reconnect grace period
        if version ~= offline_version or client_fd then
            return
        end
        serial(offline)
    end)
    return true
end

function CMD.abort_if_unbound()
    if client_fd then
        return false
    end
    skynet.call(player_mgr, "lua", "remove", player.player_id, skynet.self())
    skynet.exit()
end

function CMD.shutdown()
    skynet.exit()
end

skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
    unpack = function(msg, sz)
        return host:dispatch(msg, sz)
    end,
    dispatch = function(fd, source, protocol_type, ...)
        -- gate.forward uses fd as the Skynet message session. It is NOT an RPC
        -- response session, therefore skynet.ret() must not be called.
        skynet.ignoreret()

        if fd ~= client_fd then
            skynet.error("[PlayerAgent] stale client packet fd=", fd)
            return
        end

        if protocol_type ~= "REQUEST" then
            skynet.error("[PlayerAgent] unexpected client protocol type=", protocol_type)
            return
        end

        local name, args, response = ...
        local ok, result = pcall(dispatch_request, name, args)
        if not ok then
            skynet.error("[PlayerAgent] request failed name=", name, " err=", result)
            result = { code = 500, message = "SERVER_ERROR" }
        end

        if response then
            send_package(response(result))
        end
    end,
}

skynet.start(function()
    host = sprotoloader.load(1):host "package"
    send_request = host:attach(sprotoloader.load(2))

    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command], "unknown player_agent command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
