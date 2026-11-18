-- --host (windowed: a headless run advances no clip)
-- A console's door over time on a client: its rig plays the fixture's one-second clip from the
-- synced record, as a map's door plays its own.
--
--   DW1 a pick opens the shut door to its end, and it stays open
--   DW2 a second pick closes it all the way, then opens it to its end again
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local AssetServer = require("bevy::asset::AssetServer")

local suite = helpers.create_suite("PortalConsoleDoorWindowedSuite")
local T = suite.assert_test

-- This VM plays a client world.
world_id = 7

local MODEL = "modules/animation/tests/fixtures/Model"
local CLIP = MODEL .. "-Walk.glb#Animation0"
local ROOT = "github:zzdoorw/world"

app:add_systems(Startup, { Res[AssetServer], Commands }, function(asset_server, commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    local rig = commands:spawn({
        ["zz/rig"] = {},
        SceneRoot = asset_server:load(MODEL .. "-Idle.glb#Scene0"),
        Transform = {},
        ["animation/clip"] = { clips = { [CLIP] = 1 }, speed = 0 },
        ["core/net/sync"] = false,
    }):id()
    commands:spawn({
        Name = "zz_door",
        ["scope/portal"] = { target = ROOT .. ":prologue", at = "zz_arrival" },
        Transform = {},
        ChildOf = rig,
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["scope/portal/console"] = { door = "zz_door", at = "zz_door" }, ["core/net/sync"] = false })
end)

local phase, clock = "loading", 0
local lowest

app:add_systems(Update, {
    World,
    Query[{ with = { "zz/rig", "animation/clip/graph" }, optional = { "animation/clip" } }],
    Query[{ with = { "AnimationPlayer", "AnimationGraphHandle" } }],
    Commands,
}, function(world, rigs, players, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local r = rigs:iter()[1]
    local p = r and players:iter_many(players:iter_descendants(r:id()))[1]
    local a = p and p.AnimationPlayer:animation(r:get("animation/clip/graph").nodes[CLIP]) or nil
    local function said() return a and string.format("at %.3f, speed %s", a.seek_time, tostring(a.speed)) or "not playing" end
    local function record(target)
        local rec = world:query({ with = { "scope/portal/console/target" } })[1]
        local value = { ["scope/portal/console/target"] = { door = "zz_door", target = target, at = "zz_door" } }
        if rec then commands:entity(rec:id()):insert(value) else
            value["core/net/sync"] = false
            commands:spawn(value)
        end
    end

    if phase == "loading" then
        if a == nil and clock < 10 then return end
        record(ROOT .. ":feature")
        step("opening")

    elseif phase == "opening" and clock > 2 then
        T("DW1_a_pick_opens_the_shut_door_to_its_end", a ~= nil and a.seek_time >= 1 and a.completions >= 1, said())
        record(ROOT .. ":other")
        lowest = 1
        step("again")

    elseif phase == "again" then
        if a then lowest = math.min(lowest, a.seek_time) end
        if clock < 3.5 then return end
        T("DW2_a_second_pick_closes_it_all_the_way_then_opens_it_again", lowest <= 0.01 and a ~= nil and a.seek_time >= 1,
            string.format("lowest %.3f, %s", lowest, said()))
        phase = "done"
        suite.finish("PORTAL_CONSOLE_DOOR_WINDOWED")
    end

    if phase ~= "done" and clock > 12 then
        T("DW0_reached_" .. phase, false, said())
        phase = "done"
        suite.finish("PORTAL_CONSOLE_DOOR_WINDOWED")
    end
end):in_set("zz/console_door_windowed")
