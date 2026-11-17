-- --host
-- Respawn on a real player, driven headless: `player/client` adds the carrier and the menu, a real
-- click on the menu's button opens it, and a real click on the Respawn item stands the player on
-- its claimed point. The body is the spawner's capsule, dynamic as its owner has it, with no
-- gravity, so where the click puts it is where it stays.
--
--   R1 the item is in the menu's list, labelled Respawn
--   R2 a click stands the player on its claimed point by the capsule's height along the point's up,
--      at rest, its camera turned to the point's facing, and not on another point
--   R3 at twice the scale, twice the height
--   R4 no claim, or a claim naming no point here: no move
--   R5 a reload of the mod: one item, and its click still respawns
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("RespawnSuite")
local T = suite.assert_test

local MOD_FILE = "assets/modules/player/respawn/init.lua"
local original

local function finish()
    if original ~= nil then
        write_file_bytes(MOD_FILE, original)
    end
    suite.finish("RESPAWN")
end

-- A point turned and tilted, so its up is not the world's, and a second point the claim does not
-- name, spawned first.
local facing = Quat.mul_quat(Quat.from_rotation_y(0.7), Quat.from_rotation_x(0.3))
local start = { x = 3, y = 2, z = -4 }

local camera, player

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    camera = commands:spawn({ ["zz/camera"] = {} }):id()
    commands:spawn({
        ["zz/point"] = {},
        ["player/spawner/point"] = {},
        Name = "zz_other",
        Transform = { translation = { x = -20, y = 5, z = 20 } },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["zz/point"] = {},
        ["player/spawner/point"] = {},
        Name = "zz_start",
        Transform = { translation = start, rotation = facing },
        ["core/net/sync"] = false,
    })
    player = commands:spawn({
        ["zz/player"] = {},
        player = { client_id = 1, spawn_point = "zz_start" },
        ["core/net/sync"] = false,
        Transform = { translation = { x = -6, y = 9, z = 5 } },
        RigidBody3d = "KinematicPositionBased",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
        Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
        GravityScale3d = { value = 0 },
        camera = { yaw = 2.5 },
    }):id()
end)

local reloads = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("player/respawn/init.lua", 1, true) then
            reloads = reloads + 1
        end
    end
end):in_set("zz/respawn/reload_watch")

local function menu_button(world)
    return world:query({ with = { "sidebar/menu/button", "Button" } })[1]
end

local function items(world)
    return world:query({
        with = { "player/respawn/item" },
        optional = { "sidebar/menu/item", "Text", "Button", "ChildOf" },
    })
end

local function me(world)
    return world:query({
        with = { "zz/player" },
        optional = { "player/respawn", "sidebar/menu", "RigidBody3d", "Velocity3d", "camera", "player" },
    })[1]
end

local function placed(world)
    return world:get_entity(player).GlobalTransform:compute_transform().translation
end

local function near(a, b, within)
    return math.abs(a.x - b.x) < within and math.abs(a.y - b.y) < within and math.abs(a.z - b.z) < within
end

local function show(v)
    return string.format("(%.3f, %.3f, %.3f)", v.x, v.y, v.z)
end

local function at_rest(world)
    local v = me(world):get("Velocity3d")
    return near(v.linvel, { x = 0, y = 0, z = 0 }, 1e-4) and near(v.angvel, { x = 0, y = 0, z = 0 }, 1e-4),
        show(v.linvel)
end

local function standing(height)
    return Vec3.add(start, Quat.mul_vec3(facing, { x = 0, y = height, z = 0 }))
end

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

local function claim(commands, name)
    commands:entity(player):entry("player"):and_modify(function(p)
        p.spawn_point = name
    end)
end

local phase, clock = "arrived", 0
local mark = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    -- The net client marks its own player local frames after it arrives.
    if phase == "arrived" and clock > 0.3 then
        T("R0_nothing_before_the_player_is_ours", not me(world):has("player/respawn") and #items(world) == 0)
        commands:entity(player):insert({ ["core/net/local"] = {} })
        step("button")

    elseif phase == "button" and menu_button(world) ~= nil and clock > 0.2 then
        local p = me(world)
        T("R0_player_client_adds_respawn_beside_the_menu", p:has("player/respawn") and p:has("sidebar/menu"))
        T("R0_no_item_while_the_menu_is_closed", #items(world) == 0)
        click(commands, menu_button(world):id())
        step("item")

    elseif phase == "item" and #items(world) > 0 and items(world)[1]:has("Text") and clock > 0.2 then
        local list = items(world)
        local item = list[1]
        local data = item:get("sidebar/menu/item")
        local holder = world:query({ with = { "sidebar/menu/list" } })[1]
        T("R1_one_item_in_the_menu_s_list", #list == 1 and holder ~= nil and item:get("ChildOf") == holder:id())
        T("R1_labelled_respawn_and_not_a_toggle", data.title == "Respawn" and data.on == nil
            and item:get("Text") == "Respawn" and item:has("Button"), tostring(item:get("Text")))
        T("R1_the_body_is_the_owner_s_dynamic_one", me(world):get("RigidBody3d") == "Dynamic",
            tostring(me(world):get("RigidBody3d")))
        commands:entity(player):entry("Velocity3d"):and_modify(function(v)
            v.linvel = { x = 2, y = 1, z = -1 }
        end)
        mark.item = item:id()
        step("drifting")

    elseif phase == "drifting" and clock > 0.3 then
        mark.drifted = placed(world)
        T("R2_before_the_click_the_body_drifts", not near(mark.drifted, { x = -6, y = 9, z = 5 }, 0.1), show(mark.drifted))
        click(commands, mark.item)
        step("respawned")

    elseif phase == "respawned" and clock > 0.4 then
        local at = placed(world)
        local want = standing(0.9)
        T("R2_a_click_stands_it_on_its_point_by_the_capsule_s_height_along_the_point_s_up", near(at, want, 0.01),
            show(at) .. " against " .. show(want))
        local still, speed = at_rest(world)
        T("R2_at_rest", still, speed)
        local yaw = me(world):get("camera").yaw
        T("R2_its_camera_turned_to_the_point_s_facing", math.abs(yaw - 0.7) < 1e-3, tostring(yaw))
        commands:entity(player):entry("Transform"):and_modify(function(t)
            t.translation = { x = 10, y = 10, z = 10 }
            t.scale = { x = 2, y = 2, z = 2 }
        end)
        step("scaled")

    elseif phase == "scaled" and clock > 0.3 then
        click(commands, mark.item)
        step("respawned_scaled")

    elseif phase == "respawned_scaled" and clock > 0.4 then
        local at = placed(world)
        local want = standing(1.8)
        T("R3_at_twice_the_scale_twice_the_height", near(at, want, 0.01), show(at) .. " against " .. show(want))
        commands:entity(player):entry("Transform"):and_modify(function(t)
            t.translation = { x = 10, y = 10, z = 10 }
            t.scale = { x = 1, y = 1, z = 1 }
        end)
        commands:entity(player):entry("camera"):and_modify(function(c)
            c.yaw = 2.5
        end)
        claim(commands, nil)
        step("unclaimed")

    elseif phase == "unclaimed" and clock > 0.3 then
        mark.before = placed(world)
        click(commands, mark.item)
        step("unclaimed_clicked")

    elseif phase == "unclaimed_clicked" and clock > 0.4 then
        local at = placed(world)
        local yaw = me(world):get("camera").yaw
        T("R4_no_claim_no_move", near(at, mark.before, 1e-3) and math.abs(yaw - 2.5) < 1e-6,
            show(at) .. " against " .. show(mark.before) .. ", yaw " .. tostring(yaw))
        claim(commands, "zz_missing")
        step("missing")

    elseif phase == "missing" and clock > 0.3 then
        mark.before = placed(world)
        click(commands, mark.item)
        step("missing_clicked")

    elseif phase == "missing_clicked" and clock > 0.4 then
        local at = placed(world)
        local yaw = me(world):get("camera").yaw
        T("R4_a_claim_naming_no_point_here_no_move", near(at, mark.before, 1e-3) and math.abs(yaw - 2.5) < 1e-6,
            show(at) .. " against " .. show(mark.before) .. ", yaw " .. tostring(yaw))
        claim(commands, "zz_start")
        mark.reloads = reloads
        original = read_file_bytes(MOD_FILE)
        write_file_bytes(MOD_FILE, original .. "\n-- zz 1\n")
        step("reloading")

    elseif phase == "reloading" and reloads > mark.reloads then
        step("reloaded")

    elseif phase == "reloaded" and clock > 1 and #items(world) > 0 and items(world)[1]:has("Text") then
        local list = items(world)
        T("R5_a_reload_leaves_one_new_item", #list == 1 and list[1]:id() ~= mark.item, #list .. " items")
        click(commands, list[1]:id())
        step("after_reload")

    elseif phase == "after_reload" and clock > 0.4 then
        local at = placed(world)
        local want = standing(0.9)
        T("R5_and_its_click_still_respawns", near(at, want, 0.01), show(at) .. " against " .. show(want))
        phase = "done"
        finish()
    end

    if phase ~= "done" and clock > 10 then
        T("R0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        finish()
    end
end):in_set("zz/respawn/drive")
