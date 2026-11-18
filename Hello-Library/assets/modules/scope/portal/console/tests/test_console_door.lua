-- --host
-- A console's door on a world's server, headless: a pick drives the door's rig (the node above the
-- door carrying `animation/clip`, as a map's is), which `animation/clip` publishes. The scene is
-- stood in as `gltf/mod_registry` leaves it, and the owner's request is written on a player as the
-- net delivers it. Where the rig stands is written by the suite where the server's source of it
-- would.
--
--   DS1 the door stands open as authored, and its rig is published so
--   DS2 a pick closes it from where it stands
--   DS3 ...and once it is published shut, it opens
--   DS4 a pick of its authored branch closes it too
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("PortalConsoleDoorSuite")
local T = suite.assert_test

local ROOT = "github:zzdoors/world"
local HERE = ROOT .. ":main"
local AUTHORED = ROOT .. ":prologue"
local CLIP = "modules/animation/tests/fixtures/Model-Walk.glb#Animation0"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/world/status"] = { scope_key = HERE, scope_root = ROOT, mode = "server", status = "ready" },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    local rig = commands:spawn({
        Name = "zz_rig",
        ["animation/clip"] = { clips = { [CLIP] = 1 }, speed = 0 },
        ["animation/clip/seek"] = { to = "end" },
        Transform = {},
        ["core/net/sync"] = false,
    }):id()
    commands:spawn({
        Name = "zz_door",
        ["scope/portal"] = { target = AUTHORED, at = "zz_arrival" },
        GltfExtras = { value = '{"scope/portal":{"target":"' .. AUTHORED .. '","at":"zz_arrival"}}' },
        Transform = { translation = { x = 0, y = 0, z = -10 } },
        ChildOf = rig,
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["scope/portal/console"] = { door = "zz_door", at = "zz_door" }, ["core/net/sync"] = false })
    commands:spawn({ ["zz/player"] = {}, ["scope/portal/console/user"] = {}, ["core/net/sync"] = {} })
end)

local phase, clock = "loading", 0
local asked = 0

app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "Name", "animation/clip" }, optional = { "animation/clip/seek" } }],
    Query[{ with = { "animation/clip/node" } }],
    Query[{ with = { "zz/player" } }],
    Commands,
}, function(time, rigs, records, players, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local rig
    for _, r in ipairs(rigs:iter()) do
        if r:get("Name").name == "zz_rig" then rig = r end
    end
    local record
    for _, r in ipairs(records:iter()) do
        if r:get("animation/clip/node").name == "zz_rig" then record = r:get("animation/clip/node") end
    end
    local function said()
        local s = rig and rig:get("animation/clip/seek")
        return string.format("speed %s, seek %s, record %s", tostring(rig and rig:get("animation/clip").speed),
            tostring(s and s.to), record and (tostring(record.speed) .. " at " .. tostring(record.time)) or "none")
    end
    local function pick(target)
        asked = asked + 1
        local p = players:iter()[1]
        commands:entity(p:id()):insert({ ["scope/portal/console/request"] = { door = "zz_door", target = target, n = asked } })
    end

    if phase == "loading" then
        if record == nil and clock < 5 then return end
        T("DS1_the_door_stands_open_as_authored_and_is_published_so", rig:get("animation/clip").speed == 0
            and record ~= nil and record.speed == 0 and record.time == "end", said())
        pick(ROOT .. ":feature")
        step("closing")

    elseif phase == "closing" and clock > 0.3 then
        T("DS2_a_pick_closes_it_from_where_it_stands", rig:get("animation/clip").speed == -1
            and rig:get("animation/clip/seek").to == "end" and record.speed == -1, said())
        commands:entity(rig:id()):insert({ ["animation/clip/seek"] = { to = 0 } })
        step("shut")

    elseif phase == "shut" and clock > 1.0 then
        T("DS3_once_published_shut_it_opens", rig:get("animation/clip").speed == 1, said())
        commands:entity(rig:id()):insert({ ["animation/clip/seek"] = { to = "end" } })
        commands:entity(rig:id()):insert({ ["animation/clip"] = { clips = { [CLIP] = 1 }, speed = 0 } })
        step("standing")

    elseif phase == "standing" and clock > 0.3 then
        pick(AUTHORED)
        step("authored")

    elseif phase == "authored" and clock > 0.3 then
        T("DS4_a_pick_of_its_authored_branch_closes_it_too", rig:get("animation/clip").speed == -1, said())
        phase = "done"
        suite.finish("PORTAL_CONSOLE_DOOR")
    end

    if phase ~= "done" and clock > 10 then
        T("DS0_reached_" .. phase, false, said())
        phase = "done"
        suite.finish("PORTAL_CONSOLE_DOOR")
    end
end):in_set("zz/console_door")
