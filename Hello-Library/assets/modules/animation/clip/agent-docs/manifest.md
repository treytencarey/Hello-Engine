---
depends_on: []
conflicts_with: []
exposes: [animation/clip, animation/clip/seek, animation/clip/node, animation/clip/graph]
---

# animation/clip

Clips playing on a node: the base every skeletal animation plays through. A node carrying `animation/clip` plays its clips on the AnimationPlayer at that node or under it (Bevy's glTF loader puts the player on the animation's root node), each at its weight, all at one speed. `animation` writes it on a character's model, client-local; a map gives it to a node in Blender, as a custom property; a mod can give it to an entity it replicates. The server drives what it holds: it publishes where each animated scene node stands, and each client plays its own copy from that. Client, server and shared halves.

## Components

- `animation/clip = { clips, speed, repeat }`, on a node. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `clips` | `{ [<clip>] = <weight>, ... }`, the clips playing at once and their weights | `{}` |
  | `speed` | 1 plays forward, -1 backward, 0 pauses; another value scales | 1 |
  | `repeat` | `true` loops; `false` holds the end it reaches | `false` |

  A clip is an asset path, `<file>#Animation<N>`. A clip named another way (the name of an animation in the node's own glTF) plays nothing yet: its resolution has one place to grow into, and the log says so once per clip.

- `animation/clip/seek = { to }`, on the node: where its clips stand, in seconds of clip time (within a clip's length) or `"end"`. On a client, every playing clip moves to it on its own added or changed edge, and a clip starting (newly weighted, first reaching the player, or a finished one started again) starts there. A write to `animation/clip` alone never seeks. A place needs the clip's length, known once its file has loaded: until then the clip starts where it would, and the seek is written again each frame, so its own edge tries it, until the length arrives.
- `animation/clip/node = { name, speed, time }`: the server's record of an animated scene node, one per node on the server, keyed by the node's `Name`. Spawned by the server half with `core/net/sync = { ["animation/clip/node"] = { authority = "server" } }` and `["core/script/owner"] = false`, so every client gets it and it outlives a reload; it goes when no node of that name stands on the server any more. Written when the node's speed changes and every half second while it moves. Each client copies `speed` onto its own copy of the node's `animation/clip`, and `time` into its `animation/clip/seek`, when the record arrives or changes, and when the node arrives after it. A client never runs a clock.
- `animation/clip/graph = { handle, nodes }`: on the node, this client only, never synced. The node's AnimationGraph, and the graph node playing each clip (`nodes = { [<clip>] = <index> }`).

A replicated entity (one a mod spawns on the server with a `core/net/sync` table) carries `animation/clip` and `animation/clip/seek` in that table, as the spawning mod declares; this mod declares no sync of its own, and no record is made for it.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| PostUpdate (client) | `animation/clip/graph` | On a changed `animation/clip` whose set of clips differs from the graph's: build the graph again, a node per clip, and give it to a player already linked, which stops what it played |
| PostUpdate (client), after the graph | `animation/clip/link` | On an added AnimationPlayer: give it the graph of the nearest node at or above it |
| PostUpdate (client), after the link | `animation/clip/play` | On a changed `animation/clip` or graph, or a player given its graph: each clip with a weight plays at it and at the speed; a clip that newly has a weight starts at the seek or its start; one at 0 stops. On `animation/clip/seek` added or changed: every playing clip moves to it |
| First (client) | `animation/clip/node` | On a record added or changed, or a named node with `animation/clip` added: the record's speed and time onto the node of its name |
| First (server) | `animation/clip/node` | On an animated scene node added (named, not replicated): its record, from where it stands; on one gone, a record no node's name holds goes |
| Update (server) | `animation/clip/publish` | While a node moves, or one's clip changed: a record is written when its node's speed changes, and on each half-second beat while it moves, with where the node stands |

## Use

```lua
-- a door that opens, and later closes, holding each end it reaches
commands:entity(door):insert({ ["animation/clip"] = { clips = { ["maps/room.glb#Animation2"] = 1 }, speed = 1 } })
commands:entity(door):insert({ ["animation/clip"] = { clips = { ["maps/room.glb#Animation2"] = 1 }, speed = -1 } })

-- where it stands, from its end
commands:entity(door):insert({ ["animation/clip/seek"] = { to = "end" } })

-- two clips blended, looping
commands:entity(model):insert({ ["animation/clip"] = { clips = { [walk] = 0.7, [run] = 0.3 }, speed = 1.2, ["repeat"] = true } })
```

## Authoring in Blender

- Give the node a custom property `animation/clip`, a JSON string: `{"clips": {"maps/room.glb#Animation2": 1}, "speed": 0}`. Where it stands at first is a second one, `animation/clip/seek` = `{"to": "end"}`. Export with Custom Properties on.
- One animation root per group that moves on its own: an empty of its own, parent of the parts that group animates, carrying the property. One `animation/clip` drives one AnimationPlayer, the one at its node or under it.
- Node names are unique in a map: the server's record and each client's copy find the node by its `Name`.

## Notes

- The graph is built for the set of clips a node names, so a node that fades between clips lists all of them, those silent at 0: a set that changes builds the graph again, and what the player played stops.
- A clip that newly has a weight starts at the seek, or else from its start, which a negative speed holds; one that keeps a weight is not restarted. A backward clip starts from its end with `animation/clip/seek = { to = "end" }`.
- Bevy stops advancing a clip that does not repeat once it reaches an end. Turned the other way after that, or asked to repeat otherwise, the clip starts again at the seek, or else from where it stands (its `seek_time`, within its length), in the new mode.
- A graph built again holds the files of its set anew: a file no handle held any more is loaded again, so its length can come a few frames after the clip starts.
- Where a node stands on the server is read in one place in the server half (`position`). No clip advances in a headless app, so for now it is the node's `animation/clip/seek` as last written there; the published place follows it.
- Clients each play on their own clock between records, so they may differ a little.
- `animation/clip/graph` is written with `insert`: a patch would merge into the old `nodes`, and a clip taken out would stay listed.
- A player's `active_animations` reads back with one key for every entry, so a suite asks `AnimationPlayer:animation(index)` for each node.
- Suites, headless: `tests/test_clip.lua` (no clip advances there: defaults, the graph and the player, weights and speeds, a clip stopped and one taken out, a backward start, a change of repeat, a clip that is not an asset path; the seek on a new clip, a changed one, one within the length, a write to `animation/clip` alone, `"end"` forward and backward, and a length that comes later); `tests/test_clip_server.lua` (the record per scene node, nothing written standing still, about twice a second moving, a speed published at once, the place carried, a reload, a node gone); `tests/test_clip_node.lua` (a client copying the record onto its node, a change, a node arriving after its record, no clock on the client).
- Suite, windowed: `tests/test_clip_windowed.lua` (playing over time: forward to the end and held, back from the end after finishing, paused, back to the start and held, looping, and back from a seek to `"end"`).
