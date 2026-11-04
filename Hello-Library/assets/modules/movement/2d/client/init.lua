-- The client half: the owner's body walks in the plane; others' bodies follow their synced
-- Transform. Input is the `input/game.movement_2d` group: an action is held while its
-- component exists. A 2D body never turns. The net client marks its own player
-- `core/net/local` frames after the player arrives, so both edges count.

local Vec2 = require("bevy::math::Vec2")
local Vec3 = require("bevy::math::Vec3")
local Time = require("bevy::time::Time")

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "movement/2d", "core/net/local", "input" },
        },
        with = { "movement/2d", "core/net/local", "input" },
    }],
    Commands,
}, function(owned, commands)
    for _, e in ipairs(owned:iter()) do
        commands:entity(e:id()):patch({
            ["input/game"] = {
                movement_2d = {
                    up = { key = "KeyW" },
                    down = { key = "KeyS" },
                    left = { key = "KeyA" },
                    right = { key = "KeyD" },
                },
            },
        })
    end
end):in_set("movement/2d/bind")

-- Another client's body: incoming Transforms land in the `core/net/sync/Transform` shadow,
-- which this client then eases toward.
app:add_systems(First, {
    Query[{
        added = { "movement/2d" },
        with = { "Transform" },
        without = { "core/net/local", "core/net/sync/Transform" },
    }],
    Commands,
}, function(others, commands)
    for _, e in ipairs(others:iter()) do
        commands:entity(e:id()):insert({ ["core/net/sync/Transform"] = e:get("Transform") })
    end
end):in_set("movement/2d/shadow")

-- The body arrives kinematic, as the server has it, and is simulated only on its owner's
-- client, so walls stop it there. It only changes type, as it arrived with its collider.
app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "movement/2d", "core/net/local" },
        },
        with = { "movement/2d", "core/net/local", Mut["RigidBody2d"] },
    }],
}, function(own)
    for _, e in ipairs(own:iter_mut()) do
        if e:get("RigidBody2d") ~= "Dynamic" then
            e:set({ RigidBody2d = "Dynamic" })
        end
    end
end):in_set("movement/2d/own")

-- Polls while the body moves, as the velocity eases over time. While a key is held it eases
-- toward the keys' direction at `speed`, and with none held it eases to rest and writes no more.
app:add_systems(Update, {
    Res[Time],
    Query[{
        any_of = {
            "input/game/movement_2d/up",
            "input/game/movement_2d/down",
            "input/game/movement_2d/left",
            "input/game/movement_2d/right",
        },
        with = { "movement/2d", "core/net/local", Mut["Velocity2d"] },
    }],
    Query[{
        with = { "movement/2d", "core/net/local", Mut["Velocity2d"] },
        without = {
            "input/game/movement_2d/up",
            "input/game/movement_2d/down",
            "input/game/movement_2d/left",
            "input/game/movement_2d/right",
        },
    }],
}, function(time, walkers, coasters)
    local dt = time:delta_secs()
    for _, e in ipairs(walkers:iter_mut()) do
        local m = e:get("movement/2d")
        local up = e:get("input/game/movement_2d/up")
        local down = e:get("input/game/movement_2d/down")
        local left = e:get("input/game/movement_2d/left")
        local right = e:get("input/game/movement_2d/right")
        local x = (right and right.value or 0) - (left and left.value or 0)
        local y = (up and up.value or 0) - (down and down.value or 0)
        local along = Vec2.normalize_or_zero({ x = x, y = y })
        -- analog input moves slower; two keys at once no faster than one
        local scale = m.speed * math.min(1, math.sqrt(x * x + y * y))
        -- opposite keys cancel out: that eases to rest like no key at all
        local rate = (x ~= 0 or y ~= 0) and m.acceleration or m.deceleration
        local linvel = e:get("Velocity2d").linvel
        e:patch({
            Velocity2d = {
                linvel = Vec2.lerp(linvel, { x = along.x * scale, y = along.y * scale }, math.min(1, rate * dt)),
            },
        })
    end
    for _, e in ipairs(coasters:iter_mut()) do
        local linvel = e:get("Velocity2d").linvel
        if linvel.x ~= 0 or linvel.y ~= 0 then
            local m = e:get("movement/2d")
            local eased = Vec2.lerp(linvel, { x = 0, y = 0 }, math.min(1, m.deceleration * dt))
            -- easing alone never reaches rest
            if Vec2.length(eased) < 0.1 then
                eased = { x = 0, y = 0 }
            end
            e:patch({ Velocity2d = { linvel = eased } })
        end
    end
end):in_set("movement/2d/walk")

-- Follows, so it polls: another client's body eases toward its synced Transform.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "movement/2d", "core/net/sync/Transform", Mut["Transform"] },
        without = { "core/net/local" },
    }],
}, function(time, others)
    local dt = time:delta_secs()
    for _, e in ipairs(others:iter_mut()) do
        local m = e:get("movement/2d")
        local target = e:get("core/net/sync/Transform")
        local current = e:get("Transform")
        e:patch({
            Transform = {
                translation = Vec3.lerp(current.translation, target.translation, math.min(1, m.smoothing * dt)),
            },
        })
    end
end):in_set("movement/2d/follow")

-- `movement/2d` was taken off an entity that stays: take off what this half added, unless `input`
-- went too, as its bindings go with it and a patch landing after that would bring them back. A
-- despawned entity has no row in `bound`.
app:add_systems(First, {
    Query[{
        removed = { "movement/2d" },
        optional = { "input" },
    }],
    Query[{ with = { "input/game" } }],
    Commands,
}, function(removed, bound, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        if e:has("input") then
            gone[#gone + 1] = e:id()
        end
    end
    for _, e in ipairs(bound:iter_many(gone)) do
        commands:entity(e:id()):patch({
            ["input/game"] = { movement_2d = null },
        })
    end
end):in_set("movement/2d/removed")
