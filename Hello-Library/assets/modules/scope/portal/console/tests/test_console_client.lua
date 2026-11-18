-- --host
-- A console's client half, headless: this client's copy of the door follows the server's record.
-- The door and the console are stood in as `gltf/mod_registry` leaves them (the door's custom
-- properties in its `GltfExtras`), and each record is spawned as the net delivers it.
--
--   C1 a record re-points this client's door copy at its target and `at`
--   C2 a changed record moves the door with it
--   C3 the record gone, the door takes its authored target and `at` again
--   C4 a door that arrives after its record (a scene that lands late, or is written again) takes it
--   C5 a door authored without `target` takes a record's target
--   C6 ...and the record gone, it has no target again
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("PortalConsoleClientSuite")
local T = suite.assert_test

local ROOT = "github:zzconc/world"
local AUTHORED = ROOT .. ":prologue"
local FEATURE = ROOT .. ":feature"
local OTHER = ROOT .. ":other"

local function door(name)
    return {
        Name = name,
        ["scope/portal"] = { target = AUTHORED, at = "zz_arrival" },
        GltfExtras = { value = '{"scope/portal":{"target":"' .. AUTHORED .. '","at":"zz_arrival"}}' },
        Transform = { translation = { x = 0, y = 0, z = -10 } },
        ["core/net/sync"] = false,
    }
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    -- A world's row, which only watches: a door's view then asks root nothing.
    commands:spawn({
        ["core/world/status"] = { scope_key = ROOT .. ":main", mode = "client", status = "ready", observer = true },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    commands:spawn(door("zz_door"))
    commands:spawn({ ["scope/portal/console"] = { door = "zz_door", at = "zz_door" }, ["core/net/sync"] = false })
    commands:spawn({
        Name = "zz_blank",
        ["scope/portal"] = { at = "zz_arrival" },
        GltfExtras = { value = '{"scope/portal":{"at":"zz_arrival"}}' },
        Transform = { translation = { x = 4, y = 0, z = -10 } },
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["scope/portal/console"] = { door = "zz_blank", at = "zz_blank" }, ["core/net/sync"] = false })
end)

local function portal(world, name)
    for _, e in ipairs(world:query({ with = { "scope/portal", "Name" } })) do
        if e:get("Name").name == name then return e:get("scope/portal") end
    end
end

local function show(p) return p and (tostring(p.target) .. " @ " .. tostring(p.at)) or "none" end

local function record(world, name)
    for _, e in ipairs(world:query({ with = { "scope/portal/console/target" } })) do
        if e:get("scope/portal/console/target").door == name then return e end
    end
end

local phase, clock = "start", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "start" and clock > 0.5 then
        commands:spawn({
            ["scope/portal/console/target"] = { door = "zz_door", target = FEATURE, at = "zz_door" },
            ["core/net/sync"] = false,
        })
        step("c1")

    elseif phase == "c1" and (show(portal(world, "zz_door")) ~= AUTHORED .. " @ zz_arrival" or clock > 3) then
        T("C1_a_record_re_points_the_door_copy", show(portal(world, "zz_door")) == FEATURE .. " @ zz_door",
            show(portal(world, "zz_door")))
        commands:entity(record(world, "zz_door"):id()):entry("scope/portal/console/target"):and_modify(function(r)
            r.target = OTHER
        end)
        step("c2")

    elseif phase == "c2" and (show(portal(world, "zz_door")) ~= FEATURE .. " @ zz_door" or clock > 3) then
        T("C2_a_changed_record_moves_the_door", show(portal(world, "zz_door")) == OTHER .. " @ zz_door",
            show(portal(world, "zz_door")))
        commands:entity(record(world, "zz_door"):id()):despawn()
        step("c3")

    elseif phase == "c3" and (show(portal(world, "zz_door")) ~= OTHER .. " @ zz_door" or clock > 3) then
        T("C3_the_record_gone_the_door_is_authored_again", show(portal(world, "zz_door")) == AUTHORED .. " @ zz_arrival",
            show(portal(world, "zz_door")))
        commands:spawn({
            ["scope/portal/console/target"] = { door = "zz_late", target = FEATURE, at = "zz_late" },
            ["core/net/sync"] = false,
        })
        step("c4 recorded")

    elseif phase == "c4 recorded" and clock > 0.5 then
        commands:spawn(door("zz_late"))
        step("c4")

    elseif phase == "c4" and (show(portal(world, "zz_late")) == FEATURE .. " @ zz_late" or clock > 3) then
        T("C4_a_door_arriving_after_its_record_takes_it", show(portal(world, "zz_late")) == FEATURE .. " @ zz_late"
            and show(portal(world, "zz_door")) == AUTHORED .. " @ zz_arrival", show(portal(world, "zz_late")))
        commands:spawn({
            ["scope/portal/console/target"] = { door = "zz_blank", target = FEATURE, at = "zz_blank" },
            ["core/net/sync"] = false,
        })
        step("c5")

    elseif phase == "c5" and (show(portal(world, "zz_blank")) == FEATURE .. " @ zz_blank" or clock > 3) then
        T("C5_a_door_authored_without_target_takes_a_record_s_target", show(portal(world, "zz_blank")) == FEATURE .. " @ zz_blank",
            show(portal(world, "zz_blank")))
        commands:entity(record(world, "zz_blank"):id()):despawn()
        step("c6")

    elseif phase == "c6" and (show(portal(world, "zz_blank")) ~= FEATURE .. " @ zz_blank" or clock > 3) then
        T("C6_the_record_gone_it_has_no_target_again", show(portal(world, "zz_blank")) == "nil @ zz_arrival",
            show(portal(world, "zz_blank")))
        phase = "done"
        suite.finish("PORTAL_CONSOLE_CLIENT")
    end

    if phase ~= "done" and clock > 10 then
        T("C0_reached_" .. phase, false, "stuck in phase '" .. phase .. "'")
        phase = "done"
        suite.finish("PORTAL_CONSOLE_CLIENT")
    end
end):in_set("zz/console_client")
