-- The client half: the owner's player walks, jumps and turns; others' players follow their
-- synced Transform. Input is the `input/game.movement` group: an action is held while its
-- component exists. The net client marks its own player `core/net/local` frames after the
-- player arrives, so both edges count.

local app = ...
local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")
local Time = require("bevy::time::Time")
local ReadRapierContext = require("bevy_rapier3d::plugin::ReadRapierContext")

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "movement", "core/net/local", "input" },
        },
        with = { "movement", "core/net/local" },
    }],
    Commands,
}, function(owned, commands)
    for _, e in ipairs(owned:iter()) do
        commands:entity(e:id()):patch({
            ["input/game"] = {
                movement = {
                    forward = { key = "KeyW" },
                    backward = { key = "KeyS" },
                    left = { key = "KeyA" },
                    right = { key = "KeyD" },
                    jump = { key = "Space" },
                },
            },
        })
    end
end):in_set("movement/bind")

-- Another client's player: incoming Transforms land in the `core/net/sync/Transform` shadow,
-- which this client then eases toward.
app:add_systems(First, {
    Query[{
        added = { "movement" },
        with = { "Transform" },
        without = { "core/net/local", "core/net/sync/Transform" },
    }],
    Commands,
}, function(others, commands)
    for _, e in ipairs(others:iter()) do
        commands:entity(e:id()):insert({ ["core/net/sync/Transform"] = e:get("Transform") })
    end
end):in_set("movement/shadow")

-- Walking: while a key is held, the horizontal velocity follows the keys, turned by the
-- camera's yaw, and the player turns to face that way. It polls while a key is held (ground
-- friction would slow a single push). Letting go of the last key stands it still; vertical
-- velocity is left to gravity and jumps.
app:add_systems(Update, {
    Res[Time],
    Query[{
        ["or"] = {
            removed = {
                "input/game/movement/forward",
                "input/game/movement/backward",
                "input/game/movement/left",
                "input/game/movement/right",
            },
        },
        with = { "movement", "core/net/local", "Velocity3d" },
    }],
    Query[{
        with = { "movement", "core/net/local", Mut["Velocity3d"] },
    }],
    Query[{
        any_of = {
            "input/game/movement/forward",
            "input/game/movement/backward",
            "input/game/movement/left",
            "input/game/movement/right",
        },
        with = { "movement", "camera", "core/net/local", Mut["Velocity3d"], Mut["Transform"] },
    }],
}, function(time, released, bodies, walkers)
    -- A released key stops its body here (only the edge is read), and the keys still held
    -- are walked below. A body that despawned has no row in `bodies`.
    local stopped = {}
    for _, e in ipairs(released:iter()) do
        stopped[#stopped + 1] = e:id()
    end
    for _, e in ipairs(bodies:iter_many_mut(stopped)) do
        e:patch({ Velocity3d = { linvel = { x = 0, z = 0 } } })
    end
    local dt = time:delta_secs()
    for _, e in ipairs(walkers:iter_mut()) do
        local m = e:get("movement")
        local camera = e:get("camera")
        local rotation = e:get("Transform").rotation
        local forward = e:get("input/game/movement/forward")
        local backward = e:get("input/game/movement/backward")
        local left = e:get("input/game/movement/left")
        local right = e:get("input/game/movement/right")
        local x = (right and right.value or 0) - (left and left.value or 0)
        local z = (backward and backward.value or 0) - (forward and forward.value or 0)
        -- `movement` is filled when it is added; skip until then
        if m.speed ~= nil then
            local along = Quat.mul_vec3(Quat.from_rotation_y(camera.yaw or 0),
                Vec3.normalize_or_zero({ x = x, y = 0, z = z }))
            -- analog input moves slower; two keys at once no faster than one
            local scale = m.speed * math.min(1, math.sqrt(x * x + z * z))
            e:patch({ Velocity3d = { linvel = { x = along.x * scale, z = along.z * scale } } })
            -- opposite keys cancel out: no direction to face
            if x ~= 0 or z ~= 0 then
                e:patch({
                    Transform = {
                        rotation = Quat.slerp(rotation,
                            Quat.from_rotation_arc({ x = 0, y = 0, z = 1 }, along),
                            math.min(1, m.turn * dt)),
                    },
                })
            end
        end
    end
end):in_set("movement/walk")

-- Polls: standing on something is a short ray down from the origin, past the feet, that
-- skips the player's own body, cast through Rapier's `ReadRapierContext`.
app:add_systems(Update, {
    Query[{
        with = { "movement", "core/net/local", "Transform" },
        optional = { "movement/grounded" },
    }],
    ReadRapierContext,
    Commands,
}, function(walkers, rapier, commands)
    for _, e in ipairs(walkers:iter()) do
        local m = e:get("movement")
        local at = e:get("Transform").translation
        local hit = m.ground ~= nil
            and rapier:cast_ray(at, { x = 0, y = -1, z = 0 }, m.ground, true, { exclude_rigid_body = e:id() }) ~= nil
        if hit and not e:has("movement/grounded") then
            commands:entity(e:id()):insert({ ["movement/grounded"] = {} })
        elseif not hit and e:has("movement/grounded") then
            commands:entity(e:id()):remove("movement/grounded")
        end
    end
end):in_set("movement/ground")

-- Space while standing: straight up at `jump`. One press is one jump (the action's `added` edge).
app:add_systems(Update, {
    Query[{
        added = { "input/game/movement/jump" },
        with = { "movement", "movement/grounded", "core/net/local", Mut["Velocity3d"] },
    }],
    Commands,
}, function(jumpers, commands)
    for _, e in ipairs(jumpers:iter_mut()) do
        local m = e:get("movement")
        e:patch({ Velocity3d = { linvel = { y = m.jump } } })
        commands:entity(e:id()):remove("movement/grounded")
    end
end):in_set("movement/jump")

-- Follows, so it polls: another client's player eases toward its synced Transform.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "movement", "core/net/sync/Transform", Mut["Transform"] },
        without = { "core/net/local" },
    }],
}, function(time, others)
    local dt = time:delta_secs()
    for _, e in ipairs(others:iter_mut()) do
        local m = e:get("movement")
        local target = e:get("core/net/sync/Transform")
        local current = e:get("Transform")
        if m.smoothing ~= nil then
            local t = math.min(1, m.smoothing * dt)
            e:patch({
                Transform = {
                    translation = Vec3.lerp(current.translation, target.translation, t),
                    rotation = Quat.slerp(current.rotation, target.rotation, t),
                },
            })
        end
    end
end):in_set("movement/follow")

-- `movement` was taken off an entity that stays: take off what this half added. A despawned
-- entity has no row in `bound`.
app:add_systems(First, {
    Query[{ removed = { "movement" } }],
    Query[{ with = { "input/game" } }],
    Commands,
}, function(removed, bound, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(bound:iter_many(gone)) do
        commands:entity(e:id()):patch({
            ["input/game"] = { movement = null },
        })
    end
end):in_set("movement/removed")
