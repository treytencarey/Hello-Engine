-- The client half: the owner's player walks, jumps and turns; others' players follow their
-- synced Transform. Input is the `input/game.movement` group: an action is held while its
-- component exists. The net client marks its own player `core/net/local` frames after the
-- player arrives, so both edges count.

register_system("First", function(world)
    for _, e in ipairs(world:query({
        ["or"] = {
            added = { "movement", "core/net/local", "input" },
        },
        with = { "movement", "core/net/local" },
    })) do
        e:patch({
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
end, { label = "MovementBind" })

-- Another client's player: incoming Transforms land in the `core/net/sync/Transform` shadow,
-- which this client then eases toward.
register_system("First", function(world)
    for _, e in ipairs(world:query({
        added = { "movement" },
        with = { "Transform" },
        without = { "core/net/local", "core/net/sync/Transform" },
    })) do
        e:patch({ ["core/net/sync/Transform"] = e:get("Transform") })
    end
end, { label = "MovementShadow" })

-- Walking: while a key is held, the horizontal velocity follows the keys, turned by the
-- camera's yaw, and the player turns to face that way. It polls while a key is held (ground
-- friction would slow a single push). Letting go of the last key stands it still; vertical
-- velocity is left to gravity and jumps.
register_system("Update", function(world)
    -- A released key's row still answers get() with its old value: stop here, and the
    -- keys still held are walked below.
    for _, e in ipairs(world:query({
        ["or"] = {
            removed = {
                "input/game/movement/forward",
                "input/game/movement/backward",
                "input/game/movement/left",
                "input/game/movement/right",
            },
        },
        with = { "movement", "core/net/local", "Velocity3d" },
    })) do
        e:patch({ Velocity3d = { linvel = { x = 0, z = 0 } } })
    end
    local dt = world:delta_time() or 0
    for _, e in ipairs(world:query({
        any_of = {
            "input/game/movement/forward",
            "input/game/movement/backward",
            "input/game/movement/left",
            "input/game/movement/right",
        },
        with = { "movement", "camera", "core/net/local", "Velocity3d", "Transform" },
    })) do
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
            local along = world:call_static_method("Quat", "mul_vec3",
                world:call_static_method("Quat", "from_rotation_y", camera.yaw or 0),
                world:call_static_method("Vec3", "normalize_or_zero", { x = x, y = 0, z = z }))
            -- analog input moves slower; two keys at once no faster than one
            local scale = m.speed * math.min(1, math.sqrt(x * x + z * z))
            e:patch({ Velocity3d = { linvel = { x = along.x * scale, z = along.z * scale } } })
            -- opposite keys cancel out: no direction to face
            if x ~= 0 or z ~= 0 then
                e:patch({
                    Transform = {
                        rotation = world:call_static_method("Quat", "slerp", rotation,
                            world:call_static_method("Quat", "from_rotation_arc", { x = 0, y = 0, z = 1 }, along),
                            math.min(1, m.turn * dt)),
                    },
                })
            end
        end
    end
end, { label = "MovementWalk" })

-- Polls: standing on something is a short ray down from the origin, past the feet, that
-- skips the player's own body.
register_system("Update", function(world)
    for _, e in ipairs(world:query({
        with = { "movement", "core/net/local", "Transform" },
        optional = { "movement/grounded" },
    })) do
        local m = e:get("movement")
        local at = e:get("Transform").translation
        local hit = m.ground ~= nil
            and world:call_systemparam_method("ReadRapierContext3d", "cast_ray",
                at, { x = 0, y = -1, z = 0 }, m.ground, true, { exclude_rigid_body = e:id() }) ~= nil
        if hit and not e:has("movement/grounded") then
            e:patch({ ["movement/grounded"] = {} })
        elseif not hit and e:has("movement/grounded") then
            e:patch({ ["movement/grounded"] = null })
        end
    end
end, { label = "MovementGround" })

-- Space while standing: straight up at `jump`. One press is one jump (the action's `added` edge).
register_system("Update", function(world)
    for _, e in ipairs(world:query({
        added = { "input/game/movement/jump" },
        with = { "movement", "movement/grounded", "core/net/local" },
    })) do
        local m = e:get("movement")
        e:patch({
            Velocity3d = { linvel = { y = m.jump } },
            ["movement/grounded"] = null,
        })
    end
end, { label = "MovementJump" })

-- Follows, so it polls: another client's player eases toward its synced Transform.
register_system("Update", function(world)
    local dt = world:delta_time() or 0
    for _, e in ipairs(world:query({
        with = { "movement", "core/net/sync/Transform", "Transform" },
        without = { "core/net/local" },
    })) do
        local m = e:get("movement")
        local target = e:get("core/net/sync/Transform")
        local current = e:get("Transform")
        if m.smoothing ~= nil then
            local t = math.min(1, m.smoothing * dt)
            e:patch({
                Transform = {
                    translation = world:call_static_method("Vec3", "lerp", current.translation, target.translation, t),
                    rotation = world:call_static_method("Quat", "slerp", current.rotation, target.rotation, t),
                },
            })
        end
    end
end, { label = "MovementFollow" })

-- `movement` was taken off an entity that stays: take off what this half added.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "movement" } })) do
        e:patch({
            ["input/game"] = { movement = null },
        })
    end
end, { label = "MovementRemoved" })
