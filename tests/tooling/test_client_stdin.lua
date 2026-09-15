-- 回归保护：client.socket 的 C 模块拥有 stdin Reader，Lua 侧不能再用 io.read 竞争 TTY。
local file = assert(io.open("client/test_client.lua", "rb"))
local source = assert(file:read("*a"))
file:close()

assert(source:find("socket.readstdin()", 1, true),
    "interactive client must consume client.socket's stdin queue")
assert(not source:find('io.read("*l")', 1, true),
    "io.read competes with client.socket's stdin pthread")

print("CLIENT_STDIN_OWNER_OK")
