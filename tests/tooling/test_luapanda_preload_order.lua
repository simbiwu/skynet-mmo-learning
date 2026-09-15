-- 回归测试：LuaPanda 必须先包装 coroutine.create，skynet.lua 才能缓存该包装。
-- 这里用最小替身隔离加载顺序，不要求开发机已经下载 LuaPanda 或 LuaSocket。
local original = {
    service_name = SERVICE_NAME,
    coroutine_create = coroutine.create,
    core_loaded = package.loaded["skynet.core"],
    skynet_loaded = package.loaded.skynet,
    luapanda_loaded = package.loaded.LuaPanda,
    skynet_preload = package.preload.skynet,
    luapanda_preload = package.preload.LuaPanda,
}

local debugger_create
local skynet_cached_create
local start_args

local function restore()
    SERVICE_NAME = original.service_name
    coroutine.create = original.coroutine_create
    package.loaded["skynet.core"] = original.core_loaded
    package.loaded.skynet = original.skynet_loaded
    package.loaded.LuaPanda = original.luapanda_loaded
    package.preload.skynet = original.skynet_preload
    package.preload.LuaPanda = original.luapanda_preload
end

local ok, err = xpcall(function()
    SERVICE_NAME = "scene/scene"
    package.loaded["skynet.core"] = {
        command = function(command, name)
            assert(command == "GETENV")
            return ({
                luapanda_service = "scene/scene",
                luapanda_host = "127.0.0.1",
                luapanda_port = "8818",
            })[name]
        end,
    }

    package.loaded.LuaPanda = nil
    package.preload.LuaPanda = function()
        debugger_create = function(fn)
            return original.coroutine_create(fn)
        end
        coroutine.create = debugger_create
        return {
            start = function(host, port)
                start_args = { host, port }
            end,
        }
    end

    package.loaded.skynet = nil
    package.preload.skynet = function()
        -- 对应 skynet.lua 顶层的 local coroutine_create = coroutine.create。
        skynet_cached_create = coroutine.create
        return {
            error = function() end,
            self = function() return 1 end,
            address = function() return ":00000001" end,
        }
    end

    assert(loadfile("lualib/debug/luapanda_preload.lua"))()
    assert(start_args[1] == "127.0.0.1" and start_args[2] == 8818)
    assert(skynet_cached_create == debugger_create,
        "skynet.lua cached coroutine.create before LuaPanda wrapped it")
end, debug.traceback)

restore()
assert(ok, err)
print("LUAPANDA_PRELOAD_ORDER_OK")
