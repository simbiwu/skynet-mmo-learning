# 05 - Scene, AOI and Combat

## Grid choice

Scene 1 uses:

```text
grid_size   = 20
view_radius = 18
```

Because `grid_size >= view_radius`, every entity within true view radius must be in the current cell or one of its eight neighbors. `aoi_grid.lua` therefore returns a 3x3 candidate set and `scene.lua` performs an exact squared-distance filter.

This distinction matters:

- Grid query is a spatial coarse filter.
- Visibility radius is the gameplay rule.

Do not equate "same 3x3 cells" with "definitely visible" unless your game intentionally defines visibility that way.

## Complexity intuition

Without AOI, one movement can scan all N scene entities: O(N).

With a reasonably distributed grid, movement examines only entities in 9 cells. Let average candidates be K; typical work is approximately O(K), where K is driven by local density instead of total scene population.

Worst case still degrades: if every entity stands inside one cell, K becomes N. AOI is not magic; it exploits spatial distribution.

## Visibility sets

`visible[player_id]` records the entities currently visible to that player. After movement:

```text
old_visible - new_visible -> entity_leave
new_visible - old_visible -> entity_enter
intersection              -> movement update to relevant observers
```

## 服务端权威移动

更新 Grid 之前，`Scene` 先验证目标点处于地图边界内，并按时间补充/消费玩家的移动额度。失败请求不会修改 Grid、`visible` 或实体坐标。这样 AOI 处理的输入始终是服务器已经接受的权威位置，而不是客户端自行声明的位置。完整算法见 `docs/15_P0_AUTHORITATIVE_MOVEMENT.md`。

Player-player visibility is kept symmetric. Monster visibility is maintained in each player's set because monsters do not need a client-facing visible set of their own.

## Combat ownership

PlayerAgent requests an attack, but Scene owns the target monster and positions. Therefore Scene performs:

- attacker existence check
- target existence check
- distance/range check
- damage application
- HP AOI broadcast
- death removal
- respawn timer

PlayerAgent should not subtract monster HP locally and then tell Scene the result. That would split authoritative combat state.

## Current simplifications

- deterministic damage
- no attack cooldown
- no skill system
- no monster AI/path finding
- no aggro/threat
- no PvP
- no loot ownership
- same monster runtime id reused after respawn

These are deliberate lesson boundaries, documented in `13_PRODUCTION_GAPS.md`.
