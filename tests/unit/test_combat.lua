local combat = require "scene.combat"

assert(combat.distance_sq(0, 0, 3, 4) == 25)
assert(combat.in_range({x=0,y=0}, {x=3,y=4}, 5))
assert(not combat.in_range({x=0,y=0}, {x=3,y=4}, 4))
assert(combat.player_damage({level=10}) == 30)
assert(combat.player_damage({}) == 12)

print("PASS test_combat")
