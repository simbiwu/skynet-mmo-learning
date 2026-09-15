-- Publishes static game configuration using Skynet sharedata.
local skynet = require "skynet"
local sharedata = require "skynet.sharedata"
local game_data = require "config.game_data"

skynet.start(function()
    sharedata.new("game_config", game_data)
    skynet.error("[ConfigService] sharedata 'game_config' published")

    -- Keep this service alive. Future lessons can add validated hot reload here.
end)
