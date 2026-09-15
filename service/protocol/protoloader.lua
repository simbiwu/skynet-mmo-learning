-- Loads Sproto schemas once and stores them in shared sprotoloader slots.
local skynet = require "skynet"
local sprotoparser = require "sprotoparser"
local sprotoloader = require "sprotoloader"
local schema = require "protocol.schema"

skynet.start(function()
    local c2s = sprotoparser.parse(schema.c2s)
    local s2c = sprotoparser.parse(schema.s2c)

    -- Slot 1: Client -> Server protocol.
    -- Slot 2: Server -> Client protocol.
    sprotoloader.save(c2s, 1)
    sprotoloader.save(s2c, 2)

    skynet.error("[ProtocolLoader] c2s/s2c schemas loaded into slots 1/2")

    -- Do not skynet.exit() here. sprotoloader slots depend on the owning service
    -- keeping the compiled sproto objects alive.
end)
