---
depends_on: []
conflicts_with: []
exposes: [ai/noisemaker, ai/noisemaker/state, ai/noisemaker/sound]
---

# ai/noisemaker

Makes noise when its entity moves, for whatever listens (AI hearing). Generic: put it on a player, a rolling barrel or anything else with a `Velocity3d`. Moving slower than `quiet_speed` is silent, which is how a player sneaks. Faster is louder, and at `run_speed` it also repeats sooner. Server only; nothing syncs.

## Components

- `ai/noisemaker = { interval, loudness, kind, quiet_speed, run_speed, min_loudness, run_interval }`, added by whoever wants the noise. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `interval` | seconds between sounds | 0.5 |
  | `loudness` | how loud at `run_speed` or faster | 1 |
  | `kind` | what the sound is, for whoever hears it | `"footstep"` |
  | `quiet_speed` | metres per second below which it is silent | 2.5 |
  | `run_speed` | metres per second at which it is loudest and repeats sooner | 5 |
  | `min_loudness` | the share of `loudness` it never drops below | 0.3 |
  | `run_interval` | the share of `interval` it waits at `run_speed` or faster | 0.7 |

- `ai/noisemaker/state = { next_at }`: `Time`'s elapsed seconds at which it may sound again. Added with the defaults; goes with `ai/noisemaker` by `mod_registry`.

## Events

- `ai/noisemaker/sound = { entity, x, y, z, loudness, kind }`: one sound. `entity` is what made it, and `x`, `y`, `z` where its `Transform` was.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/noisemaker/init` | On an added `ai/noisemaker`, fill in missing fields and add its state, unless it has one |
| PostUpdate | `ai/noisemaker/sound` | On a changed `Velocity3d`, trigger the sound if it is moving fast enough and its wait is over |

## Use

```lua
-- on the server
commands:entity(barrel):patch({ ["ai/noisemaker"] = { interval = 0.8, loudness = 0.6, kind = "rolling" } })

-- hear it, in any mod on the server
local On = require("bevy::ecs::prelude::On")

app:add_observer(On["ai/noisemaker/sound"], {}, function(event)
    print(event.kind, event.loudness, event.x, event.y, event.z)
end)
```

## Notes

- Only horizontal speed counts: rising and falling make no noise.
- A change to `Velocity3d` runs it, so it costs nothing while its entity stands still. Whoever writes `Velocity3d` every frame, or physics changing it, keeps it sounding. A body that keeps one velocity with nothing writing it makes one sound at most.
- A server's player makes noise too: its body is kinematic and moves through its `Transform`, and Rapier writes the velocity that gives into `Velocity3d`.
- A sound is an event, so it is heard as it happens and nothing is left to clean up. Anything else that makes a one-off sound (a door, a scripted scare) triggers the same event.
- A reload keeps the fields given and the running wait.
