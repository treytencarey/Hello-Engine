---
depends_on: [ai/spawner, ai/archetype/backrooms_wanderer/spawner, ai/nav, ai/perception, ai/noisemaker, ai/debug, ai/debug/world, map/default]
conflicts_with: []
exposes: [ai/demo, ai/demo/region, ai/demo/spawner, ai/demo/decoy, ai/demo/decoys]
---

# ai/demo

A scene that proves the agents work, on `map/default`: a spawner of wanderers, and if asked, a ring of regions around an unwalkable centre, so a working path has to go around, and a decoy circling for them to chase. Server only.

## Components

- `ai/demo = { ... }`, on any entity. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `count` | wanderers | 2 |
  | `radius` | metres from the centre they start | 16 |
  | `regions` | true for the ring | false |
  | `decoy` | true for the decoy | false |
  | `decoy_radius` | metres from the centre it circles | 12 |
  | `decoy_speed` | metres per second, below a chasing wanderer's | 3.5 |
  | `debug` | true to draw what the wanderers think, and the ground | false |

- `ai/demo/region`: a region of the ring's box, on a child. `ai/nav/region` is made from it, again when `ai/nav` arrives.
- `ai/demo/spawner = { debug }`: on the spawner, a child.
- `ai/demo/decoy = { entity = <its demo>, angle, radius, speed }`, on the decoy: a relationship with target `ai/demo/decoys`, `linked_spawn = true`.
- `ai/demo/decoys`: a demo's decoys, kept by the engine.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/demo/build` | On an added `ai/demo`, builds what it asks for, unless a reload finds it built |
| First | `ai/demo/debug` | A wanderer of its spawner is drawn, if the demo said so |
| First | `ai/demo/removed` | When it is removed from an entity that stays, its decoys and `ai/debug/world` go; its marked children go by `mod_registry`, and the spawner takes its wanderers |
| Update | `ai/demo/decoy` | Polls: the decoy circles |

## Use

```lua
commands:spawn({ ["map/default"] = {}, ["core/net/sync"] = false })
commands:spawn({ ["ai/demo"] = { regions = true, decoy = true, debug = true } })
```

## Notes

- The ring describes `map/default`'s ground and nothing else. On another map leave `regions` off, as regions that don't match the ground send agents the wrong way.
- The decoy has no body and nothing draws it: it is only somewhere to look and something to hear.
- With `debug`, `ai/debug/world` goes on the demo's own entity, so that entity has to cross to clients for the ground to be drawn.
