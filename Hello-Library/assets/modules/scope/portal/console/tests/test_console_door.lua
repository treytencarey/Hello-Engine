-- --host
-- A console's door on a client, headless: its rig (the node above the door carrying
-- `animation/clip`, as a map's is) plays from the synced record. No clip advances headless, so where
-- a clip stands is moved by the suite where time would move it.
--
--   DR1 a door arriving stands open, at its clip's end, with no record naming it
--   DR2 a pick closes it from where it stands
--   DR3 ...and once it is shut, it opens
--   DR4 pointing it back at its authored target (the record going) closes and opens it too
--   DR5 a door whose record stood before it arrived (a client joining) stands open at its end
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local AssetServer = require("bevy::asset::AssetServer")

local suite = helpers.create_suite("PortalConsoleDoorSuite")
local T = suite.assert_test

-- This VM plays a client world.
world_id = 7

local MODEL = "modules/animation/tests/fixtures/Model"
local CLIP = MODEL .. "-Walk.glb#Animation0"
local ROOT = "github:zzdoor/world"

local function spawn_door(commands, asset_server, name, x)
    local rig = commands:spawn({
        ["zz/rig"] = { name = name },
        SceneRoot = asset_server:load(MODEL .. "-Idle.glb#Scene0"),
        Transform = { translation = { x = x, y = 0, z = 0 } },
        ["animation/clip"] = { clips = { [CLIP] = 1 }, speed = 0 },
        ["core/net/sync"] = false,
    }):id()
    commands:spawn({
        Name = name,
        ["scope/portal"] = { target = ROOT .. ":prologue", at = "zz_arrival" },
        Transform = {},
        ChildOf = rig,
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["scope/portal/console"] = { door = name, at = name }, ["core/net/sync"] = false })
end

app:add_systems(Startup, { Res[AssetServer], Commands }, function(asset_server, commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    spawn_door(commands, asset_server, "zz_door", 0)
end)

local seeks = {}

-- Where time would move the clip: the suite seeks the rig's player.
app:add_systems(Update, {
    Query[{ with = { "zz/rig", "animation/clip/graph" } }],
    Query[{ with = { Mut["AnimationPlayer"], "AnimationGraphHandle" } }],
}, function(rigs, players)
    for _, r in ipairs(rigs:iter()) do
        local at = seeks[r:get("zz/rig").name]
        if at ~= nil then
            local p = players:iter_many_mut(players:iter_descendants(r:id()))[1]
            if p then
                p.AnimationPlayer:play(r:get("animation/clip/graph").nodes[CLIP], { seek_to = at })
                seeks[r:get("zz/rig").name] = nil
            end
        end
    end
end):in_set("zz/console_door_seek"):before("scope/portal/console/client")

local phase, clock = "loading", 0

app:add_systems(Update, {
    World,
    Res[AssetServer],
    Query[{ with = { "zz/rig" }, optional = { "animation/clip", "animation/clip/graph" } }],
    Query[{ with = { "AnimationPlayer", "AnimationGraphHandle" } }],
    Commands,
}, function(world, asset_server, rigs, players, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function rig(name)
        for _, r in ipairs(rigs:iter()) do
            if r:get("zz/rig").name == name then return r end
        end
    end
    local function clip(name)
        local r = rig(name)
        return r and r:get("animation/clip") or {}
    end
    local function active(name)
        local r = rig(name)
        local p = r and players:iter_many(players:iter_descendants(r:id()))[1]
        local graph = r and r:get("animation/clip/graph")
        return p and graph and p.AnimationPlayer:animation(graph.nodes[CLIP]) or nil
    end
    local function said(name)
        local a = active(name)
        local c = clip(name)
        return string.format("speed %s, seek_to %s, %s", tostring(c.speed), tostring(c.seek_to),
            a and ("at " .. a.seek_time) or "not playing")
    end
    local function open_at_end(name)
        local a, c = active(name), clip(name)
        return c.speed == 1 and c.seek_to == "end" and c["repeat"] == false and a ~= nil and math.abs(a.seek_time - 1) < 1e-3
    end
    local function record(target)
        local r = world:query({ with = { "scope/portal/console/target" } })[1]
        if r then
            commands:entity(r:id()):insert({ ["scope/portal/console/target"] = { door = "zz_door", target = target, at = "zz_door" } })
        else
            commands:spawn({
                ["scope/portal/console/target"] = { door = "zz_door", target = target, at = "zz_door" },
                ["core/net/sync"] = false,
            })
        end
    end

    if phase == "loading" then
        if active("zz_door") == nil and clock < 10 then return end
        step("arrived")

    elseif phase == "arrived" and clock > 0.5 then
        T("DR1_a_door_arriving_stands_open_at_its_clips_end", open_at_end("zz_door"), said("zz_door"))
        record(ROOT .. ":feature")
        step("closing")

    elseif phase == "closing" and clock > 0.3 then
        local a = active("zz_door")
        T("DR2_a_pick_closes_it_from_where_it_stands", clip("zz_door").speed == -1 and clip("zz_door").seek_to == nil
            and a ~= nil and math.abs(a.seek_time - 1) < 1e-3, said("zz_door"))
        seeks.zz_door = 0
        step("reopening")

    elseif phase == "reopening" and clock > 0.3 then
        T("DR3_once_shut_it_opens", clip("zz_door").speed == 1, said("zz_door"))
        seeks.zz_door = 1
        step("authored")

    elseif phase == "authored" and clock > 0.3 then
        for _, r in ipairs(world:query({ with = { "scope/portal/console/target" } })) do commands:entity(r:id()):despawn() end
        step("authored_closing")

    elseif phase == "authored_closing" and clock > 0.3 then
        T("DR4_pointing_it_back_closes_it_too", clip("zz_door").speed == -1, said("zz_door"))
        seeks.zz_door = 0
        step("authored_reopening")

    elseif phase == "authored_reopening" and clock > 0.3 then
        T("DR4_and_opens_it", clip("zz_door").speed == 1, said("zz_door"))
        -- a door named by a record already standing, as a client joining finds it
        commands:spawn({
            ["scope/portal/console/target"] = { door = "zz_late", target = ROOT .. ":feature", at = "zz_late" },
            ["core/net/sync"] = false,
        })
        spawn_door(commands, asset_server, "zz_late", 10)
        step("late")

    elseif phase == "late" and (active("zz_late") ~= nil and clock > 0.5 or clock > 10) then
        T("DR5_a_door_joined_late_stands_open_at_its_end", open_at_end("zz_late"), said("zz_late"))
        phase = "done"
        suite.finish("PORTAL_CONSOLE_DOOR")
    end

    if phase ~= "done" and clock > 12 then
        T("DR0_reached_" .. phase, false, said("zz_door"))
        phase = "done"
        suite.finish("PORTAL_CONSOLE_DOOR")
    end
end):in_set("zz/console_door")
