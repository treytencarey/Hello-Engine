-- --host
-- `animation/clip`'s server half on a world's server, headless: each animated scene node's place,
-- published in a synced record, and a replicated entity's in its own seek. The nodes are stood in
-- as `gltf/mod_registry` leaves a scene's: named, unsynced, their properties inserted. A node with
-- the fixture's scene plays its clip on the server's own AnimationPlayer; one without a player is
-- published from its seek, which the suite writes.
--
--   SC1 each animated scene node gets one record, synced from the server, from where it stands
--   SC2 a node standing still writes nothing
--   SC3 a moving node's record is written about twice a second
--   SC4 a speed set on a node (as a console does) is published at once, from where it stands
--   SC5 a moving node's record carries where the node stands now
--   SC6 a reload of the server half keeps one record a node
--   SC7 a node gone takes its record
--   SC8 a node with a player is published where its player really stands
--   SC9 a replicated entity gets no record: its own seek is written, from its player
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")
local AssetServer = require("bevy::asset::AssetServer")

local suite = helpers.create_suite("AnimationClipServerSuite")
local T = suite.assert_test

local MODEL = "modules/animation/tests/fixtures/Model"
local WALK = MODEL .. "-Walk.glb#Animation0"
local IDLE = MODEL .. "-Idle.glb#Animation0"
local SERVER = "assets/modules/animation/clip/server/init.lua"

app:add_systems(Startup, { Res[AssetServer], Commands }, function(asset_server, commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        Name = "zz_real",
        SceneRoot = asset_server:load(MODEL .. "-Idle.glb#Scene0"),
        ["animation/clip"] = { clips = { [WALK] = 1 }, speed = 1 },
        Transform = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["zz/replicated"] = {},
        Name = "zz_moved",
        SceneRoot = asset_server:load(MODEL .. "-Idle.glb#Scene0"),
        ["animation/clip"] = { clips = { [WALK] = 1 }, speed = 1, ["repeat"] = true },
        Transform = {},
        ["core/net/sync"] = {
            ["animation/clip"] = { authority = "server" },
            ["animation/clip/seek"] = { authority = "server" },
        },
    })
    commands:spawn({
        Name = "zz_rig",
        ["animation/clip"] = { clips = { [WALK] = 1 }, speed = 0 },
        ["animation/clip/seek"] = { to = "end" },
        Transform = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({
        Name = "zz_fan",
        ["animation/clip"] = { clips = { [IDLE] = 1 }, speed = 2, ["repeat"] = true },
        Transform = {},
        ["core/net/sync"] = false,
    })
end)

-- The nodes and records, from the suite system's own queries this frame.
local nodes_q, records_q

local function node(name)
    for _, e in ipairs(nodes_q:iter()) do
        if e:get("Name").name == name then return e end
    end
end

local function records(name)
    local out = {}
    for _, r in ipairs(records_q:iter()) do
        if r:get("animation/clip/node").name == name then out[#out + 1] = r end
    end
    return out
end

local phase, clock = "loading", 0
local writes = { zz_rig = 0, zz_fan = 0 }

app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "animation/clip", "Name" }, optional = { "animation/clip/seek" } }],
    Query[{ with = { "animation/clip/node" }, optional = { "core/net/sync" } }],
    Query[{ changed = { "animation/clip/node" } }],
    Commands,
}, function(time, nq, rq, changed, commands)
    nodes_q, records_q = nq, rq
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    for _, r in ipairs(changed:iter()) do
        local name = r:get("animation/clip/node").name
        writes[name] = (writes[name] or 0) + 1
    end
    local function said(name)
        local r = records(name)[1]
        local v = r and r:get("animation/clip/node") or {}
        local n = node(name)
        local s = n and n:get("animation/clip/seek")
        return string.format("record speed %s time %s, seek %s, %d records", tostring(v.speed), tostring(v.time),
            tostring(s and s.to), #records(name))
    end
    local function value(name)
        local r = records(name)[1]
        return r and r:get("animation/clip/node") or {}
    end

    if phase == "loading" then
        if #records("zz_rig") == 0 and clock < 5 then return end
        local r = records("zz_rig")[1]
        local sync = r and r:get("core/net/sync") or {}
        T("SC1_a_node_gets_one_record_synced_from_the_server_from_where_it_stands", #records("zz_rig") == 1
            and #records("zz_fan") == 1 and value("zz_rig").speed == 0 and value("zz_rig").time == "end"
            and value("zz_fan").speed == 2 and value("zz_fan").time == 0
            and (sync["animation/clip/node"] or {}).authority == "server", said("zz_rig"))
        writes = { zz_rig = 0, zz_fan = 0 }
        step("running")

    elseif phase == "running" and clock > 2 then
        T("SC2_a_node_standing_still_writes_nothing", writes.zz_rig == 0, tostring(writes.zz_rig) .. " writes")
        T("SC3_a_moving_nodes_record_is_written_about_twice_a_second", writes.zz_fan >= 3 and writes.zz_fan <= 5,
            tostring(writes.zz_fan) .. " writes in 2 s")
        -- a one-second clip, started 2 s ago and holding its end
        T("SC8_a_node_with_a_player_is_published_where_its_player_stands", type(value("zz_real").time) == "number"
            and value("zz_real").time > 0.95, said("zz_real"))
        local moved = node("zz_moved")
        local seek = moved and moved:get("animation/clip/seek")
        T("SC9_a_replicated_entity_gets_no_record_its_own_seek_is_written_from_its_player", #records("zz_moved") == 0
            and seek ~= nil and type(seek.to) == "number" and seek.to > 0 and seek.to < 1,
            tostring(#records("zz_moved")) .. " records, seek " .. tostring(seek and seek.to))
        commands:entity(node("zz_rig"):id()):insert({ ["animation/clip"] = { clips = { [WALK] = 1 }, speed = -1 } })
        step("closing")

    elseif phase == "closing" and clock > 0.2 and not seen_close then
        seen_close = true
        T("SC4_a_speed_set_is_published_at_once_from_where_it_stands", value("zz_rig").speed == -1
            and value("zz_rig").time == "end", said("zz_rig"))
        commands:entity(node("zz_rig"):id()):insert({ ["animation/clip/seek"] = { to = 0.3 } })

    elseif phase == "closing" and clock > 1.0 then
        T("SC5_a_moving_nodes_record_carries_where_it_stands_now", value("zz_rig").time == 0.3, said("zz_rig"))
        write_file_bytes(SERVER, read_file_bytes(SERVER))
        step("reloaded")

    elseif phase == "reloaded" and clock > 2 then
        T("SC6_a_reload_keeps_one_record_a_node", #records("zz_rig") == 1 and #records("zz_fan") == 1, said("zz_rig"))
        commands:entity(node("zz_fan"):id()):despawn()
        step("gone")

    elseif phase == "gone" and clock > 0.3 then
        T("SC7_a_node_gone_takes_its_record", #records("zz_fan") == 0 and #records("zz_rig") == 1, said("zz_fan"))
        phase = "done"
        suite.finish("ANIMATION_CLIP_SERVER")
    end

    if phase ~= "done" and clock > 10 then
        T("SC0_reached_" .. phase, false, said("zz_rig"))
        phase = "done"
        suite.finish("ANIMATION_CLIP_SERVER")
    end
end):in_set("zz/animation_clip_server")
