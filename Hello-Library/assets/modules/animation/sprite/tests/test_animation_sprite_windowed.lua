-- --host (windowed: a headless run has no image loader)
-- `animation/sprite` on a client: the sprite it builds from an image. The suite makes its two sheets,
-- each a one-pixel PNG. Which clip and frame it shows is in test_animation_sprite.lua.
--
--   SW1  each character gets one child holding its sprite, scaled and raised as stated, on its frame,
--        its sheet loads, and one naming no image draws nothing
--   SW2  a change that names nothing new replaces nothing
--   SW3  a new image replaces the sprite, and so does a new scale or z
--   SW4  the mod's file edited: each character has one sprite, on its frame, and the old one is gone
--   SW5  taken off an entity that stays: its sprite and its parts go
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local PNG = "\x89\x50\x4e\x47\x0d\x0a\x1a\x0a\x00\x00\x00\x0d\x49\x48\x44\x52\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\x0d\x49\x44\x41\x54\x78\xda\x63\x64\x60\xf8\x5f\x0f\x00\x02\x87\x01\x80\xeb\x47\xba\x92\x00\x00\x00\x00\x49\x45\x4e\x44\xae\x42\x60\x82"

local suite = helpers.create_suite("AnimationSpriteWindowedSuite")

local SHEET = {
    image = "test_fixtures/zz_sprite_sheet.png",
    tile_size = { x = 64, y = 64 },
    columns = 13,
    scale = 2,
    z = 3,
    clips = {
        idle = { frames = { 130 }, fps = 1 },
    },
}

app:add_systems(Startup, { Commands }, function(commands)
    write_file_bytes("assets/test_fixtures/zz_sprite_sheet.png", PNG)
    write_file_bytes("assets/test_fixtures/zz_sprite_sheet_other.png", PNG)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ Camera2d = {}, Camera = { order = 0 } })
    commands:spawn({ ["zz/char"] = { name = "one" }, ["animation/sprite"] = SHEET, Transform = {} })
    commands:spawn({ ["zz/char"] = { name = "two" }, ["animation/sprite"] = SHEET, Transform = {} })
    commands:spawn({ ["zz/char"] = { name = "unnamed" }, ["animation/sprite"] = {}, Transform = {} })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/char" },
        optional = { "animation/sprite", "animation/sprite/playing", "Transform" },
    })) do
        if e:get("zz/char").name == name then return e end
    end
end

local function sprites_of(world, e)
    return world:query({
        iter_many = world:descendants(e:id()),
        with = { "animation/sprite/image", "Sprite", "Transform" },
    })
end

local phase, clock = "spawned", 0
local first
local arrived = 0

-- A sheet that filled its handle. A file that is not there never does.
app:add_systems(Update, {
    Query[{
        asset_changed = { "Sprite" },
        with = { "animation/sprite/image" },
    }],
}, function(sprites)
    arrived = arrived + #sprites:iter()
end):in_set("zz/animation_sprite_windowed_arrived")

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawned" and clock > 0.5 then
        local sprites = sprites_of(world, named(world, "one"))
        suite.assert_test("SW1a_each_character_gets_one_child_holding_its_sprite",
            #sprites == 1 and #sprites_of(world, named(world, "two")) == 1, "one has " .. #sprites)
        local t = sprites[1]:get("Transform")
        suite.assert_test("SW1b_scaled_and_raised_as_stated", t.scale.x == 2 and t.scale.y == 2 and t.translation.z == 3, "")
        suite.assert_test("SW1c_on_its_frame", sprites[1]:get("Sprite").rect.min.y == 640, "")
        suite.assert_test("SW1d_its_sheet_loads", arrived > 0, "arrived " .. arrived)
        suite.assert_test("SW1e_one_naming_no_image_draws_nothing", #sprites_of(world, named(world, "unnamed")) == 0, "")
        first = sprites[1]:id()
        named(world, "one"):patch({ ["animation/sprite"] = { speed = 2 } })
        step("speed")

    elseif phase == "speed" and clock > 0.2 then
        suite.assert_test("SW2_a_change_that_names_nothing_new_replaces_nothing",
            sprites_of(world, named(world, "one"))[1]:id() == first, "")
        named(world, "one"):patch({ ["animation/sprite"] = { image = "test_fixtures/zz_sprite_sheet_other.png" } })
        named(world, "two"):patch({ ["animation/sprite"] = { z = 9 } })
        step("new image")

    elseif phase == "new image" and clock > 0.2 then
        local sprites, others = sprites_of(world, named(world, "one")), sprites_of(world, named(world, "two"))
        suite.assert_test("SW3a_a_new_image_replaces_the_sprite",
            #sprites == 1 and sprites[1]:id() ~= first and sprites[1]:get("animation/sprite/image").path == "test_fixtures/zz_sprite_sheet_other.png", "")
        suite.assert_test("SW3b_a_new_z_too", #others == 1 and others[1]:get("Transform").translation.z == 9, "")
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local path = "assets/modules/animation/sprite/client/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloaded")

    elseif phase == "reloaded" and clock > 1 then
        local sprites, others = sprites_of(world, named(world, "one")), sprites_of(world, named(world, "two"))
        suite.assert_test("SW4_after_a_reload_each_character_has_one_sprite_on_its_frame",
            #sprites == 1 and #others == 1 and sprites[1]:get("Sprite").rect.min.y == 640, "one has " .. #sprites .. ", two has " .. #others)
        commands:entity(named(world, "one"):id()):remove("animation/sprite")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        local one = named(world, "one")
        suite.assert_test("SW5_taken_off_an_entity_that_stays_its_sprite_and_parts_go",
            one ~= nil and #sprites_of(world, one) == 0 and not one:has("animation/sprite/playing"), "")
        helpers.delete_fixture("test_fixtures/zz_sprite_sheet.png")
        helpers.delete_fixture("test_fixtures/zz_sprite_sheet_other.png")
        phase = "done"
        suite.finish("AnimationSpriteWindowedSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("SW_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("AnimationSpriteWindowedSuite")
    end
end):in_set("zz/animation_sprite_windowed_suite")
