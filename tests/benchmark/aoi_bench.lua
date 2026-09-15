package.path = "./lualib/?.lua;" .. package.path
local Grid = require "scene.aoi_grid"

local entity_count = tonumber(arg[1]) or 10000
local query_count = tonumber(arg[2]) or 100000
local map_size = 4000
local grid = Grid.new(20)

math.randomseed(20260911)
local positions = {}
for i = 1, entity_count do
    local x = math.random(0, map_size)
    local y = math.random(0, map_size)
    positions[i] = {x=x, y=y}
    grid:insert(i, x, y)
end

local begin = os.clock()
local candidates = 0
for i = 1, query_count do
    local p = positions[((i - 1) % entity_count) + 1]
    local set = grid:query_3x3(p.x, p.y)
    for _ in pairs(set) do
        candidates = candidates + 1
    end
end
local elapsed = os.clock() - begin

print(string.format("AOI_BENCH entities=%d queries=%d elapsed=%.3fs qps=%.0f avg_candidates=%.2f cells=%d",
    entity_count, query_count, elapsed, query_count / math.max(elapsed, 0.000001),
    candidates / query_count, grid:count_cells()))
