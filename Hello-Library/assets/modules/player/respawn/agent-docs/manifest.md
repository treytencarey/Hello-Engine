---
depends_on: [player, player/spawner, sidebar/menu]
conflicts_with: []
exposes: [player/respawn, player/respawn/item]
---

# player/respawn

Respawn, an item in the sidebar's menu: a click stands the local player back on the spawn point it claims, at rest, with its camera turned the way the point faces. It has no key. It runs on the client, which drives its own player's Transform; the server's copy eases toward it as it does after any move (`player`).

## Components

- `player/respawn = {}` on the local player. `player/client` adds and removes it, so every world on the library's player has it; a game's own player adds it the same way, in its client half. Never synced.
- `player/respawn/item`: marks its `sidebar/menu/item` (`title = "Respawn"`, `order = 1`) in the menu's list.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| Update | `player/respawn` | On a new menu list or a new local carrier, spawn the item in each list holding none, with its click observer. A run condition over those edges skips it otherwise |

| Observer | Purpose |
|----------|---------|
| `Pointer<Click>` on the item | Find this side's `player/spawner/point` whose `Name` is `player.spawn_point`; set the player's `Transform.translation` to the point's place plus the body's height along the point's up, zero its `Velocity3d`, and set `camera.yaw` to the point's facing |

## Use

```lua
-- a game's player, in its client half, for its local player
commands:entity(player):insert_if_new({ ["player/respawn"] = {} })
```

## Notes

- The height is the capsule's, read from the player's own `Collider3d`: its centre stands `half_height + radius` above its feet, times the player's `Transform.scale.y`. For the spawner's `capsule_y = { radius = 0.4, half_height = 0.5 }` that is 0.9 m. A point sits on the floor, upright, so the body stands on it. A new player is placed `lift` above its point instead (`player/spawner`, 1 m by default), so it drops onto it.
- `Collider3d` reads back in rapier's own form: `unscaled = { Capsule = { segment = { a, b }, radius } }` is the shape as written, with the segment's ends as lists, and `raw` is the same shape at the entity's scale. A body whose collider is not a capsule is not moved.
- Each side has its own copy of the map's points, and the click finds this client's. No claim (no point was ready), or a claim naming no point here, does nothing.
- The body's rotation is locked, so the camera's yaw is what turns the player: it becomes the yaw of the point's rotation (Bevy's `YXZ` Euler order), as the spawner sets a new player's.
- The item goes with the menu's panel. A reload of this mod takes it and spawns a new one in the open list.
- Suites: `test_respawn.lua` runs headless, on a real player whose body is the spawner's capsule, dynamic, with no gravity, so where a click puts it is where it stays: real clicks on the menu's button and the item, a tilted point and one the claim does not name, twice the scale, no claim and a claim naming no point, and a reload.
