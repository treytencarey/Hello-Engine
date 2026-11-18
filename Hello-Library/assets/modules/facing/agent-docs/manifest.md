---
depends_on: []
conflicts_with: []
exposes: [facing, facing/velocity, facing/camera]
---

# facing

Which way a character's body points. `facing` is the one writer of a character's rotation: movement moves it, facing turns it. The base turns the body toward a target and never decides one; a variant decides. Attach a variant, never `facing` itself: the variant's base brings it.

| Variant | Faces | Standing |
|---------|-------|----------|
| `facing/velocity` | where the character walks: the direction its own walking drives | holds still |
| `facing/camera` | where its camera looks, while it moves (strafing) | holds still |

`player` gives every player `facing/velocity`; `player/vr` swaps it for `facing/camera` while the player is in VR.

## Components

- `facing/velocity = {}`, `facing/camera = {}`: a variant, on a character, added on the server and synced from it. Each variant's client half has `base = "facing"`, so the mod registry adds `facing` beside it on each client, and a second variant there replaces the first. The server carries no `facing`, so a mod that swaps variants on the server removes the old one itself.
- `facing = { target, turn_rate }`: on each client, never synced. Missing fields get defaults when it is added.

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `target` | the rotation the body turns toward, written by the variant; absent, the body holds still | none |
  | `turn_rate` | radians per second | 10 |

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| Update (client), after `movement/walk` | `facing/velocity` | On this client's own characters while a movement key is held (`any_of` the `input/game.movement` actions): the target is the direction of `Velocity3d` as `movement/walk` wrote it this frame; keys that cancel out (no velocity) take the target off |
| Update (client), after `movement/walk` | `facing/camera` | Polls this client's own characters: moving, the target is `camera.yaw` turned half; standing, no target |
| Update (client), after both | `facing` | Polls this client's own characters with a target: turns the body toward it, at most `turn_rate` a second (Bevy's `Quat::rotate_towards`), and writes nothing once it is there |

## Authority

The owner's client turns its own characters (those in its own nets' `core/net/owns`), as it moves them. Their Transform reaches the server through the player's client-authority sync, the server eases its copy toward it (`player/follow`), and every other client eases its copy toward what the server sends (`movement/follow`). No client turns another's character.

## Use

```lua
-- on the server: a strafing character
commands:entity(character):insert({ ["facing/camera"] = {} })

-- a variant of a new kind: write the target on this client's own characters, after what it reads
app:add_systems(Update, {
    Query[{ with = { "my/variant", Mut["facing"] } }],
}, function(bodies)
    -- e:get_mut("facing").target = <a rotation>, or nil to hold still
end):in_set("my/variant")
-- its client half returns { base = "facing" }, and `facing` orders itself after it
```

## Notes

- `facing/velocity` reads the walk's own direction, so a push (knockback, another body) with no key held does not turn the body. Letting go of the keys leaves the last target, so a turn under way finishes.
- A body's front is +Z and a camera's look is -Z, hence the half turn in `facing/camera`.
- Neither variant turns a character standing still: with no turn-in-place clips, a body that turns on the spot slides its feet.
- A character the server drives itself (one with no owner) is not turned yet.
- The suite, headless: `tests/test_facing.lua` (the base arriving with its turn rate, walking turning the body at the rate, a push not turning it, another client's character not turned, the camera variant replacing the velocity one and facing the look while moving, and holding still standing).
