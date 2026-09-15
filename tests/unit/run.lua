package.path = "./lualib/?.lua;./tests/unit/?.lua;" .. package.path

dofile("tests/unit/test_aoi_grid.lua")
dofile("tests/unit/test_combat.lua")
dofile("tests/unit/test_movement.lua")
print("UNIT_TESTS_OK")
