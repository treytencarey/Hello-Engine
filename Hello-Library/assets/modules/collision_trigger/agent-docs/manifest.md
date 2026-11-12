---
depends_on: []
conflicts_with: []
exposes: [collision_trigger]
---

# collision_trigger

Makes an entity a trigger: when what overlaps it changes, `collision_trigger` says who came and who went. Needs 3D physics (Rapier) and a collider on the entity.

## Components

- `collision_trigger = { entered = { <entity>, ... }, exited = { <entity>, ... }, inside = { <entity>, ... } }`: written on each physics change of what overlaps the entity. `entered` and `exited` hold what changed since the last write; `inside` holds everything overlapping now. An `inside` given when the trigger is added is where it starts from: a body listed there and overlapping at the first reading has not entered (`scope/portal` gives the bodies already standing in a portal it drops).

When `collision_trigger` is added, the mod gives it this full shape and adds whichever of `Sensor3d`, `CollidingEntities3d`, `ActiveEvents3d` (`"COLLISION_EVENTS"`) and `ActiveCollisionTypes3d` the entity lacks. One it already has stays as it is, so a hot reload does not read as everything having exited. It removes those four when `collision_trigger` is removed.

`ActiveCollisionTypes3d` is Rapier's default (`DYNAMIC_DYNAMIC|DYNAMIC_KINEMATIC|DYNAMIC_STATIC`) with `KINEMATIC_STATIC`: the default leaves out a kinematic body against a fixed one, so a fixed trigger (a portal, a door) would never see a body moved by its Transform, which is what a player is on the server and another client's player is on a client. `KINEMATIC_KINEMATIC` is left out: no trigger in this library is kinematic.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `collision_trigger/init` | On an added `collision_trigger`, add whichever of the sensor components it lacks |
| First | `collision_trigger/removed` | On a removed `collision_trigger`, remove the sensor components |
| First | `collision_trigger` | After `collision_trigger/init`. On a changed `CollidingEntities3d` of an entity whose collider Rapier holds (`RapierColliderHandle3d`), write `entered`, `exited` and `inside` when anything changed. Before Rapier holds it, `CollidingEntities3d` is only the empty set `init` inserted, so it is not read: reading it would empty a starting `inside` and the next reading would count its bodies as entering |

## Use

```lua
commands:entity(door):patch({
    collision_trigger = {},
    Collider3d = { cuboid = { hx = 1, hy = 2, hz = 0.2 } },
})

-- in Update
app:add_systems(Update, {
    Query[{ changed = { "collision_trigger" } }],
}, function(triggers)
    for _, e in ipairs(triggers:iter()) do
        local entered = e:get("collision_trigger").entered or {}
        for _, id in ipairs(entered) do
            -- something walked into the door
        end
    end
end)
```

## Notes

- Read it in `Update` or later, never in `First`, where it is written.
- `collision_trigger` holds only the latest change. A consumer that misses a run still sees `inside`, but not every entry and exit in between.
- `entered`, `exited` and `inside` hold entity values: compare one with `==` to an `id()`.
- A fixed trigger sees every kinematic body too: on a client, other players walk in as well as this client's own, so a consumer that cares only for its own player filters for it (`core/net/local`).
- Suite: `tests/test_collision_trigger.lua`, headless, with real Rapier bodies: T1-T3 entries and exits of dynamic bodies, never a mirror; T4-T5 removal and despawn; T6-T8 a trigger with its own list, through a reload; T9 a kinematic body moved by its Transform into a fixed trigger enters it. A starting `inside` is covered by `scope/portal`'s suites (a portal dropped on a player, a door spawned around one).
