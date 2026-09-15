-- 仅由 config/debug_luapanda.lua 加载，并且只注入明确指定的一个 Service。
-- LuaPanda 使用 LuaSocket 和 Debug Hook；它可能阻塞当前 Worker Thread，并改变 Coroutine
-- 时序，所以绝不能在正常、共享测试或生产配置中启用。
-- 这里必须先使用 C 模块读取环境变量，不能提前 require "skynet"。
-- skynet.lua 在模块加载时会把 coroutine.create 缓存到局部变量；LuaPanda 则通过替换
-- coroutine.create 来跟踪并给新 Coroutine 安装 Debug Hook。若顺序相反，主 Service 能
-- 连上 Debug Adapter，但之后由 Skynet 创建的消息分发 Coroutine 永远不会命中断点。
local skynet_core = require "skynet.core"
local function getenv(name)
    return skynet_core.command("GETENV", name)
end

local target = assert(getenv("luapanda_service"), "missing luapanda_service")
if SERVICE_NAME ~= target then
    return
end

local host = assert(getenv("luapanda_host"), "missing luapanda_host")
local port = assert(tonumber(getenv("luapanda_port")), "invalid luapanda_port")

-- 使用 LuaPanda 官方入口，不封装第二套调试协议。useCHook=false 时由 Lua Debug Hook
-- 工作，避免加载 LuaPanda 为其他 Lua ABI 预编译的 libpdebug.so。
require("LuaPanda").start(host, port)

-- LuaPanda 完成 Coroutine 包装后才能加载 skynet.lua，确保其缓存的是包装后的函数。
local skynet = require "skynet"
skynet.error(string.format(
    "[LuaPanda] target=%s service=%s address=%s adapter=%s:%d coroutine_hook=ready",
    target,
    SERVICE_NAME,
    skynet.address(skynet.self()),
    host,
    port
))
