-- Makes plain bodies for a scene to populate itself with, and links each to itself: the same body and
-- collider a player has, with `animation` for its model and `movement` for how clients show it. What
-- a body becomes is for a subclass to say, as `ai/archetype/<name>/spawner`, which has this mod as its
-- base. Raising `count` adds bodies; lowering it takes none. They go with the spawner.
--
-- ai/spawner = {
--     count = <bodies>,
--     radius = <metres from the centre>,
--     center_x = <metres>,
--     center_z = <metres>,
--     y = <metres up they start>,
--     body_radius = <metres>,
--     body_half_height = <metres>,
--     model = <the `animation` model; absent, its default>,
-- }
--
-- ai/spawner/agent = { entity = <its spawner> }: on a body
-- ai/spawner/agents: a spawner's bodies, kept by the engine

local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")

-- A body's place comes from its number, turning by the golden angle, so any first few are evenly
-- spread and more fill the gaps. They outlive this mod's reloads, and their link takes them with the
-- spawner.
app:add_systems(First, {
    Query[{
        changed = { "ai/spawner" },
        optional = { "ai/spawner/agents" },
    }],
    Commands,
}, function(spawners, commands)
    for _, e in ipairs(spawners:iter()) do
        local s = e:get("ai/spawner")
        for i = #(e:get("ai/spawner/agents") or {}) + 1, s.count do
            local at = Vec3.add({ x = s.center_x, y = s.y, z = s.center_z },
                Quat.mul_vec3(Quat.from_rotation_y(i * math.pi * (3 - math.sqrt(5))), { x = s.radius, y = 0, z = 0 }))
            commands:spawn({
                ["ai/spawner/agent"] = { entity = e:id() },
                animation = { model = s.model },
                movement = {},
                Transform = { translation = at },
                RigidBody3d = "Dynamic",
                Collider3d = { capsule_y = { radius = s.body_radius, half_height = s.body_half_height } },
                LockedAxes3d = "ROTATION_LOCKED",
                Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
                ["core/net/sync"] = {
                    Transform = { authority = "server", reliable = false },
                    RigidBody3d = { authority = "server" },
                    Collider3d = { authority = "server" },
                    LockedAxes3d = { authority = "server" },
                },
                -- It ends at this mod's own `removed` edge (`ai/spawner/removed`).
                ["core/script/owner"] = false,
            })
        end
    end
end):in_set("ai/spawner/spawn")

-- `ai/spawner` was taken off an entity that stays: its bodies go, as they would with the entity.
app:add_systems(First, {
    Query[{
        removed = { "ai/spawner" },
        with = { "ai/spawner/agents" },
    }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        for _, body in ipairs(e:get("ai/spawner/agents")) do
            commands:entity(body):try_despawn()
        end
    end
end):in_set("ai/spawner/removed")

return {
    defaults = {
        ["ai/spawner"] = {
            count = 1,
            radius = 12,
            center_x = 0,
            center_z = 0,
            y = 1.5,
            body_radius = 0.4,
            body_half_height = 0.5,
        },
    },
    relationships = {
        ["ai/spawner/agent"] = { target = "ai/spawner/agents", linked_spawn = true },
    },
}
