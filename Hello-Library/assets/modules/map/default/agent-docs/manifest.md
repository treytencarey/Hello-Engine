---
depends_on: []
conflicts_with: []
exposes: [map/default, map/default/sun]
---

# map/default

A flat ground to stand on, lit by a sun, with a spawn point on it. The map entity itself becomes the ground: a fixed box whose top is at `size.y / 2`. A change to `map/default` rebuilds the box and relights the same sun. The server and every client build the body from the synced `map/default`, so only that component is synced; clients draw it and light it.

## Components

- `map/default = { size, color, sun }`: put on the map entity by the world's boot. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `size` | `{ x, y, z }`, the box in metres | `{ 100, 0.2, 100 }` |
  | `color` | `{ r, g, b }` | `{ 0.3, 0.5, 0.3 }` |
  | `sun` | the sunlight's illuminance, in lux | 10000 |

  Synced from the server.
- `map/default/sun`: on a client, a child of the map entity with the `DirectionalLight`, shining down at an angle.
- The spawn point: on both sides, a child of the map entity with `player/spawner/point = {}`, `Name = "map/default"` and a `Transform` on the centre of the box's top, where `player/spawner` puts players. A change of size moves it to the new top. It is found among the map's children by `player/spawner/point`.
- On both sides it adds `RigidBody3d = "Fixed"` and `Collider3d` to the map entity, and `Transform` if it has none, as Bevy places the spawn point only through a chain where every link has one; on a client also `Mesh3d` and `MeshMaterial3d<StandardMaterial>`. If `map/default` is removed from an entity that stays, each half removes what it added (`Transform` stays), the shared half despawns the spawn point, and the client despawns the sun.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (both) | `map/default/ground` | On a new or changed `map/default`: fill in missing fields (itself a change, so the box follows on the next run), or make the entity a fixed box of its size, with its collider |
| First (both) | `map/default/ground` | On a new or changed `map/default` with its size: give the map entity a `Transform` if it has none, and spawn the spawn point on the centre of the box's top, or move it there |
| First (both) | `map/default/removed` | When `map/default` is removed from an entity that stays, remove the body and despawn the spawn point |
| First (client), after `map/default/ground` | `map/default/draw` | On a new or changed `map/default`, draw the box's mesh and material, and spawn the sun or relight it |
| First (client) | `map/default/undraw` | When `map/default` is removed from an entity that stays, remove the mesh and material; the sun, marked `map/default/sun`, goes by `mod_registry` |

## Use

```lua
-- in a world's boot, on the server
commands:spawn({ ["map/default"] = { size = { x = 60, y = 0.2, z = 60 } }, ChildOf = boot:id() })
```

## Notes

- Ambient light is left to the engine's default. Bevy 0.17's `AmbientLight` component requires a `Camera`, so the old map's ambient-light entity was an extra camera nobody despawned; the world resource is not writable from Lua.
- This map declares no walkable nav volume (`ai/nav/volumes/box`) for AI agents.
- Suites: a server one (headless: physics, the spawn point and a player spawned on it) and a client one (windowed: a headless run has no `StandardMaterial` assets). The client suite keeps a second map so removing the first does not unload the mod.
