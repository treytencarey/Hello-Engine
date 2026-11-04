-- --host
-- `animation/sprite` on a client: which clip it plays and which frame it shows, with a sheet laid out
-- as a real character's: 13 frames a row of 64 pixels, its clips far down the sheet. A headless run
-- has no image loader, so these characters name no image and hold a sprite as the mod would build it;
-- what builds it from an image is in test_animation_sprite_windowed.lua.
--
--   SP1  missing fields get defaults; with no image nothing is drawn, and no load is asked for, which
--        is the one thing that could raise
--   SP3  standing, it shows its idle clip's frame, in the sheet's row and column
--   SP4  a body's velocity walks it: the clip for that way, every frame in turn, none outside it
--   SP5  it stops: idle, facing the way it last went
--   SP6  a state with no clip of its own plays `idle`
--   SP7  a character with no body is read from how its Transform moves, and stands when it stops
--   SP8  a kinematic copy moved by its Transform walks too, and so does a body whose velocity reads
--        still as it moves, as Rapier's does on a frame holding two steps
--   SP9  a new tile size or column count shows at once
--   SP10 the mod's file edited: it still plays
--   SP11 taken off an entity that stays: its sprite and its parts go
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local AssetServer = require("bevy::asset::AssetServer")

local suite = helpers.create_suite("AnimationSpriteSuite")

-- Every load the mod asks for, with the real call still made.
local loads = 0
local real_load = AssetServer.load
function AssetServer.load(server, path)
    loads = loads + 1
    return real_load(server, path)
end

local SHEET = {
    tile_size = { x = 64, y = 64 },
    columns = 13,
    clips = {
        idle = { frames = { 130 }, fps = 1 },
        idle_down = { frames = { 130 }, fps = 1 },
        idle_right = { frames = { 143 }, fps = 1 },
        walk_right = { frames = { 143, 144, 145, 146 }, fps = 10 },
        walk_up = { frames = { 104, 105, 106, 107 }, fps = 10 },
    },
}

app:add_systems(Startup, { Commands }, function(commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    local carriers = {
        commands:spawn({
            ["zz/char"] = { name = "body" },
            ["animation/sprite"] = SHEET,
            Velocity2d = { linvel = { x = 0, y = 0 }, angvel = 0 },
            Transform = {},
        }):id(),
        commands:spawn({
            ["zz/char"] = { name = "bare" },
            ["animation/sprite"] = SHEET,
            Transform = {},
        }):id(),
        -- As another client's copy comes from `player/2d/spawner`: kinematic, moved by its Transform.
        commands:spawn({
            ["zz/char"] = { name = "copy" },
            ["animation/sprite"] = SHEET,
            Velocity2d = { linvel = { x = 0, y = 0 }, angvel = 0 },
            RigidBody2d = "KinematicPositionBased",
            Collider2d = { capsule_y = { radius = 8, half_height = 10 } },
            Transform = { translation = { x = 500, y = 500, z = 0 } },
        }):id(),
        commands:spawn({
            ["zz/char"] = { name = "still" },
            ["animation/sprite"] = SHEET,
            Velocity2d = { linvel = { x = 0, y = 0 }, angvel = 0 },
            Transform = {},
        }):id(),
    }
    for _, carrier in ipairs(carriers) do
        commands:spawn({
            ["animation/sprite/image"] = { path = "zz.png", scale = 1, z = 1 },
            Sprite = {},
            Transform = {},
            ChildOf = carrier,
        })
    end
    commands:spawn({
        ["zz/char"] = { name = "unnamed" },
        ["animation/sprite"] = {},
        Transform = {},
    })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/char" },
        optional = { "animation/sprite", "animation/sprite/playing", "animation/sprite/motion", "Transform", "Velocity2d" },
    })) do
        if e:get("zz/char").name == name then return e end
    end
end

local function sprites_of(world, e)
    return world:query({
        iter_many = world:descendants(e:id()),
        with = { "animation/sprite/image", "Sprite" },
    })
end

-- The frame a sprite shows, in a sheet of 13 frames a row of 64 pixels.
local function frame_of(sprite)
    local rect = sprite:get("Sprite").rect
    if not rect then return nil end
    return math.floor(rect.min.y / 64) * 13 + math.floor(rect.min.x / 64)
end

local phase, clock = "spawned", 0
local seen = {}
local bare_x, copy_x = 0, 500

-- Moved every frame, as a follower is.
local moving = false
app:add_systems(Update, { World }, function(world)
    local dt = world:delta_time() or 0
    if moving then
        bare_x = bare_x + 100 * dt
        copy_x = copy_x + 100 * dt
        named(world, "bare"):patch({ Transform = { translation = { x = bare_x, y = 0, z = 0 } } })
        named(world, "copy"):patch({ Transform = { translation = { x = copy_x, y = 500, z = 0 } } })
        named(world, "still"):patch({ Transform = { translation = { x = bare_x, y = 0, z = 0 } } })
    end
end):in_set("zz/animation_sprite_mover")

-- Every frame a walk shows, as it shows them.
app:add_systems(Last, { World }, function(world)
    if phase == "walking" then
        local frame = frame_of(sprites_of(world, named(world, "body"))[1])
        if frame then seen[frame] = true end
    end
end):in_set("zz/animation_sprite_frames")

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawned" and clock > 0.5 then
        local unnamed = named(world, "unnamed")
        local a = unnamed:get("animation/sprite")
        suite.assert_test("SP1a_missing_fields_get_defaults",
            a.tile_size.x == 16 and a.columns == 1 and a.speed == 1 and a.scale == 1 and a.z == 1 and a.clips.idle.frames[1] == 0, "")
        suite.assert_test("SP1b_with_no_image_nothing_is_drawn", #sprites_of(world, unnamed) == 0, "")
        suite.assert_test("SP1c_and_no_load_is_asked_for", loads == 0, loads .. " loads")
        local body = named(world, "body")
        local rect = sprites_of(world, body)[1]:get("Sprite").rect
        suite.assert_test("SP3_standing_it_shows_its_idle_frame_in_the_sheets_row_and_column",
            rect ~= nil and rect.min.x == 0 and rect.min.y == 640 and rect.max.x == 64 and rect.max.y == 704,
            rect and string.format("%s,%s to %s,%s", rect.min.x, rect.min.y, rect.max.x, rect.max.y) or "no rect")
        body:patch({ Velocity2d = { linvel = { x = 100, y = 0 } } })
        step("walking")

    elseif phase == "walking" and clock > 1.0 then
        local all, outside = true, false
        for _, f in ipairs({ 143, 144, 145, 146 }) do all = all and seen[f] == true end
        -- 130 is the idle frame it shows until the velocity's frame lands
        for f in pairs(seen) do outside = outside or (f ~= 130 and (f < 143 or f > 146)) end
        suite.assert_test("SP4a_a_velocity_walks_it_through_every_frame_of_that_clip", all, "")
        suite.assert_test("SP4b_and_none_outside_it", not outside, "")
        named(world, "body"):patch({ Velocity2d = { linvel = { x = 0, y = 0 } } })
        step("stopped")

    elseif phase == "stopped" and clock > 0.2 then
        local body = named(world, "body")
        local state = body:get("animation/sprite/playing").state
        suite.assert_test("SP5_it_stops_on_idle_facing_the_way_it_last_went",
            state == "idle_right" and frame_of(sprites_of(world, body)[1]) == 143, state)
        body:patch({ Velocity2d = { linvel = { x = 0, y = -100 } } })
        step("no clip")

    elseif phase == "no clip" and clock > 0.2 then
        local body = named(world, "body")
        local state = body:get("animation/sprite/playing").state
        suite.assert_test("SP6_a_state_with_no_clip_of_its_own_plays_idle",
            state == "walk_down" and frame_of(sprites_of(world, body)[1]) == 130, state)
        body:patch({ Velocity2d = { linvel = { x = 0, y = 0 } } })
        moving = true
        step("transforms moving")

    elseif phase == "transforms moving" and clock > 0.5 then
        local bare = named(world, "bare")
        local state = bare:get("animation/sprite/playing").state
        suite.assert_test("SP7a_with_no_body_it_is_read_from_how_it_moves",
            state == "walk_right" and frame_of(sprites_of(world, bare)[1]) >= 143, state)
        local copy = named(world, "copy")
        local copy_state = copy:get("animation/sprite/playing").state
        suite.assert_test("SP8_a_kinematic_copy_moved_by_its_transform_walks", copy_state == "walk_right",
            copy_state .. " velocity x " .. tostring(copy:get("Velocity2d").linvel.x))
        local still_state = named(world, "still"):get("animation/sprite/playing").state
        suite.assert_test("SP8b_a_velocity_reading_still_as_it_moves_walks", still_state == "walk_right", still_state)
        moving = false
        step("transforms stopped")

    elseif phase == "transforms stopped" and clock > 0.3 then
        local bare = named(world, "bare")
        local state = bare:get("animation/sprite/playing").state
        suite.assert_test("SP7b_and_stands_when_it_stops", state == "idle_right", state)
        bare:patch({ ["animation/sprite"] = { tile_size = { x = 32, y = 32 }, columns = 26 } })
        step("new tiles")

    elseif phase == "new tiles" and clock > 0.2 then
        local rect = sprites_of(world, named(world, "bare"))[1]:get("Sprite").rect
        -- frame 143 in a sheet of 26 frames a row of 32 pixels
        suite.assert_test("SP9_a_new_tile_size_and_column_count_show_at_once",
            rect.min.y == 160 and rect.min.x == 416 and rect.max.x == 448 and rect.max.y == 192,
            string.format("%s,%s to %s,%s", rect.min.x, rect.min.y, rect.max.x, rect.max.y))
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local path = "assets/modules/animation/sprite/client/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloaded")

    elseif phase == "reloaded" and clock > 1 then
        named(world, "body"):patch({ Velocity2d = { linvel = { x = 100, y = 0 } } })
        step("walking again")

    elseif phase == "walking again" and clock > 0.3 then
        local body = named(world, "body")
        local state = body:get("animation/sprite/playing").state
        suite.assert_test("SP10_after_a_reload_it_still_plays",
            state == "walk_right" and frame_of(sprites_of(world, body)[1]) >= 143, state)
        commands:entity(body:id()):remove("animation/sprite")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        local body = named(world, "body")
        suite.assert_test("SP11_taken_off_an_entity_that_stays_its_sprite_and_parts_go",
            body ~= nil and #sprites_of(world, body) == 0 and not body:has("animation/sprite/playing"), "")
        phase = "done"
        suite.finish("AnimationSpriteSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("SP_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("AnimationSpriteSuite")
    end
end):in_set("zz/animation_sprite_suite")
