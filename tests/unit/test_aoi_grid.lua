local Grid = require "scene.aoi_grid"

local function count(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end

local g = Grid.new(20)
g:insert("a", 0, 0)
g:insert("b", 19, 0)
g:insert("c", 40, 0)

local q = g:query_3x3(0, 0)
assert(q.a and q.b, "same/neighbor cell entities must be returned")
assert(not q.c, "cell two steps away must not be returned by 3x3 query")
assert(count(q) == 2)

assert(g:move("c", 20, 0) == true)
q = g:query_3x3(0, 0)
assert(q.c, "moved entity in neighbor cell must be visible to candidate query")

assert(g:move("a", 1, 1) == false, "move inside same cell should not relink cells")
assert(g:remove("b") == true)
assert(g:remove("b") == false)

print("PASS test_aoi_grid")
