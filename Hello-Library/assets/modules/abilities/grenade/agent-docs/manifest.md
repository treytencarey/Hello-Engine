---
depends_on: [abilities, abilities/projectile, camera]
conflicts_with: []
exposes: [abilities/grenade]
---

# abilities/grenade

A grenade: a key lobs a small glowing ball along the camera's look. It falls, bounces and ends when its lifetime does, and then the grenade cools down for a moment. It is an ability on the player: it registers its entry in `abilities` and removes it when it goes. Every player has one (`player`).

## Components

- `abilities/grenade = { key, cooldown, speed, radius, color }`: on the player. Missing fields get defaults:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `key` | the `KeyCode` that fires it | `KeyG` |
  | `cooldown` | seconds before it fires again | 1 |
  | `speed` | metres per second | 20 |
  | `radius` | the ball's radius | 0.2 |
  | `color` | `{ r, g, b }` | `{ 0.4, 0.9, 0.3 }` |

  It never crosses the network: the server holds it and fires, and its `abilities` entry reaches the owner.
- It writes `abilities.grenade = { key, cooldown }`. On its own press (`input/game/abilities/grenade` added) while it is not cooling (`abilities/grenade/cooling`), it spawns an `abilities/projectile` from 1 m above the player with the camera's yaw and pitch, under `projectile`'s gravity and lifetime. If `abilities/grenade` is removed from an entity that stays, its entry goes, and its cooldown with it.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `abilities/grenade/init` | Write its entry in `abilities` |
| Update | `abilities/grenade/fire` | On its press while not cooling, spawn its `abilities/projectile` |
| First | `abilities/grenade/removed` | When `abilities/grenade` is removed from an entity that stays, remove its entry |

## Use

```lua
-- on the server, on the player: a grenade with the default key, thrown harder
commands:entity(player):insert({ ["abilities/grenade"] = { speed = 30 } })
```

## Notes

- Its ball ends itself, by lifetime or by what it hits. It is marked `core/script/owner = false`, so a reload of this mod, or its last carrier leaving, does not take a ball in flight, and nothing throws another.
- Its cooling component is its own part (`abilities/grenade/cooling`), so `mod_registry` also strips it when `abilities/grenade` goes.
