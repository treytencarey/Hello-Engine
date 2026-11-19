---
depends_on: [animation/clip]
conflicts_with: []
exposes: [animation, animation/action, animation/model, animation/playing]
---

# animation

A character's skeletal animation: its model, and the clip it plays for what it is doing. The server states the model; each client draws it and plays it through `animation/clip` on the model. What a character plays is worked out once, by the side that moves it, the one holding its Transform's authority: the owning client for a player, the server for a character no client owns. It crosses as `animation/playing`, as the Transform does, and every other copy plays it. Players and server-moved characters go the same way. `player` gives every player one; an agent can be given one with its own model. With no `model` set, a character has no mesh: nothing is drawn or played.

## Components

- `animation = { model, scene, clips, walk_speed, run_speed, offset }`: on a character, synced from the server. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `model` | path prefix of the model's files | none: no model is drawn and no clip plays |
  | `scene` | suffix of the file and label of the scene drawn | `"-Idle.glb#Scene0"` |
  | `clips` | `{ <state> = <suffix> }`, a clip per state, or for a state a set of directions (below) | `idle`, `walk`, `jump`, `fall` from `-Idle.glb`, `-Walk.glb`, `-Jump.glb` |
  | `walk_speed` | metres per second at which `walk` plays at its own speed | 6 |
  | `run_speed` | metres per second at which `run` plays at its own speed | 6 |
  | `offset` | `{ x, y, z }`, where the model sits under the character | `{ 0, -0.9, 0 }` |

  A state's clip may be a set of directions: `{ { angle = 0, clip = "-Walk_F.glb#Animation0" }, { angle = 45, clip = "-Walk_R45.glb#Animation0" }, ... }`, its angles in degrees clockwise from forward, seen from above, in any number and spacing. The two directions nearest the angle between where the character faces and where it moves play, each as near as the angle lies to it: halfway between 0 and 45 plays both at half.

  A world gives its characters a model through carrier defaults on its player mod (`defaults = { animation = { model = "modules/<mod>/assets/Model" } }`), with `Model-Idle.glb`, `Model-Walk.glb` and `Model-Jump.glb` beside that prefix.

- `animation/action = { state, speed }`: written by another mod that plays something on purpose (a cast, an emote). While it is there, it is played instead of the motion's state. It syncs as the mod that writes it declares.
- `animation/playing = { state, speed, angle }`: what the character plays now, written by the side that moves it, only when it changes. `angle` is where it moves against where it faces, in degrees clockwise, absent while it stands; a set of directions plays by it. When `animation` arrives on a character the server replicates, the server half lists it in the character's `core/net/sync` with its Transform's authority (`client` for a player, else `server`), on the reliable channel, and takes the entry off when `animation` goes from a character that stays. A character never replicated works out its own.
- `animation/motion = { at }`: where the character was last frame, on the side that moves it. Never synced.
- On each client, never synced: `animation/model = { scene }`: a child of the character holding the model's scene, and the scene's path. It carries `animation/clip`: every clip file the character's states name, each at its weight, those silent at 0, looping, at the state's speed. `animation/clip` builds the model's graph and plays it on the AnimationPlayer the scene spawned.

  If `animation` is removed from an entity that stays, `mod_registry` takes these off and despawns the children.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (client) | `animation/model` | On a changed `animation` whose fields are filled: spawn the model child with `SceneRoot = asset_server:load(scene)` and an empty `animation/clip`, or replace it when the scene differs from the one it holds |
| First (server) | `animation/sync` | On `animation` added to a replicated character: list `animation/playing` in its `core/net/sync` with its Transform's authority; on `animation` removed from one that stays, take the entry off |
| Update (both) | `animation/state` | Polls the characters this side moves (never replicated; a client's own player; on the server, one no client owns): from the body's velocity while that says it moves, else its motion since last frame (or its `animation/action`), the state, speed and angle, into `animation/playing` when it differs |
| Update (client), after the state | `animation/fade` | For every character with a model and an `animation/playing`, its own or one that arrived: each clip's weight on the model moves toward its target (the state's clip at 1, or its two nearest directions, or idle's for a state with none; 0 for the rest) at 5 a second, so a change of state or direction fades over 0.2 s, and the first state starts at its weights. A model at its targets and speed is not written |

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
- The state comes from how the character moved on the side that moves it: rising faster than 1 m/s is `jump`, falling faster is `fall`, moving across faster than 4 m/s with a `run` clip is `run` (its speed scaled by `run_speed`), faster than 0.1 m/s is `walk` (scaled by `walk_speed`), each between 0.3 and 2, else `idle`. Every clip plays at that one speed.
- The direction is measured, not decided: where the body faces is `facing`'s. With `facing/velocity` the body faces where it walks, so only the forward direction plays; with `facing/camera` it is the strafing angle. Every copy plays what the side that moves it worked out.
- The scene and clips are asset handles (`asset_server:load`). Bevy refills them in place when a file changes or arrives, so a changed model or clip file respawns the scene and changes the clip on every character using it, and nothing here runs again.
- A change to `animation` replaces only what it names anew: a new scene replaces the model child, a changed or removed clip rebuilds the graph, and a change to anything else (`walk_speed`) touches neither.
- A copy the side does not move never works out its state: its velocity comes from its synced Transform, which arrives in uneven bursts, so a steady walk read there jumped between walk and run: 22 to 42 flips in 10 s on a remote player and on a server-moved character, measured, against none since. Keeping silent clips playing (an evaluation per clip, all the time) and interpolating snapshots by the server's time (more machinery than syncing the state) were turned down; players and server-moved characters go the same way. `animation/playing` is written whenever the speed or angle changes, which for a character whose Transform is followed is most frames; its clip is never restarted for it.
- A clip fading out that is wanted again is not restarted: `animation/clip` restarts only a clip whose weight came back from 0. The model lists every clip file at all times, so its graph is built once for its set of files.
- Clips advance in a headless run too, but `test_animation_client.lua`, which reads them over time beside a reload, runs windowed. `test_animation_state.lua` (the state picked for bodies whose velocity reads still, and a character with no model) and `test_animation_play.lua` (what the character writes on its model: every clip, the fade, the speed, and no write at rest) run headless, and so does `test_animation_8d.lua` (a walk of eight directions: straight ahead, halfway between two, back and to the left; the run above 4 m/s, a walk just under it, and a character with no run clip). `test_animation_net.lua` runs over a real connection: another client's player and a server-moved character, each walking steadily, play one state on a third client for 10 s, with their angle, and so does that client's own player. All draw a fixture model in `tests/fixtures`: an animated node under an `Armature`, with no mesh (`Model-Walk8.gltf` holds eight clips of it, the directions).
- A file still downloading gives a handle that fills in when it lands (core), so a character draws and plays once its files arrive, without a rebuild.
- Not done yet: `vr/avatar` and `vr/calibration`, which use a character's model, are not in this library yet.
