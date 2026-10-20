---
depends_on: []
conflicts_with: []
exposes: [animation, animation/action, animation/model, animation/graph, animation/player, animation/playing]
---

# animation

A character's skeletal animation: its model, and the clip it plays for what it is doing. The server states the model; each client draws it and picks the clip from what it sees its own copy doing. `player` gives every player one; an agent can be given one with its own model.

## Components

- `animation = { model, scene, clips, walk_speed, offset }`: on a character, synced from the server. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `model` | path prefix of the model's files | `"Placeholder-Character/Model"` |
  | `scene` | suffix of the file and label of the scene drawn | `"-Idle.glb#Scene0"` |
  | `clips` | `{ <state> = <suffix> }`, a clip per state | `idle`, `walk`, `jump`, `fall` from `-Idle.glb`, `-Walk.glb`, `-Jump.glb` |
  | `walk_speed` | metres per second at which `walk` plays at its own speed | 6 |
  | `offset` | `{ x, y, z }`, where the model sits under the character | `{ 0, -0.9, 0 }` |

- `animation/action = { state, speed }`: written by another mod that plays something on purpose (a cast, an emote). While it is there, it is played instead of the motion's state. It syncs as the mod that writes it declares.
- On each client, never synced:
  - `animation/model = { scene }`: a child of the character holding the model's scene, and the scene's path.
  - `animation/graph = { handle, nodes, clips }`: the character's AnimationGraph, a node per clip (`nodes`), and the path of the clip each state plays (`clips`).
  - `animation/player = { state, graph }`: on the AnimationPlayer the model's scene spawned, what it last started (empty until it starts one).
  - `animation/motion = { at }`: where the character was last frame.
  - `animation/playing = { state, speed }`: the clip it should play now.

  If `animation` is removed from an entity that stays, `mod_registry` takes these off and despawns the children.

## Systems

| Schedule | Label | Purpose |
|----------|-------|---------|
| First (both) | AnimationInit | On an added `animation`, fill in missing fields |
| First (client) | AnimationModel | On a changed `animation` whose fields are filled: spawn the model child with `SceneRoot = load_asset(scene)`, or replace it when the scene differs from the one it holds |
| First (client) | AnimationGraph | On a changed `animation`: build the graph from the clips' handles, or rebuild it when a clip's path changed or one was taken out, and give it to a player already linked |
| First (client), after `AnimationGraph` | AnimationLink | On an added AnimationPlayer, find its character (the nearest ancestor with a graph), give the player the graph and mark it `animation/player` |
| Update (client) | AnimationState | Polls: from the body's velocity when it has one, else its motion since last frame (or its `animation/action`), the state and speed to play |
| Update (client), after `AnimationState` | AnimationPlay | When a character's state, speed or graph changes, or a new player appears: a state or graph its player has not started crossfades into its clip from the start; the same one at a new speed only changes the running clip's speed |

## Use

```lua
-- on the server: a character drawn with the default model
spawn({ animation = {}, Transform = { translation = at } })

-- a cast, on whichever side decides it (synced as the writing mod declares)
e:patch({ ["animation/action"] = { state = "cast", speed = 1 } })
-- and when it ends
e:patch({ ["animation/action"] = null })
```

## Notes

- The motion is the body's velocity when the character has one (its own player: physics moves a body in fixed steps, so most frames show no movement), else how its Transform moved since last frame (another player, eased toward what arrives).
- The state comes from how the character moved on this client: rising faster than 1 m/s is `jump`, falling faster is `fall`, moving across faster than 0.1 m/s is `walk` (its speed scaled by `walk_speed`, between 0.3 and 2), else `idle`. Two clients can play different clips for one character for a moment, where their copies move differently.
- The scene and clips are handles from `load_asset`. Bevy refills them in place when a file changes or arrives, so a changed model or clip file respawns the scene and changes the clip on every character using it, and nothing here runs again.
- A change to `animation` replaces only what it names anew: a new scene replaces the model child, a changed or removed clip rebuilds the graph, and a change to anything else (`walk_speed`) touches neither.
- `animation/playing` is written whenever the speed changes, which for a character followed by its Transform is most frames; its clip is never restarted for it.
- A headless run has no AnimationPlugin, so the client half's suite runs windowed.
- A file still downloading gives a handle that fills in when it lands (core), so a character draws and plays once its files arrive, without a rebuild.
- `animation/graph` is written with `set`: a patch would merge into the old `nodes` and `clips`, and a clip taken out would stay listed.
- Not provable by the suite: that a rebuilt graph reaches a player already linked. A created asset's handle reads back as an opaque reflect value, so no suite can tell which graph a player holds; the line stays because without it the player keeps the old graph's clips.
- `vr/avatar` and `vr/calibration` read the old `model_entity_id` and break until their own turn.
