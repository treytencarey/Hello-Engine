---
depends_on: [abilities, abilities/projectile, projectile/explode, camera]
conflicts_with: []
exposes: [abilities/fireball]
---

# abilities/fireball

A fireball: a key fires a glowing ball straight along the camera's look. It does not fall or bounce, and it explodes on the first thing it touches. Then the fireball cools down for a moment. It is an ability on the player: it registers its entry in `abilities` and removes it when it goes. Every player has one (`player`).

## Components

- `abilities/fireball = { key, cooldown, speed, radius, blast, color }`: on the player. Missing fields get defaults:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `key` | the `KeyCode` that fires it | `KeyQ` |
  | `cooldown` | seconds before it fires again | 1 |
  | `speed` | metres per second | 25 |
  | `radius` | the ball's radius | 0.25 |
  | `blast` | the explosion's radius | 1.5 |
  | `color` | `{ r, g, b }` | `{ 1, 0.3, 0.1 }` |

  It never crosses the network: the server holds it and fires, and its `abilities` entry reaches the owner.
- It writes `abilities.fireball = { key, cooldown }`. On its own press (`input/game/abilities/fireball` added) while it is not cooling (`abilities/fireball/cooling`), it spawns an `abilities/projectile` from 1 m above the player, with the camera's yaw and pitch, no gravity and a 5 s lifetime, plus `projectile/explode` with its blast and color. If `abilities/fireball` is removed from an entity that stays, its entry goes, and its cooldown with it.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `abilities/fireball/init` | Write its entry in `abilities` |
| Update | `abilities/fireball/fire` | On its press while not cooling, spawn its exploding projectile |
| First | `abilities/fireball/removed` | When `abilities/fireball` is removed from an entity that stays, remove its entry |

## Use

```lua
-- on the server, on the player: a fireball on KeyF, cooling for 2 s
commands:entity(player):insert({ ["abilities/fireball"] = { key = "KeyF", cooldown = 2 } })
```

## Notes

- Its ball ends itself, by lifetime or by what it hits. It is marked `core/script/owner = false`, so a reload of this mod, or its last carrier leaving, does not take a ball in flight, and nothing throws another.
- Its projectile carries `projectile/caster = { entity = <the player> }`, so it passes through the player who cast it, even fired straight down; the player lists it in `projectile/casts` while it flies. The fireball spawns it with `["core/net/sync"] = { ["projectile/caster"] = { authority = "server" } }`, so every client has the caster from the shot's first spawn and tells its own hits apart from the first frame (the spawn site declares it, an exception to the reader declaring).
