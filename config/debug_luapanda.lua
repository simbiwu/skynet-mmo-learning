-- LuaPanda 专用开发配置。先复用正常配置，再只增加调试器所需路径和 Preload。
-- 正常运行和自动测试不会读取此文件，因此不会携带 Debug Hook 或 LuaSocket 开销。
include "game.lua"

preload = root .. "lualib/debug/luapanda_preload.lua"
lua_path = root .. "third_party/luapanda/Debugger/?.lua;"
    .. lua_path
lua_cpath = root .. "third_party/luapanda-runtime/luaclib/?.so;" .. lua_cpath

-- run_luapanda_server.sh 在启动前设置这些环境变量。Skynet 配置加载器会展开 $NAME。
luapanda_service = "$LUAPANDA_SERVICE"
luapanda_host = "$LUAPANDA_HOST"
luapanda_port = "$LUAPANDA_PORT"
