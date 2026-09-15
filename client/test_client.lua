-- Cross-platform learning client executed with Skynet's bundled Lua 5.4.
-- On Windows the provided PowerShell wrapper runs this client inside WSL2, matching
-- the officially supported POSIX runtime used by the server.
package.cpath = "./third_party/skynet/luaclib/?.so"
package.path = "./third_party/skynet/lualib/?.lua;./lualib/?.lua;" .. package.path

if _VERSION ~= "Lua 5.4" then
    error("Use Skynet's bundled Lua 5.4")
end

local socket = require "client.socket"
local sproto = require "sproto"
local sprotoparser = require "sprotoparser"
local schema = require "protocol.schema"

local opts = { host = "127.0.0.1", port = 8888, player = 10001, auto = false }
for _, v in ipairs(arg or {}) do
    if v == "--auto" then
        opts.auto = true
    else
        local k, value = v:match("^%-%-([%w_]+)=(.+)$")
        if k == "port" or k == "player" then
            opts[k] = tonumber(value)
        elseif k == "host" then
            opts.host = value
        end
    end
end

local host = sproto.new(sprotoparser.parse(schema.s2c)):host "package"
local request = host:attach(sproto.new(sprotoparser.parse(schema.c2s)))
local fd = assert(socket.connect(opts.host, opts.port))
print(string.format("[Client] connected %s:%d fd=%d", opts.host, opts.port, fd))

local recv_buffer = ""
local session = 0

local function send_package(payload)
    socket.send(fd, string.pack(">s2", payload))
end

local function unpack_one(text)
    if #text < 2 then
        return nil, text
    end
    local size = text:byte(1) * 256 + text:byte(2)
    if #text < size + 2 then
        return nil, text
    end
    return text:sub(3, size + 2), text:sub(size + 3)
end

local function recv_package_blocking()
    while true do
        local payload
        payload, recv_buffer = unpack_one(recv_buffer)
        if payload then
            return payload
        end

        local data = socket.recv(fd)
        if data == "" then
            error("server closed")
        elseif data then
            recv_buffer = recv_buffer .. data
        else
            socket.usleep(1000)
        end
    end
end

local function send_rpc(name, args)
    session = session + 1
    send_package(request(name, args or {}, session))
    return session
end

local function dump_table(t)
    if not t then return end
    for k, v in pairs(t) do
        print("    ", k, v)
    end
end

local function wait_response(target_session)
    while true do
        local protocol_type, a, b = host:dispatch(recv_package_blocking())
        if protocol_type == "REQUEST" then
            print("[Push]", a)
            dump_table(b)
        elseif protocol_type == "RESPONSE" then
            print("[Response] session=", a)
            dump_table(b)
            if a == target_session then
                return b
            end
        else
            error("unknown sproto dispatch type: " .. tostring(protocol_type))
        end
    end
end

local function rpc(name, args)
    return wait_response(send_rpc(name, args))
end

local function login()
    local result = rpc("login", {
        player_id = opts.player,
        token = "dev:" .. tostring(opts.player),
    })
    assert(result and result.code == 0, "login failed")
    return result
end

local function auto_run()
    local info = login()
    assert(rpc("ping", {}).code == 0)

    -- Player 10001 starts at (100,100). Green Slime 100001 is at (104,100), so
    -- the player starts inside the 5-unit attack range.
    if opts.player == 10001 then
        local dead = false
        for i = 1, 10 do
            local r = rpc("attack", { target_id = 100001 })
            if r.code ~= 0 then
                error("attack failed: " .. tostring(r.message))
            end
            if r.dead then
                dead = true
                break
            end
        end
        assert(dead, "expected training slime to die")
    else
        assert(rpc("move", { x = info.x + 1, y = info.y }).code == 0)
    end

    -- 回归检查：服务端必须拒绝越界坐标，客户端不能直接决定权威位置。
    local invalid_move = rpc("move", { x = 1000000, y = info.y })
    assert(invalid_move.code ~= 0 and invalid_move.message == "OUT_OF_BOUNDS",
        "服务端应拒绝越界移动")

    local logout_session = send_rpc("logout", {})
    -- Server may close quickly after queuing the response. The gameplay checks above
    -- already prove the end-to-end path; logout response is intentionally best-effort.
    print("SMOKE_OK player=" .. tostring(opts.player) .. " logout_session=" .. tostring(logout_session))
end

local function interactive_run()
    local info = login()
    print("Commands: ping | move X Y | attack ID | logout")
    while true do
        -- client.socket 在 C 模块加载时已经启动 stdin pthread，并把完整行放入其私有队列。
        -- 这里若再用 io.read，会出现两个 Reader 竞争同一 TTY：命令在 Terminal 中有回显，
        -- 却可能被 C 线程取走而永远到不了 Lua 主循环。必须使用官方 readstdin 队列。
        local line
        repeat
            line = socket.readstdin()
            if not line then
                socket.usleep(1000)
            end
        until line
        local cmd, rest = line:match("^(%S+)%s*(.*)$")
        if cmd == "ping" then
            rpc("ping", {})
        elseif cmd == "move" then
            local x, y = rest:match("^(%-?%d+)%s+(%-?%d+)$")
            if x then rpc("move", { x = tonumber(x), y = tonumber(y) }) end
        elseif cmd == "attack" then
            local id = tonumber(rest)
            if id then rpc("attack", { target_id = id }) end
        elseif cmd == "logout" then
            send_rpc("logout", {})
            break
        else
            print("unknown command")
        end
    end
end

if opts.auto then
    auto_run()
else
    interactive_run()
end
