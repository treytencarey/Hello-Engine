---
depends_on: [animation/clip]
conflicts_with: []
exposes: [animation, animation/action, animation/model, animation/playing]
---

# animation

A character's skeletal animation: its model, and the clip it plays for what it is doing. The server states the model; each client draws it and picks the clip from what it sees its own copy doing, and plays it through `animation/clip` on the model. `player` gives every player one; an agent can be given one with its own model. With no `model` set, a character has no mesh: nothing is drawn or played.

## Components

- `animation = { model, scene, clips, walk_speed, offset }`: on a character, synced from the server. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `model` | path prefix of the model's files | none: no model is drawn and no clip plays |
  | `scene` | suffix of the file and label of the scene drawn | `"-Idle.glb#Scene0"` |
  | `clips` | `{ <state> = <suffix> }`, a clip per state | `idle`, `walk`, `jump`, `fall` from `-Idle.glb`, `-Walk.glb`, `-Jump.glb` |
  | `walk_speed` | metres per second at which `walk` plays at its own speed | 6 |
  | `offset` | `{ x, y, z }`, where the model sits under the character | `{ 0, -0.9, 0 }` |

  A world gives its characters a model through carrier defaults on its player mod (`defaults = { animation = { model = "modules/<mod>/assets/Model" } }`), with `Model-Idle.glb`, `Model-Walk.glb` and `Model-Jump.glb` beside that prefix.

- `animation/action = { state, speed }`: written by another mod that plays something on purpose (a cast, an emote). While it is there, it is played instead of the motion's state. It syncs as the mod that writes it declares.
- On each client, never synced:
  - `animation/model = { scene }`: a child of the character holding the model's scene, and the scene's path. It carries `animation/clip`: every clip file the character's states name, each at its weight, those silent at 0, looping, at the state's speed. `animation/clip` builds the model's graph and plays it on the AnimationPlayer the scene spawned.
  - `animation/motion = { at }`: where the character was last frame.
  - `animation/playing = { state, speed }`: the clip it should play now.

  If `animation` is removed from an entity that stays, `mod_registry` takes these off and despawns the children.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (client) | `animation/model` | On a changed `animation` whose fields are filled: spawn the model child with `SceneRoot = asset_server:load(scene)` and an empty `animation/clip`, or replace it when the scene differs from the one it holds |
| Update (client) | `animation/state` | Polls a character with a model: from the body's velocity while that says it moves, else its motion since last frame (or its `animation/action`), the state and speed to play |
| Update (client), after `animation/state` | `animation/play` | Polls: each clip's weight on the model moves toward its target (1 for the state's clip, or idle's for a state with none, 0 for the rest) at 5 a second, so a change of state fades over 0.2 s; the first state starts at its weight. A model at its targets and speed is not written |

## Use

```lua
-- on the server: a character drawn with a model the world ships
commands:spawn({ animation = { model = "modules/my_world/assets/Model" }, Transform = { translation = at } })

-- a cast, on whichever side decides it (synced as the writing mod declares)
commands:entity(character):patch({ ["animation/action"] = { state = "cast", speed = 1 } })
-- and when it ends
commands:entity(character):patch({ ["animation/action"] = null })
```

## Notes

- The motion is the body's velocity while that says it moves (physics moves a body in fixed steps, so most frames show no movement), else how its Transform moved since last frame. Another player's copy is a kinematic body eased toward what arrives, and Rapier writes its velocity as still on a frame holding two steps, as its Transform moved only before the first; read from its velocity alone, it flickered between `walk` and `idle`, and each flip restarted the clip.
- The state comes from how the character moved on this client: rising faster than 1 m/s is `jump`, falling faster is `fall`, moving across faster than 0.1 m/s is `walk` (its speed scaled by `walk_speed`, between 0.3 and 2), else `idle`. Two clients can play different clips for one character for a moment, where their copies move differently.
- The scene and clips are asset handles (`asset_server:load`). Bevy refills them in place when a file changes or arrives, so a changed model or clip file respawns the scene and changes the clip on every character using it, and nothing here runs again.
- A change to `animation` replaces only what it names anew: a new scene replaces the model child, a changed or removed clip rebuilds the graph, and a change to anything else (`walk_speed`) touches neither.
- `animation/playing` is written whenever the speed changes, which for a character followed by its Transform is most frames; its clip is never restarted for it.
- A clip fading out that is wanted again is not restarted: `animation/clip` restarts only a clip whose weight came back from 0. The model lists every clip file at all times, so its graph is built once for its set of files.
- No clip advances in a headless run: `test_animation_client.lua` runs windowed. `test_animation_state.lua` (the state picked for bodies whose velocity reads still, and a character with no model) and `test_animation_play.lua` (what the character writes on its model: every clip, the fade, the speed, and no write at rest) run headless. All draw a fixture model in `tests/fixtures`: an animated node under an `Armature`, with no mesh.
- A file still downloading gives a handle that fills in when it lands (core), so a character draws and plays once its files arrive, without a rebuild.
- Not done yet: `vr/avatar` and `vr/calibration`, which use a character's model, are not in this library yet.
