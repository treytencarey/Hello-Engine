---
depends_on: []
conflicts_with: []
exposes: [collision_trigger]
---

# collision_trigger

Makes an entity a trigger: when what overlaps it changes, `collision_trigger` says who came and who went. Needs 3D physics (Rapier) and a collider on the entity.

## Components

- `collision_trigger = { entered = { <entity>, ... }, exited = { <entity>, ... }, inside = { <entity>, ... } }`: written on each physics change of what overlaps the entity. `entered` and `exited` hold what changed since the last write; `inside` holds everything overlapping now.

When `collision_trigger` is added, the mod gives it this full shape and adds `Sensor3d`, `CollidingEntities3d` and `ActiveEvents3d`. It removes those three when `collision_trigger` is removed.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `collision_trigger/init` | On an added `collision_trigger`, set its shape and add the sensor components |
| First | `collision_trigger/removed` | On a removed `collision_trigger`, remove the sensor components |
| First | `collision_trigger` | On a changed `CollidingEntities3d`, write `entered`, `exited` and `inside` when anything changed |

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
