-- --host
-- A scene node the server drives, on a client, headless: the server's record (`animation/clip/node`)
-- is spawned here as the net delivers it, and the node as `gltf/mod_registry` leaves a scene's, on
-- the animation fixture's model. Clips advance headless, so a node plays on from where it is put.
--
--   CN1 a record arriving puts its speed on the node and its time in the node's seek, which the
--       node's player takes
--   CN2 a record changing moves the node again
--   CN3 a node arriving after its record (a client joining, a scene landing late) takes it
--   CN4 the client runs no clock: the node's seek stays the server's
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local AssetServer = require("bevy::asset::AssetServer")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("AnimationClipNodeSuite")
local T = suite.assert_test

local MODEL = "modules/animation/tests/fixtures/Model"
local WALK = MODEL .. "-Walk.glb#Animation0"

local function spawn_node(commands, asset_server, name)
    commands:spawn({
        Name = name,
        SceneRoot = asset_server:load(MODEL .. "-Idle.glb#Scene0"),
        ["animation/clip"] = { clips = { [WALK] = 1 }, speed = 0 },
        ["animation/clip/seek"] = { to = "end" },
        Transform = {},
        ["core/net/sync"] = false,
    })
end

local function record(commands, name, speed, time)
    commands:spawn({ ["animation/clip/node"] = { name = name, speed = speed, time = time }, ["core/net/sync"] = false })
end

app:add_systems(Startup, { Res[AssetServer], Commands }, function(asset_server, commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    spawn_node(commands, asset_server, "zz_rig")
end)

local phase, clock = "loading", 0

app:add_systems(Update, {
    Res[Time],
    Res[AssetServer],
    Query[{ with = { "animation/clip", "Name" }, optional = { "animation/clip/seek", "animation/clip/graph" } }],
    Query[{ with = { "animation/clip/node" } }],
    Query[{ with = { "AnimationPlayer", "AnimationGraphHandle" } }],
    Commands,
}, function(time, asset_server, nodes, records, players, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function node(name)
        for _, e in ipairs(nodes:iter()) do
            if e:get("Name").name == name then return e end
        end
    end
    local function at(name)
        local n = node(name)
        local graph = n and n:get("animation/clip/graph")
        local p = n and players:iter_many(players:iter_descendants(n:id()))[1]
        local a = p and graph and p.AnimationPlayer:animation(graph.nodes[WALK])
        return a and a.seek_time or nil
    end
    local function said(name)
        local n = node(name)
        local s = n and n:get("animation/clip/seek")
        return string.format("speed %s, seek %s, playing at %s", tostring(n and n:get("animation/clip").speed),
            tostring(s and s.to), tostring(at(name)))
    end

    if phase == "loading" then
        if at("zz_rig") == nil and clock < 10 then return end
        record(commands, "zz_rig", 0, 0.25)
        step("arrived")

    elseif phase == "arrived" and clock > 0.3 then
        local n = node("zz_rig")
        T("CN1_a_record_puts_its_speed_and_time_on_the_node", n:get("animation/clip").speed == 0
            and n:get("animation/clip/seek").to == 0.25 and math.abs((at("zz_rig") or -1) - 0.25) < 1e-3, said("zz_rig"))
        for _, r in ipairs(records:iter()) do
            commands:entity(r:id()):insert({ ["animation/clip/node"] = { name = "zz_rig", speed = 1, time = 0.6 } })
        end
        step("changed")

    elseif phase == "changed" and clock > 0.3 then
        local n = node("zz_rig")
        T("CN2_a_record_changing_moves_the_node_again", n:get("animation/clip").speed == 1
            and n:get("animation/clip/seek").to == 0.6, said("zz_rig"))
        step("no_clock")

    elseif phase == "no_clock" and clock > 0.5 then
        T("CN4_the_client_runs_no_clock", node("zz_rig"):get("animation/clip/seek").to == 0.6, said("zz_rig"))
        record(commands, "zz_late", -1, 0.4)
        step("record_first")

    elseif phase == "record_first" and clock > 0.3 then
        spawn_node(commands, asset_server, "zz_late")
        step("late")

    elseif phase == "late" and (at("zz_late") ~= nil and clock > 0.3 or clock > 10) then
        local n = node("zz_late")
        -- put at 0.4, it has played back since, at -1
        local now = at("zz_late")
        T("CN3_a_node_arriving_after_its_record_takes_it", n ~= nil and n:get("animation/clip").speed == -1
            and n:get("animation/clip/seek").to == 0.4 and now ~= nil and now < 0.4 and now >= 0, said("zz_late"))
        phase = "done"
        suite.finish("ANIMATION_CLIP_NODE")
    end

    if phase ~= "done" and clock > 12 then
        T("CN0_reached_" .. phase, false, said("zz_rig"))
        phase = "done"
        suite.finish("ANIMATION_CLIP_NODE")
    end
end):in_set("zz/animation_clip_node")
