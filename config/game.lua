-- Skynet MMO Learning Project - development configuration.
-- Run from repository root: ./third_party/skynet/skynet config/game.lua

root = "./"
skynet_root = root .. "third_party/skynet/"

luaservice = root .. "service/?.lua;" .. skynet_root .. "service/?.lua"
lualoader = skynet_root .. "lualib/loader.lua"
lua_path = root .. "lualib/?.lua;" .. root .. "lualib/?/init.lua;" .. skynet_root .. "lualib/?.lua;" .. skynet_root .. "lualib/?/init.lua"
lua_cpath = skynet_root .. "luaclib/?.so"
cpath = skynet_root .. "cservice/?.so"

thread = 8
harbor = 0
bootstrap = "snlua bootstrap"
start = "main"
logger = nil
logpath = "."

-- Network
gate_host = "0.0.0.0"
gate_port = 8888
max_client = 10000
debug_console_port = 8000

-- Storage. Default is memory so a new learner can run immediately.
storage_driver = "memory"
storage_pool = 4

-- MySQL settings are used only when storage_driver = "mysql".
db_host = "127.0.0.1"
db_port = 3306
db_name = "mmo"
db_user = "mmo"
db_password = "123456"
