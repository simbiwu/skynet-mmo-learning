-- Owns Scene service lifecycle. Scene creation is protected by skynet.queue because
-- newservice/call can yield and two coroutines could otherwise create the same scene.
local skynet = require "skynet"
local queue = require "skynet.queue"

local CMD = {}
local scenes = {}
local create_lock = queue()

local function get_scene(scene_id)
    if scenes[scene_id] then
        return scenes[scene_id]
    end

    return create_lock(function()
        if scenes[scene_id] then
            return scenes[scene_id]
        end
        local service = skynet.newservice("scene/scene")
        skynet.call(service, "lua", "init", scene_id)
        scenes[scene_id] = service
        return service
    end)
end

function CMD.start()
    get_scene(1)
    return true
end

function CMD.enter(info)
    local scene = get_scene(info.scene_id)
    local ok, snapshot = skynet.call(scene, "lua", "enter", info)
    return ok, scene, snapshot
end

function CMD.get(scene_id)
    return scenes[scene_id]
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command], "unknown scene_mgr command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
