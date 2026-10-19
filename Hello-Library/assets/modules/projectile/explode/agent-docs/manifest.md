---
depends_on: [projectile, collision_trigger, explosion]
conflicts_with: []
exposes: [projectile/explode, projectile/explode/hit]
---

# projectile/explode

A projectile that explodes on contact. It passes through what it meets instead of bouncing (a sensor, through `collision_trigger`). Every side reacts at once to the first thing its own copy enters other than its caster: it hides the ball and shows its own `explosion` where it was. The server alone ends the ball, and its despawn reaches every client.

## Components

- `projectile/explode = { radius, duration, color }`: on a `projectile`. The fields are the explosion's; missing ones are the explosion's own defaults. Synced from the server, so a client's copy is a sensor too and reacts to its own hits.
- `projectile/explode/hit = {}`: on each side, once its copy has hit. Never synced. It hides the ball (`Visibility = Hidden`) and stops it reacting again.
- It adds `collision_trigger` to its entity, which makes the collider a sensor. If `projectile/explode` is removed from an entity that stays, it removes `collision_trigger` and `projectile/explode/hit`, and a ball it hid shows again.

## Systems

| Schedule | Label | Purpose |
|----------|-------|---------|
| First (both) | ProjectileExplodeSensor | On an added `projectile/explode`, add `collision_trigger` |
| Update (both) | ProjectileExplode | On the first thing it enters other than its caster: spawn a local `explosion` there, mark it `projectile/explode/hit` and hide it |
| Update (server), after `ProjectileExplode` | ProjectileExplodeEnd | On an added `projectile/explode/hit`, despawn the ball |
| First (both) | ProjectileExplodeRemoved | When `projectile/explode` is removed from an entity that stays, remove what it added and show the ball |

## Use

```lua
-- on the server
spawn({
    projectile = { from = muzzle, velocity = along_the_look, gravity = 0 },
    ["projectile/explode"] = { radius = 1.5 },
    ["projectile/caster"] = { entity = shooter:id() },
    -- the caster rides the first spawn, so every client tells its own hits apart at once
    ["core/net/sync"] = { ["projectile/caster"] = { authority = "server" } },
})
```

## Notes

- A client never despawns its copy: it hides it, and the server's despawn ends it a round trip later. Until then the hidden ball flies on, and what it enters shows nothing.
- The explosion is local on each side (never synced) and is spawned with `ScriptOwned = false`: the ball is this mod's last carrier, and its despawn would otherwise reap the explosion with the mod.
- It passes through its caster: an entity named by the projectile's `projectile/caster` (a relationship declared by `projectile`) never ends it. A projectile with no `projectile/caster` ends on anything. A client needs the caster from its copy's first frame, so whatever spawns the projectile syncs `projectile/caster` in the spawn itself.
- A client's hit and the server's can differ where the two worlds differ (another player standing elsewhere on each side). The server's despawn decides the ball; each side's explosion shows what that side saw.
