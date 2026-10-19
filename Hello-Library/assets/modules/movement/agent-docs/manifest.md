---
depends_on: [input, camera]
conflicts_with: []
exposes: [movement, movement/grounded]
---

# movement

Walking and jumping. The owning client moves its own player from input, relative to where its camera looks, and turns it to face where it goes; every other client eases its copy toward the synced Transform. The owner drives the Transform until prediction returns with the net rewrite, so the server runs no movement.

## Components

- `movement = { speed, jump, turn, ground, smoothing }`, added by `player` on the server and synced from it. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `speed` | metres per second | 6 |
  | `jump` | metres per second upward | 5 |
  | `turn` | how fast it turns to face where it goes, per second | 10 |
  | `ground` | metres from its origin to just below its feet (a capsule with half height 0.5 and radius 0.4 stands 0.9 above them) | 1 |
  | `smoothing` | how fast another client's copy follows its synced Transform, per second | 10 |

- `movement/grounded`: on the owner's client while it stands on something.
- On the owner's client it binds `input/game.movement` (`forward` W, `backward` S, `left` A, `right` D, `jump` Space) and writes `Velocity3d` and the Transform's rotation. On other clients it seeds the `core/net/sync/Transform` shadow incoming Transforms land in. If `movement` is removed from an entity that stays, the keys are unbound and `movement/grounded` removed.

## Systems

| Schedule | Label | Purpose |
|----------|-------|---------|
| First (both) | MovementInit | On an added `movement`, fill in missing fields |
| First (client) | MovementBind | When the player is this client's (`core/net/local` arrives frames after the player), bind its keys; again when `input` is added back |
| First (client) | MovementShadow | For another client's player, seed the shadow its Transform arrives in |
| Update (client) | MovementWalk | While a key is held (`any_of`), it polls: horizontal velocity from the held keys, turned by `camera.yaw`, and a turn to face that way. Letting go of a key (its `removed` edge) stands it still, and keys still held walk on. Vertical velocity is left to gravity and jumps |
| Update (client) | MovementGround | Polls: a ray down from the origin, skipping the player's own body, adds or removes `movement/grounded` |
| Update (client) | MovementJump | On a jump press while grounded, straight up at `jump` |
| Update (client) | MovementFollow | Polls: another client's player eases toward its synced Transform |
| First (client) | MovementRemoved | When `movement` is removed from an entity that stays, unbind; `movement/grounded` goes by `mod_registry` |

## Notes

- It faces where the keys point, not where it moves: a push does not turn it, and opposite keys held together stand it still without turning.
- One press is one jump: the jump reacts to the action's `added` edge, so the old cooldown after a jump is gone.
- The ground ray passes `{ exclude_rigid_body = <the player> }`; the old ray started inside the player's own capsule and always found it.
- Not yet carried over: facing where a VR headset looks (returns with `vr`), and server-side movement for prediction (returns with the net rewrite and the input action sync).
- The suite runs windowed: keys reach `input` through a window.
