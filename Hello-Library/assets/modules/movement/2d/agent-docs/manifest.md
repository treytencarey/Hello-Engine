---
depends_on: [input]
conflicts_with: [movement]
exposes: [movement/2d]
---

# movement/2d

Top-down 2D walking. The owning client moves its own body from input; every other client eases its copy toward the synced Transform. The owner drives the Transform, as there is no client prediction yet, so the server runs no movement. Its own component is how it knows an entity is 2D: it reads no camera.

## Components

- `movement/2d = { speed, acceleration, deceleration, smoothing }`, added by `player/2d` on the server and synced from it. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `speed` | pixels per second | 160 |
  | `acceleration` | how fast the velocity reaches the keys', per second | 14 |
  | `deceleration` | how fast it dies with no key held, per second | 20 |
  | `smoothing` | how fast another client's copy follows its synced Transform, per second | 16 |

- `Velocity2d`: added with `movement/2d` when the entity has none (the server does not send one), and left in place when `movement/2d` goes.
- On the owner's client it binds `input/game.movement_2d` (`up` W, `down` S, `left` A, `right` D) and writes `Velocity2d`. It never changes the owner's own `RigidBody2d`: the player mod turns it `Dynamic` (`player/2d` does so when the player is this client's), so a game's player can wait for its map's colliders, and until then the body stays kinematic and the velocity moves nothing. On other clients it seeds the `core/net/sync/Transform` shadow incoming Transforms land in. If `movement/2d` is removed from an entity that stays, the keys are unbound.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (both) | `movement/2d/init` | On an added `movement/2d` with no `Velocity2d`, add one |
| First (client) | `movement/2d/bind` | When the body is this client's (`core/net/local` arrives frames after it), bind its keys; again when `input` is added back |
| First (client) | `movement/2d/shadow` | For another client's body, seed the shadow its Transform arrives in |
| Update (client) | `movement/2d/walk` | Polls while it moves: with a key held (`any_of`), the velocity eases toward the keys' direction at `speed`; with none, it eases to rest and writes no more |
| Update (client) | `movement/2d/follow` | Polls: another client's body eases toward its synced Transform |
| First (client) | `movement/2d/removed` | When `movement/2d` is removed from an entity that stays, unbind |

## Use

```lua
-- on the server, on a body with a `RigidBody2d` and a `Collider2d`: walk faster than the default
commands:entity(player):insert({ ["movement/2d"] = { speed = 240 } })
```

## Notes

- It needs a body: `Velocity2d` moves nothing without a `RigidBody2d`, and nothing while it is kinematic. A body arrives kinematic from the server, as `player/2d/spawner` makes it, and the player mod changes only its type on its owner's client, as it arrived with its collider. Being dynamic there, walls stop it.
- Rapier's 2D world has no gravity, and is scaled at 100 pixels to the metre.
- A 2D body never turns: nothing here writes a rotation, and a follower eases only its translation.
- Other mods read `Velocity2d` for where the body goes (`animation/sprite`); Rapier writes a kinematic copy's from how it moved.
- The server needs no action component, as it runs no movement, so none is synced. Server-side movement waits for client prediction.
- No jump: a top-down world has no use for one.
