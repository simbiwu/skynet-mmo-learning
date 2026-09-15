-- Connection lifecycle + pre-login protocol service.
-- After login, official gate.lua forwards packets directly to PlayerAgent.
local skynet = require "skynet"
local sprotoloader = require "sprotoloader"
local frame = require "protocol.frame"

local CMD = {}
local SOCKET = {}
local gate
local player_mgr
local auth_service
local host
local connections = {} -- fd -> connection table
local next_connection_id = 0

local function new_connection_id()
    next_connection_id = next_connection_id + 1
    return next_connection_id
end

local function alive(fd, connection)
    return connections[fd] == connection
end

local function close_later(fd, connection_id)
    skynet.timeout(10, function() -- 0.1 s: allow a final response to enter socket send queue
        local c = connections[fd]
        if c and c.id == connection_id then
            skynet.call(gate, "lua", "kick", fd)
        end
    end)
end

function SOCKET.open(fd, addr)
    local c = {
        id = new_connection_id(),
        fd = fd,
        addr = addr,
        state = "CONNECTED",
        agent = nil,
    }
    connections[fd] = c
    skynet.error("[Watchdog] open fd=", fd, " conn=", c.id, " addr=", addr)

    -- gate accepts the socket first but does not start client reads until accept/openclient.
    skynet.call(gate, "lua", "accept", fd)
end

local function on_close(fd)
    local c = connections[fd]
    if not c then
        return
    end
    connections[fd] = nil
    if c.agent then
        skynet.send(c.agent, "lua", "client_closed", fd, c.id)
    end
    skynet.error("[Watchdog] close fd=", fd, " conn=", c.id)
end

function SOCKET.close(fd)
    on_close(fd)
end

function SOCKET.error(fd, msg)
    skynet.error("[Watchdog] socket error fd=", fd, " msg=", msg)
    on_close(fd)
end

function SOCKET.warning(fd, size)
    skynet.error("[Watchdog] socket send-buffer warning fd=", fd, " KB=", size)
end

function SOCKET.data(fd, msg)
    local c = connections[fd]
    if not c or c.state ~= "CONNECTED" then
        return
    end

    local ok, protocol_type, name, args, response = pcall(function()
        return host:dispatch(msg)
    end)
    if not ok or protocol_type ~= "REQUEST" or name ~= "login" then
        skynet.error("[Watchdog] first packet must be valid login fd=", fd)
        c.state = "CLOSING"
        close_later(fd, c.id)
        return
    end

    -- Change state BEFORE first yield. Otherwise a second packet may enter login again.
    c.state = "AUTHING"

    local auth_ok = skynet.call(auth_service, "lua", "verify", args.player_id, args.token)
    if not alive(fd, c) then
        return
    end
    if not auth_ok then
        if response then
            frame.write(fd, response { code = 1, message = "AUTH_FAILED" })
        end
        c.state = "CLOSING"
        close_later(fd, c.id)
        return
    end

    local agent, is_new, err = skynet.call(player_mgr, "lua", "login", args.player_id)
    if not alive(fd, c) then
        if is_new and agent then
            skynet.send(agent, "lua", "abort_if_unbound")
        end
        return
    end
    if not agent then
        if response then
            frame.write(fd, response { code = 2, message = err or "LOAD_PLAYER_FAILED" })
        end
        c.state = "CLOSING"
        close_later(fd, c.id)
        return
    end

    c.agent = agent
    skynet.call(agent, "lua", "bind_client", {
        fd = fd,
        watchdog = skynet.self(),
        connection_id = c.id,
    })
    if not alive(fd, c) then
        return
    end

    local enter_ok, player_info = skynet.call(agent, "lua", "enter_world")
    if not alive(fd, c) then
        return
    end
    if not enter_ok then
        if response then
            frame.write(fd, response { code = 3, message = player_info or "ENTER_WORLD_FAILED" })
        end
        c.state = "CLOSING"
        close_later(fd, c.id)
        return
    end

    -- gate.forward changes future packet destination from Watchdog to PlayerAgent.
    skynet.call(gate, "lua", "forward", fd, 0, agent)
    c.state = "PLAYING"

    if response then
        frame.write(fd, response {
            code = 0,
            message = "OK",
            player_id = player_info.player_id,
            name = player_info.name,
            level = player_info.level,
            gold = player_info.gold,
            hp = player_info.hp,
            max_hp = player_info.max_hp,
            scene_id = player_info.scene_id,
            x = player_info.x,
            y = player_info.y,
        })
    end

    -- Snapshot/AOI pushes were queued while login was in progress. Flush only after
    -- the login response has been queued to preserve client-visible ordering.
    skynet.send(agent, "lua", "client_ready")
    skynet.error("[Watchdog] login success player=", args.player_id, " fd=", fd)
end

function CMD.kick(fd, connection_id, reason)
    local c = connections[fd]
    if not c or c.id ~= connection_id then
        return false
    end
    c.state = "CLOSING"
    skynet.call(gate, "lua", "kick", fd)
    return true
end

function CMD.start(conf)
    player_mgr = assert(conf.player_mgr)
    auth_service = assert(conf.auth_service)
    gate = skynet.newservice("gate")
    return skynet.call(gate, "lua", "open", {
        address = conf.address,
        port = conf.port,
        maxclient = conf.maxclient,
        nodelay = true,
        watchdog = skynet.self(),
    })
end

skynet.start(function()
    host = sprotoloader.load(1):host "package"
    skynet.dispatch("lua", function(session, source, command, subcommand, ...)
        if command == "socket" then
            local fn = assert(SOCKET[subcommand], "unknown socket event: " .. tostring(subcommand))
            fn(...)
            return
        end

        local fn = assert(CMD[command], "unknown watchdog command: " .. tostring(command))
        local result = { fn(subcommand, ...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
