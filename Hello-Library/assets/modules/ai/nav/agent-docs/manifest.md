---
depends_on: []
conflicts_with: []
exposes: [ai/nav, ai/nav/request, ai/nav/path, ai/nav/serving, ai/nav/search, ai/nav/region, ai/nav/link, ai/nav/graph]
---

# ai/nav

Navigation for the agents that carry it. It builds a graph of what is walkable from the regions and links any level source publishes, holds it in a resource, and answers each agent's request with a path, which `ai/steering` walks. Search runs over regions, never over world cells: a map with 400 rooms searches 400 nodes however large they are. Server only; nothing syncs.

## Components

- `ai/nav = { capabilities = { <capability> = true, ... } }`, on each agent. A link that needs a capability the agent lacks is closed to it. `capabilities` defaults to none.
- `ai/nav/region = { min_x, max_x, min_z, max_z, y, min_y, max_y, cost }`, on any entity: a walkable XZ box, added by a level source (`ai/nav/volumes`, or by hand). `y` defaults to 0 and `cost` to 1, and `min_y` and `max_y`, the heights it spans, to `y`. A region with a side missing is left out until it has one.
- `ai/nav/link = { from = { x, y, z }, to = { x, y, z }, x, y, z, cost, kind, capability, behavior, one_way }`, on any entity: a way between two regions that do not touch (a door, a vent, a jump). `from` and `to` are positions, each resolved to the floor there, or within 8 m, whenever the graph is built, so a level that respawns its regions keeps its links. Only those two are required: the crossing `x`, `y`, `z` defaults to between them on the ground, at the higher region's height, and `cost` to the distance between the regions' centres. It runs both ways unless `one_way`. An end no region is near makes no edge, with one warning in the log for each such position, ever: a link that lands before its regions warns once, then works.
- `ai/nav/request = { <asker> = { to = { x, y, z } }, ... }`: what the agent is asked to go to. `ai/nav` adds it empty when it sets up, and it goes with `ai/nav`, by `mod_registry`; nothing else adds or removes the component. An asker waits for it to be there, then writes and removes only its own key, so askers need no order between them. An entry with no `to` is not served.
- `ai/nav/path = { solved_id, status, path = { { x, y, z, kind, behavior }, ... }, regions = { <region index>, ... } }`: the answer to the entry being served. `status` is `"ready"` or `"unreachable"`, an unreachable path being empty. `solved_id` is `Time`'s elapsed seconds when it was answered, so it changes with each new path and never repeats. `regions` indexes `ai/nav/graph` as it was then, and is empty for a straight walk. Replaced whole, never patched: a patch would leave the old route's trailing waypoints. It goes when the entry it answers goes, and with `ai/nav`.
- `ai/nav/serving = { key, to, entries, answered }`: the entry being served, the entries as last seen, and the entry the path answers. On while there is an entry.
- `ai/nav/search = { job }`: on while an answer is owed, `job` being the search once it has started.

## Resources

- `ai/nav/graph = { regions, edges, warned }`: `regions` is a list of `{ min_x, max_x, min_z, max_z, y, min_y, max_y, cost, center = <a Vec2 on the ground, its y the world z>, island = <the same for regions edges join> }`, `edges[<region index>]` lists that region's `{ to = <region index>, cost, x, y, z, kind, capability, behavior }`, and `warned` the link ends already warned about. Nothing keeps it current once the mod has unloaded with its last agent, and the next agent builds it again.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/nav/init` | On an added `ai/nav`, add `ai/nav/request` and make the resource |
| First | `ai/nav/index` | Runs only when a region or link is added, changed or removed: build the graph again and owe every served entry a new answer. Its condition's first run sees every existing one as changed, so regions older than the mod count |
| PreUpdate | `ai/nav/serve` | On a changed `ai/nav/request`, choose the entry to serve: one that is new or goes somewhere new, else the one it is serving, else any, in key order. A new choice owes a search, the path goes with its entry, and no entries takes the path away |
| PreUpdate | `ai/nav/solve` | Polls while a search is owed: one search at a time, until `over_budget()`, and write each answer whole |

## Use

```lua
-- on the server: what is walkable
commands:spawn({ ["ai/nav/region"] = { min_x = -10, max_x = 10, min_z = -10, max_z = 10 } })

-- on an agent
commands:entity(agent):patch({ ["ai/nav"] = { capabilities = { walk = true } } })

-- ask, once `ai/nav/request` is there, and stop asking
commands:entity(agent):patch({ ["ai/nav/request"] = { chase = { to = { x = 4, y = 0, z = 9 } } } })
commands:entity(agent):patch({ ["ai/nav/request"] = { chase = null } })

-- a door between two rooms that do not touch
commands:spawn({ ["ai/nav/link"] = { from = { x = 9, y = 0, z = 0 }, to = { x = 12, y = 0, z = 0 }, kind = "door" } })
```

## Notes

- Regions whose boxes come within 0.35 m are joined when they share at least 0.5 m of border and their heights come within a 0.5 m step, so a corner alone is no way through, and neither is the storey overhead: author a link where one should be. The numbers are fixed in `server/graph.lua`: the graph is the world's, and `ai/nav` sits on each agent. A bake with a `max_step` over 0.5 would leave its ramp's rectangles apart.
- A point's region, an agent's or a goal's, is the floor over or under it at or just below its height, however near the floor above: it stands on the one below. Over no floor, it is the nearest within 8 m, measured in three dimensions, and for a goal only among the floors joined to the agent's own, whichever way a link runs: so a goal inside a block walks up to the block, rather than answering `"unreachable"` for the top of the ceiling above it. A goal over a floor nothing joins to the agent, a ceiling's top included, is still `"unreachable"`.
- A rebuild costs the square of the regions, and happens only when the level changes.
- The path is delivered in PreUpdate, so `ai/steering` in Update reads it with no ordering.
- The answer to a goal off the graph, more than 8 m from any region, is `"unreachable"`. An agent off the graph, or already in the goal's region, walks straight at the goal, as does every agent in a world with no regions at all.
- While the served entry moves to a new place the old path stays until the new one is answered, so the agent keeps walking. An entry that goes takes its path at once.
- Writing the same place again answers nothing new: to ask again, take the key out for a frame.
- A search stops when the system has spent its slice of the frame's budget, and carries on next frame, so more rooms take extra frames, never a longer frame. Searches go one at a time. When the slice is already spent, a run looks at two regions, the first poll of a run answering false, so a search over N regions can take N/2 frames after whatever is ahead of it: 400 regions is about 3.5 s at 60 frames a second.
- A changed `capabilities` applies to the next search, not to the path it has.
