-- Development authentication service.
-- Production replacement: LoginServer/Center issues a one-time token; GameServer
-- verifies and consumes it, usually through Center/Redis rather than trusting client identity.
local skynet = require "skynet"

local CMD = {}

function CMD.verify(player_id, token)
    local expected = "dev:" .. tostring(player_id)
    return token == expected
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, command, ...)
        local fn = assert(CMD[command], "unknown auth command: " .. tostring(command))
        local result = { fn(...) }
        if session ~= 0 then
            skynet.retpack(table.unpack(result))
        end
    end)
end)
