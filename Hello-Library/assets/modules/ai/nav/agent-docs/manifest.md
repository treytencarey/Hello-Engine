---
depends_on: []
conflicts_with: []
exposes: [ai/nav, ai/nav/region, ai/nav/link, ai/nav/path, ai/nav/graph]
---

# ai/nav

Navigation for the agents that carry it. It builds a graph of what is walkable from the regions and links any level source publishes, and holds it in a resource. Search runs over regions, never over world cells: a map with 400 rooms searches 400 nodes however large they are. Server only; nothing syncs.

Not yet here: answering path requests. The search itself is in `shared/graph.lua`, with its suite.

## Components

- `ai/nav = { capabilities = { <capability> = true, ... } }`, on each agent. A link that needs a capability the agent lacks is closed to it. `capabilities` defaults to none.
- `ai/nav/region = { min_x, max_x, min_z, max_z, y, cost }`, on any entity: a walkable XZ box, added by a level source (`ai/nav/volumes`, or by hand). `y` defaults to 0 and `cost` to 1. A region with a side missing is left out until it has one.
- `ai/nav/link = { from, to, x, y, z, cost, kind, capability, behavior, one_way }`, on any entity: a way between two regions that do not touch (a door, a vent, a jump). `from` and `to` are region entities. Only those two are required: the crossing defaults to between the regions' centres, and `cost` to the distance between them. It runs both ways unless `one_way`. While an end is gone it is no edge.
- `ai/nav/path = { solved_id, status, path = { { x, y, z, kind, behavior }, ... }, regions = { <region entity>, ... } }`: an agent's route; `status` is `"ready"` or `"unreachable"`, and `solved_id` changes with each new path. `ai/steering` walks it. Replaced whole, never patched: a patch would leave the old route's trailing waypoints. It goes with `ai/nav`, by `mod_registry`.

## Resources

- `ai/nav/graph = { regions, edges }`, there once a region is: `regions` is a list of `{ entity, min_x, max_x, min_z, max_z, y, cost, center = { x, y, z } }`, and `edges[<region index>]` lists that region's `{ to = <region index>, cost, x, y, z, kind, capability, behavior }`. Nothing keeps it current once the mod has unloaded with its last agent, and the next agent builds it again.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/nav/init` | On an added `ai/nav`, fill in `capabilities` |
| First | `ai/nav/index` | When a region or link is added, changed or removed, build the graph again, which makes the resource the first time. Its first run sees every existing one as changed, so regions older than the mod count |

## Use

```lua
-- on the server: what is walkable
commands:spawn({ ["ai/nav/region"] = { min_x = -10, max_x = 10, min_z = -10, max_z = 10 } })

-- on an agent
commands:entity(agent):patch({ ["ai/nav"] = { capabilities = { walk = true } } })
```

## Notes

- Regions whose boxes come within 0.35 m are joined, at a corner too. That distance is fixed in `shared/graph.lua`: the graph is the world's, and `ai/nav` sits on each agent.
- A rebuild costs the square of the regions, and happens only when the level changes.
