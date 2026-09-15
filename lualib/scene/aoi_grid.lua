-- Grid-based AOI index.
--
-- Important design choice:
--   grid_size >= view_radius
-- Therefore a 3x3 neighborhood is sufficient to find every entity that may be
-- within view radius. We still perform an exact distance check in scene.lua.
--
-- This module stores spatial membership only. Entity data remains owned by Scene.
local Grid = {}
Grid.__index = Grid

local function cell_key(gx, gy)
    return gx .. ":" .. gy
end

function Grid.new(grid_size)
    assert(grid_size and grid_size > 0, "grid_size must be > 0")
    return setmetatable({
        grid_size = grid_size,
        cells = {},       -- "gx:gy" -> { [entity_key] = true }
        entity_cell = {}, -- entity_key -> "gx:gy"
    }, Grid)
end

function Grid:coords(x, y)
    return math.floor(x / self.grid_size), math.floor(y / self.grid_size)
end

function Grid:insert(entity_key, x, y)
    assert(self.entity_cell[entity_key] == nil, "entity already exists in AOI grid: " .. tostring(entity_key))
    local gx, gy = self:coords(x, y)
    local key = cell_key(gx, gy)
    local cell = self.cells[key]
    if not cell then
        cell = {}
        self.cells[key] = cell
    end
    cell[entity_key] = true
    self.entity_cell[entity_key] = key
end

function Grid:remove(entity_key)
    local key = self.entity_cell[entity_key]
    if not key then
        return false
    end
    local cell = self.cells[key]
    if cell then
        cell[entity_key] = nil
        if next(cell) == nil then
            self.cells[key] = nil
        end
    end
    self.entity_cell[entity_key] = nil
    return true
end

function Grid:move(entity_key, x, y)
    local old_key = assert(self.entity_cell[entity_key], "entity is not in AOI grid: " .. tostring(entity_key))
    local gx, gy = self:coords(x, y)
    local new_key = cell_key(gx, gy)
    if old_key == new_key then
        return false
    end

    local old_cell = self.cells[old_key]
    old_cell[entity_key] = nil
    if next(old_cell) == nil then
        self.cells[old_key] = nil
    end

    local new_cell = self.cells[new_key]
    if not new_cell then
        new_cell = {}
        self.cells[new_key] = new_cell
    end
    new_cell[entity_key] = true
    self.entity_cell[entity_key] = new_key
    return true
end

function Grid:query_3x3(x, y)
    local gx, gy = self:coords(x, y)
    local result = {}
    for dx = -1, 1 do
        for dy = -1, 1 do
            local cell = self.cells[cell_key(gx + dx, gy + dy)]
            if cell then
                for entity_key in pairs(cell) do
                    result[entity_key] = true
                end
            end
        end
    end
    return result
end

function Grid:count_cells()
    local n = 0
    for _ in pairs(self.cells) do
        n = n + 1
    end
    return n
end

return Grid
