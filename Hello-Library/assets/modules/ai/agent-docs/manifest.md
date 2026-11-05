---
depends_on: []
conflicts_with: []
exposes: []
---

# ai

Agents that walk, look, listen and choose what to do, run on the server and shown to clients as ordinary bodies. `ai` itself is only this manifest: there is nothing to attach, and each mod below stands alone and is declared by what needs it. Each has its own manifest.

## Mods

| Mod | Side | What it does |
|-----|------|--------------|
| `ai/agent` | server | A memory, a clock it thinks by, and a choice among the options linked to it |
| `ai/perception` | server | What it sees and hears, written into its memory |
| `ai/nav` | server | The graph of what is walkable, and a path for what it is asked to go to |
| `ai/nav/volumes`, `/box`, `/scene` | server | Regions baked from volumes against the collision world |
| `ai/steering` | server | Walks the path by `Velocity3d` |
| `ai/noisemaker` | server | Makes noise when its entity moves, for whatever hears |
| `ai/behavior/chase` | server | Runs at what it has seen |
| `ai/behavior/investigate` | server | Walks to what it has heard and looks around |
| `ai/behavior/patrol` | server | Wanders around home when nothing else is worth doing |
| `ai/spawner` | server | Makes plain bodies and links them to itself |
| `ai/archetype/wanderer` | server | A creature: all of the above, each with its mod's defaults |
| `ai/archetype/wanderer/spawner` | server | A spawner whose bodies become that creature |
| `ai/demo` | server | A scene that proves it all works, on `map/default` |
| `ai/debug` | both | Draws what an agent thinks |
| `ai/debug/world` | both | Draws the walkable ground |

## How they fit

- A behaviour is a mod with no `base`, on the agent. For each agent it spawns an option entity linked by `ai/agent/option` and keeps its `score` current. `ai/agent` puts `ai/agent/chosen` on the highest. It names no behaviour, and a new behaviour needs no change anywhere else.
- A behaviour enters on `added` and leaves on `removed` of `ai/agent/chosen` beside its own marker, or looks at each thought while its option is chosen.
- While chosen, a behaviour writes its own key in `ai/nav/request`. `ai/nav` answers with `ai/nav/path`, `ai/steering` walks it, and the behaviour reads how that went. Not chosen any more, it removes its key.
- `ai/agent/memory` holds `seen` and `sound`, each with one writer: `ai/perception`. Behaviours only read it.
- An archetype has `ai/agent` as its `base`, declares the rest on each mod's own component, and removes what it adds. A creature built on one (`base = "ai/archetype/wanderer"`) sets its numbers as carrier defaults, which reach only its own bodies.
- A client sees an agent as `animation` and `movement` on a body whose collider and type came from the server. `movement` makes any copy that isn't local kinematic. Nothing else of an agent crosses, except `ai/debug` if it is put on one.

## Use

```lua
-- a pack of wanderers around the middle of the map
commands:spawn({
    ["ai/spawner"] = { count = 3, radius = 12 },
    ["ai/archetype/wanderer/spawner"] = {},
    ["core/net/sync"] = false,
})

-- what they should notice: `player` adds both of these itself
commands:entity(barrel):patch({ ["ai/perception/target"] = {}, ["ai/noisemaker"] = {} })
```

## Notes

- A scene gets its walkable ground from `ai/nav/volumes/box`, `ai/nav/volumes/scene` or `ai/nav/region`s by hand. With none, an agent walks in straight lines.
