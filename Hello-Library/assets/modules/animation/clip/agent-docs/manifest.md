---
depends_on: []
conflicts_with: []
exposes: [animation/clip, animation/clip/graph]
---

# animation/clip

Clips playing on a node: the base every skeletal animation plays through. A node carrying `animation/clip` plays its clips on the AnimationPlayer at that node or under it (Bevy's glTF loader puts the player on the animation's root node), each at its weight, all at one speed. `animation` writes it on a character's model; a map can give it to a node in Blender, as a custom property, for an animation of its own (a door). Client only: each client plays its own copy.

## Components

- `animation/clip = { clips, speed, repeat, seek_to }`, on a node. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `clips` | `{ [<clip>] = <weight>, ... }`, the clips playing at once and their weights | `{}` |
  | `speed` | 1 plays forward, -1 backward, 0 pauses; another value scales | 1 |
  | `repeat` | `true` loops; `false` holds the end it reaches | `false` |
  | `seek_to` | where a clip starts: seconds of the clip's own time, within its length, or `"end"` | none: a clip starts where it would |

  A clip is an asset path, `<file>#Animation<N>`. A clip named another way (the name of an animation in the node's own glTF) plays nothing yet: its resolution has one place to grow into, and the log says so once per clip.

  `seek_to` is a value that stays; nothing clears it. It applies when a clip starts (when the node first reaches its player, when a clip is newly in `clips`, and when the base starts a finished clip again), and to every playing clip whenever `seek_to` itself changes. A write that keeps it moves nothing. A place needs the clip's length, known once its file has loaded: until then the clip starts where it would, and goes to its place when the length arrives.

- `animation/clip/graph = { handle, nodes, seek_to }`: on the node, this client only, never synced. The node's AnimationGraph, the graph node playing each clip (`nodes = { [<clip>] = <index> }`), and the `seek_to` last applied to its playing clips.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| PostUpdate (client) | `animation/clip/graph` | On a changed `animation/clip` whose set of clips differs from the graph's: build the graph again, a node per clip, and give it to a player already linked, which stops what it played |
| PostUpdate (client), after the graph | `animation/clip/link` | On an added AnimationPlayer: give it the graph of the nearest node at or above it |
| PostUpdate (client), after the link | `animation/clip/play` | On a changed `animation/clip` or graph, or a player given its graph: each clip with a weight plays at it and at the speed; a clip that newly has a weight starts at `seek_to` or its start; a changed `seek_to` moves every playing clip; one at 0 stops |
| PostUpdate (client), after the play | `animation/clip/seek` | While a `seek_to` waits for a clip's length: each frame, every node whose `seek_to` is not applied yet is tried again |

## Use

```lua
-- a door that opens, and later closes, holding each end it reaches
commands:entity(door):insert({ ["animation/clip"] = { clips = { ["maps/room.glb#Animation2"] = 1 }, speed = 1 } })
commands:entity(door):insert({ ["animation/clip"] = { clips = { ["maps/room.glb#Animation2"] = 1 }, speed = -1 } })

-- two clips blended, looping
commands:entity(model):insert({ ["animation/clip"] = { clips = { [walk] = 0.7, [run] = 0.3 }, speed = 1.2, ["repeat"] = true } })
```

In Blender, on the node: the custom property `animation/clip` = `{"clips": {"maps/room.glb#Animation2": 1}, "speed": 0}`.

## Notes

- The graph is built for the set of clips a node names, so a node that fades between clips lists all of them, those silent at 0: a set that changes builds the graph again, and what the player played stops.
- A clip that newly has a weight starts at `seek_to`, or else from its start, which a negative speed holds; one that keeps a weight is not restarted. A backward clip starts from its end with `seek_to = "end"`.
- Bevy stops advancing a clip that does not repeat once it reaches an end. Turned the other way after that, or asked to repeat otherwise, the clip starts again at `seek_to`, or else from where it stands (its `seek_time`, within its length), in the new mode.
- A graph built again holds the files of its set anew: a file no handle held any more is loaded again, so its length can come a few frames after the clip starts.
- `animation/clip/graph` is written with `insert`: a patch would merge into the old `nodes`, and a clip taken out would stay listed.
- A player's `active_animations` reads back with one key for every entry, so a suite asks `AnimationPlayer:animation(index)` for each node.
- Suites: `tests/test_clip.lua` (headless, as no clip advances there: defaults, the graph and the player, weights and speeds, a clip stopped and one taken out, a backward start, a change of repeat, a clip that is not an asset path; `seek_to` on a new clip, a changed one, one within the length, a write that keeps it, `"end"` forward and backward, and a length that comes later) and `tests/test_clip_windowed.lua` (playing over time: forward to the end and held, back from the end after finishing, paused, back to the start and held, looping, and back from `seek_to = "end"`).
