-- --host
-- Flight on a real player, driven headless: the world's client adds `movement/fly` beside what
-- `player/client` adds, keys go through `input` as a device-less source writes them, and the menu's
-- items are clicked as Bevy's picking triggers a click. The body is the spawner's capsule, dynamic
-- as its owner has it, standing on a floor under gravity.
--
--   F1 F, Space and ShiftLeft are bound in the `fly` group, and flight starts off
--   F2 F turns flight on: no gravity, so the body hovers; F again turns it off, flight's scale goes,
--      `player/client` puts its 1 back, and it falls
--   F3 while it flies, Space climbs and ShiftLeft sinks at movement's speed, and the floor still
--      stops it
--   F4 the menu holds Flight and No-clip, showing the state
--   F5 No-clip turns flight on too and makes the body a sensor: it sinks through the floor
--   F6 flight off turns no-clip off: no sensor and gravity again, and the floor stops it
--   F7 a reload of the mod: two new items showing the state, and flight still flying
--   F8 `movement/fly` taken off while it flies: no-clip and flight's scale go, the player's 1 comes
--      back and the body falls to the floor, and its keys are unbound; taken off while it does not
--      fly, the player's scale stays
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local bevy = require("bevy::prelude")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")

local suite = helpers.create_suite("FlySuite")
local T = suite.assert_test

local MOD_FILE = "assets/modules/movement/fly/init.lua"
local original

local function finish()
    if original ~= nil then
        write_file_bytes(MOD_FILE, original)
    end
    suite.finish("FLY")
end

local camera, player

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    camera = commands:spawn({ ["zz/camera"] = {} }):id()
    commands:spawn({
        ["zz/floor"] = {},
        Transform = { translation = { x = 0, y = -0.1, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 50, hy = 0.1, hz = 50 } },
        ["core/net/sync"] = false,
    })
    -- The player as it arrives from the server, with what the server adds that flight reads.
    player = commands:spawn({
        ["zz/player"] = {},
        player = { client_id = 1 },
        movement = {},
        camera = { yaw = 0 },
        ["core/net/sync"] = false,
        Transform = { translation = { x = 0, y = 0.9, z = 0 } },
        RigidBody3d = "KinematicPositionBased",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
        Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
    }):id()
end)

local reloads = 0
app:add_systems(Update, { bevy.MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("movement/fly/init.lua", 1, true) then
            reloads = reloads + 1
        end
    end
end):in_set("zz/fly/reload_watch")

local keys = {}
local function key(code, state) keys[#keys + 1] = { key_code = code, state = state } end

app:add_systems(Update, { bevy.MessageWriter["input/synthetic_key"] }, function(write)
    for _, m in ipairs(keys) do write:write(m) end
    keys = {}
end):in_set("zz/fly/keys")

local function me(world)
    return world:query({
        with = { "zz/player" },
        optional = {
            "movement/fly", "GravityScale3d", "Sensor3d", "Velocity3d", "input/game", "RigidBody3d",
            "input/game/fly/up", "input/game/fly/down",
        },
    })[1]
end

local function height(world)
    return world:get_entity(player).GlobalTransform:compute_transform().translation.y
end

local function fly_of(world)
    return me(world):get("movement/fly") or {}
end

local function menu_button(world)
    return world:query({ with = { "sidebar/menu/button", "Button" } })[1]
end

-- The menu's items for flight, by field, with their labels.
local function items(world)
    local out, count = {}, 0
    for _, e in ipairs(world:query({
        with = { "movement/fly/item", "sidebar/menu/item" },
        optional = { "Text", "Button", "ChildOf" },
    })) do
        out[e:get("movement/fly/item").field] = e
        count = count + 1
    end
    return out, count
end

local function label(item)
    return item ~= nil and item:get("Text") or "none"
end

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

-- `GravityScale3d` reads back as its number.
local function scale_of(p)
    return p:has("GravityScale3d") and p:get("GravityScale3d") or nil
end

local phase, clock = "arrived", 0
local mark = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    -- The net client marks its own player local frames after it arrives; the world's client half
    -- adds flight to it.
    if phase == "arrived" and clock > 0.3 then
        commands:entity(player):insert({ ["core/net/local"] = {}, ["movement/fly"] = {} })
        step("bound")

    elseif phase == "bound" and clock > 0.5 then
        local p = me(world)
        local game = p:get("input/game") or {}
        local fly = game.fly or {}
        T("F1_its_keys_are_bound_in_the_fly_group", fly.toggle ~= nil and fly.toggle.key == "KeyF"
            and fly.up ~= nil and fly.up.key == "Space" and fly.down ~= nil and fly.down.key == "ShiftLeft")
        local state = fly_of(world)
        T("F1_flight_starts_off_with_the_player_s_scale_of_1", state.on == false and state.noclip == false
            and scale_of(p) == 1 and not p:has("Sensor3d"), tostring(scale_of(p)))
        T("F1_the_body_is_the_owner_s_dynamic_one_standing_on_the_floor",
            p:get("RigidBody3d") == "Dynamic" and math.abs(height(world) - 0.9) < 0.05, tostring(height(world)))
        key("KeyF", "Pressed")
        step("toggle_pressed")

    elseif phase == "toggle_pressed" and clock > 0.1 then
        key("KeyF", "Released")
        step("flying")

    elseif phase == "flying" and clock > 0.3 then
        local p = me(world)
        T("F2_f_turns_flight_on_with_no_gravity", fly_of(world).on == true and scale_of(p) == 0, tostring(scale_of(p)))
        key("Space", "Pressed")
        mark.from = height(world)
        step("climbing")

    elseif phase == "climbing" and clock > 0.5 then
        local p = me(world)
        local vy = p:get("Velocity3d").linvel.y
        T("F3_space_climbs_at_movement_s_speed", math.abs(vy - 6) < 1e-3 and height(world) > mark.from + 1,
            string.format("vy %.3f from %.3f to %.3f", vy, mark.from, height(world)))
        key("Space", "Released")
        step("released")

    elseif phase == "released" and clock > 0.2 then
        mark.hover = height(world)
        step("hovering")

    elseif phase == "hovering" and clock > 0.5 then
        T("F2_with_no_key_it_hovers", math.abs(height(world) - mark.hover) < 0.02 and mark.hover > 2,
            string.format("from %.3f to %.3f", mark.hover, height(world)))
        key("ShiftLeft", "Pressed")
        step("sinking")

    elseif phase == "sinking" and clock > 0.1 then
        local vy = me(world):get("Velocity3d").linvel.y
        mark.sinking = vy
        step("landed")

    elseif phase == "landed" and clock > 1.5 then
        T("F3_shift_sinks_at_movement_s_speed", math.abs(mark.sinking + 6) < 1e-3, tostring(mark.sinking))
        T("F3_and_the_floor_still_stops_it", math.abs(height(world) - 0.9) < 0.05, tostring(height(world)))
        key("ShiftLeft", "Released")
        key("Space", "Pressed")
        step("up_again")

    elseif phase == "up_again" and clock > 0.4 then
        key("Space", "Released")
        key("KeyF", "Pressed")
        step("toggle_off")

    elseif phase == "toggle_off" and clock > 0.1 then
        key("KeyF", "Released")
        mark.from = height(world)
        step("falling")

    elseif phase == "falling" and clock > 2.5 then
        local p = me(world)
        T("F2_f_again_turns_it_off_with_the_scale_back_at_1_and_it_falls_to_the_floor", fly_of(world).on == false
            and scale_of(p) == 1 and mark.from > 2 and math.abs(height(world) - 0.9) < 0.05,
            string.format("scale %s from %.3f to %.3f", tostring(scale_of(p)), mark.from, height(world)))
        click(commands, menu_button(world):id())
        step("menu")

    elseif phase == "menu" and clock > 0.2 then
        local list, count = items(world)
        if count == 2 and list.on:has("Text") and list.noclip:has("Text") then
            local holder = world:query({ with = { "sidebar/menu/list" } })[1]
            T("F4_the_menu_holds_flight_and_no_clip", holder ~= nil and list.on:get("ChildOf") == holder:id()
                and list.noclip:get("ChildOf") == holder:id() and list.on:has("Button") and list.noclip:has("Button"))
            T("F4_showing_the_state", label(list.on) == "Flight: Off" and label(list.noclip) == "No-clip: Off",
                label(list.on) .. " / " .. label(list.noclip))
            click(commands, list.noclip:id())
            step("noclip")
        end

    elseif phase == "noclip" and clock > 0.3 then
        local p = me(world)
        local state = fly_of(world)
        T("F5_no_clip_turns_flight_on_too", state.noclip == true and state.on == true and scale_of(p) == 0,
            string.format("on %s noclip %s", tostring(state.on), tostring(state.noclip)))
        T("F5_and_makes_the_body_a_sensor", p:has("Sensor3d"))
        local list = items(world)
        T("F4_the_items_follow_the_state", label(list.on) == "Flight: On" and label(list.noclip) == "No-clip: On",
            label(list.on) .. " / " .. label(list.noclip))
        key("ShiftLeft", "Pressed")
        step("through")

    elseif phase == "through" and clock > 0.6 then
        T("F5_it_sinks_through_the_floor", height(world) < -1, tostring(height(world)))
        key("ShiftLeft", "Released")
        key("Space", "Pressed")
        step("back_up")

    elseif phase == "back_up" and clock > 0.8 then
        key("Space", "Released")
        mark.from = height(world)
        click(commands, items(world).on:id())
        step("flight_off")

    elseif phase == "flight_off" and clock > 2.5 then
        local p = me(world)
        local state = fly_of(world)
        T("F6_flight_off_turns_no_clip_off", state.on == false and state.noclip == false
            and not p:has("Sensor3d") and scale_of(p) == 1,
            string.format("on %s noclip %s", tostring(state.on), tostring(state.noclip)))
        T("F6_and_the_floor_stops_it_again", mark.from > 1.5 and math.abs(height(world) - 0.9) < 0.05,
            string.format("from %.3f to %.3f", mark.from, height(world)))
        local list = items(world)
        T("F6_the_items_show_it", label(list.on) == "Flight: Off" and label(list.noclip) == "No-clip: Off",
            label(list.on) .. " / " .. label(list.noclip))
        click(commands, list.on:id())
        step("flying_for_reload")

    elseif phase == "flying_for_reload" and clock > 0.3 then
        local list = items(world)
        mark.on_item, mark.noclip_item = list.on:id(), list.noclip:id()
        mark.reloads = reloads
        original = read_file_bytes(MOD_FILE)
        write_file_bytes(MOD_FILE, original .. "\n-- zz 1\n")
        step("reloading")

    elseif phase == "reloading" and reloads > mark.reloads then
        step("reloaded")

    elseif phase == "reloaded" and clock > 1 then
        local list, count = items(world)
        if count > 0 and list.on ~= nil and list.on:has("Text") then
            local p = me(world)
            T("F7_a_reload_leaves_two_new_items_showing_the_state", count == 2 and list.on:id() ~= mark.on_item
                and list.noclip ~= nil and list.noclip:id() ~= mark.noclip_item
                and label(list.on) == "Flight: On" and label(list.noclip) == "No-clip: Off",
                count .. " items, " .. label(list.on) .. " / " .. label(list.noclip))
            T("F7_and_it_still_flies", fly_of(world).on == true and scale_of(p) == 0)
            key("Space", "Pressed")
            mark.from = height(world)
            step("climbing_after_reload")
        end

    elseif phase == "climbing_after_reload" and clock > 0.4 then
        T("F7_space_still_climbs", height(world) > mark.from + 1,
            string.format("from %.3f to %.3f", mark.from, height(world)))
        key("Space", "Released")
        click(commands, items(world).noclip:id())
        step("noclip_for_removal")

    elseif phase == "noclip_for_removal" and clock > 0.3 then
        local p = me(world)
        if p:has("Sensor3d") and scale_of(p) == 0 then
            mark.from = height(world)
            commands:entity(player):remove("movement/fly")
            step("removed_flying")
        end

    elseif phase == "removed_flying" and clock > 2.5 then
        local p = me(world)
        local game = p:get("input/game") or {}
        T("F8_taken_off_while_it_flies_no_clip_goes_and_the_player_s_scale_comes_back",
            not p:has("movement/fly") and not p:has("Sensor3d") and scale_of(p) == 1, tostring(scale_of(p)))
        T("F8_and_the_body_falls_to_the_floor", mark.from > 1.5 and math.abs(height(world) - 0.9) < 0.05,
            string.format("from %.3f to %.3f", mark.from, height(world)))
        T("F8_and_its_keys_are_unbound", game.fly == nil and game.movement ~= nil)
        commands:entity(player):insert({ ["movement/fly"] = {} })
        step("back_off")

    elseif phase == "back_off" and clock > 0.5 then
        local game = me(world):get("input/game") or {}
        if game.fly ~= nil then
            commands:entity(player):remove("movement/fly")
            step("removed_off")
        end

    elseif phase == "removed_off" and clock > 0.5 then
        local p = me(world)
        local game = p:get("input/game") or {}
        T("F8_taken_off_while_it_does_not_fly_the_player_s_scale_stays", scale_of(p) == 1 and game.fly == nil,
            tostring(scale_of(p)))
        phase = "done"
        finish()
    end

    if phase ~= "done" and clock > 10 then
        T("F0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        finish()
    end
end):in_set("zz/fly/drive")
