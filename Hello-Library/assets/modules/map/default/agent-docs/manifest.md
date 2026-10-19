---
depends_on: []
conflicts_with: []
exposes: [map/default, map/default/sun]
---

# map/default

A flat ground to stand on, lit by a sun. The map entity itself becomes the ground: a fixed box whose top is at `size.y / 2`. A change to `map/default` rebuilds the box and relights the same sun. The server and every client build the body from the synced `map/default`, so only that component is synced; clients draw it and light it.

## Components

- `map/default = { size, color, sun }`: put on the map entity by the world's boot. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `size` | `{ x, y, z }`, the box in metres | `{ 100, 0.2, 100 }` |
  | `color` | `{ r, g, b }` | `{ 0.3, 0.5, 0.3 }` |
  | `sun` | the sunlight's illuminance, in lux | 10000 |

  Synced from the server.
- `map/default/sun`: on a client, a child of the map entity with the `DirectionalLight`, shining down at an angle.
- On both sides it adds `RigidBody3d = "Fixed"` and `Collider3d` to the map entity; on a client also `Mesh3d` and `MeshMaterial3d`. If `map/default` is removed from an entity that stays, each half removes what it added, and the client despawns the sun.

## Systems

| Schedule | Label | Purpose |
|----------|-------|---------|
| First (both) | MapGround | On a new or changed `map/default`: fill in missing fields (itself a change, so the box follows on the next run), or make the entity a fixed box of its size, with its collider |
| First (both) | MapRemoved | When `map/default` is removed from an entity that stays, remove the body |
| First (client), after `MapGround` | MapDraw | On a new or changed `map/default`, draw the box's mesh and material, and spawn the sun or relight it |
| First (client) | MapUndraw | When `map/default` is removed from an entity that stays, remove the mesh and material; the sun, marked `map/default/sun`, goes by `mod_registry` |

## Use

```lua
-- in a world's boot, on the server
spawn({ ["map/default"] = { size = { x = 60, y = 0.2, z = 60 } } }):with_parent(boot:id())
```

## Notes

- Ambient light is left to the engine's default. Bevy 0.17's `AmbientLight` component requires a `Camera`, so the old map's ambient-light entity was an extra camera nobody despawned; the world resource is not writable from Lua.
- The old map also declared a walkable nav volume (`ai/nav/volumes/box`) for AI agents; that waits for the rewritten `ai/nav`.
- Suites: a server one (headless: physics only) and a client one (windowed: a headless run has no `StandardMaterial` assets). The client suite keeps a second map so removing the first does not unload the mod.
