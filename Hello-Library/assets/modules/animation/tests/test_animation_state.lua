-- --host
-- `animation` on a client: the state it picks for characters whose body's velocity does not say
-- how they move, and for one with no model. Headless: the scene's AnimationPlayer and its graph
-- exist, though no clip advances. The model is a fixture: an animated node under an `Armature`.
--
--   AS1 a character whose velocity reads still as its Transform moves walks: Rapier writes a
--       kinematic copy's velocity as still on a frame holding two physics steps
--   AS2 another client's player as it arrives here (`movement`, which gives it a velocity, eases
--       its kinematic body toward the synced Transform) walks steadily while its Transform walks
--   AS3 with no model set, nothing is drawn or played, though its other fields are filled
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("AnimationStateSuite")

local MODEL = "modules/animation/tests/fixtures/Model"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        Transform = { translation = { x = 0, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 100, hy = 0.5, hz = 100 } },
    })
    -- no body: nothing writes its velocity, which reads still however it moves
    commands:spawn({
        ["zz/char"] = { name = "still" }, animation = { model = MODEL },
        Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
        Transform = { translation = { x = 0, y = 1, z = 10 } },
    })
    -- as `player/spawner` sends another client's player
    commands:spawn({
        ["zz/char"] = { name = "copy" }, movement = {}, animation = { model = MODEL },
        Transform = { translation = { x = 0, y = 0.9, z = 0 } },
        RigidBody3d = "KinematicPositionBased",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
    })
    commands:spawn({
        ["zz/char"] = { name = "bare" }, animation = {},
        Transform = { translation = { x = 0, y = 1, z = -10 } },
    })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/char" },
        optional = { "animation", "animation/playing", "Transform", "core/net/sync/Transform" },
    })) do
        if e:get("zz/char").name == name then return e end
    end
end

--- Whether the character's model has its graph (`animation/clip` builds it on the model).
local function built(world, e)
    return #world:query({ with = { "animation/model", "animation/clip/graph" }, iter_many = world:descendants(e:id()) }) > 0
end

local phase, clock = "loading", 0
local seen = { frames = 0, walking = 0, changes = 0 }

-- While walking, each moves 3 m/s: the bodyless one its Transform, the copy its packets (the synced
-- Transform it eases toward).
app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "zz/char", Mut["Transform"] }, without = { "movement" } }],
    Query[{ with = { "zz/char", Mut["core/net/sync/Transform"] } }],
}, function(time, bodyless, copies)
    if phase ~= "walking" then return end
    local dx = 3 * time:delta_secs()
    for _, e in ipairs(bodyless:iter_mut()) do
        local t = e:get_mut("Transform")
        t.translation.x = t.translation.x + dx
    end
    for _, e in ipairs(copies:iter_mut()) do
        local t = e:get_mut("core/net/sync/Transform")
        t.translation.x = t.translation.x + dx
    end
end):in_set("zz/animation_state_mover")
    -- their state reads this frame's move with this frame's time step
    :before("animation/state")
    :before("movement/follow")

app:add_systems(Update, { World, Res[Time] }, function(world, time)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local still, copy = named(world, "still"), named(world, "copy")

    if phase == "loading" then
        local ready = still and copy and built(world, still) and built(world, copy)
            and copy:has("core/net/sync/Transform")
        if not ready and clock < 10 then return end
        step("settle")

    elseif phase == "settle" then
        if clock >= 0.5 then step("walking") end

    elseif phase == "walking" then
        if clock < 0.5 then return end
        local state = (copy:get("animation/playing") or {}).state
        seen.frames = seen.frames + 1
        if state == "walk" then seen.walking = seen.walking + 1 end
        if seen.state ~= nil and seen.state ~= state then seen.changes = seen.changes + 1 end
        seen.state = state
        if clock < 2.5 then return end
        local s = (still:get("animation/playing") or {}).state
        suite.assert_test("AS1_a_velocity_reading_still_as_it_moves_walks", s == "walk", tostring(s))
        -- Measured: read from its velocity alone it walked 10 to 32% of frames; on a loaded
        -- machine (frames of 0.15 s) a frame here and there still reads idle.
        suite.assert_test("AS2_another_clients_player_walks_steadily",
            seen.walking >= seen.frames * 0.8,
            string.format("walk %d of %d frames, %d changes", seen.walking, seen.frames, seen.changes))
        local bare = named(world, "bare")
        local a = bare:get("animation")
        local models = world:query({ with = { "animation/model" }, iter_many = world:descendants(bare:id()) })
        suite.assert_test("AS3_with_no_model_nothing_is_drawn_or_played",
            a.model == nil and a.walk_speed == 6 and #models == 0
                and not bare:has("animation/playing"),
            string.format("model=%s walk_speed=%s models=%d playing=%s", tostring(a.model), tostring(a.walk_speed),
                #models, tostring(bare:has("animation/playing"))))
        suite.finish("ANIMATION_STATE")
        phase = "done"
    end
end):in_set("zz/animation_state_suite"):after("animation/state")
