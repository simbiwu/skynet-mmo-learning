-- TCP framing helper.
-- Skynet's gate service expects a 2-byte big-endian length prefix ("s2").
local socket = require "skynet.socket"

local M = {}

function M.pack(payload)
    assert(type(payload) == "string", "payload must be a string")
    assert(#payload <= 0xffff, "packet is larger than the 2-byte frame limit")
    return string.pack(">s2", payload)
end

function M.write(fd, payload)
    return socket.write(fd, M.pack(payload))
end

return M
