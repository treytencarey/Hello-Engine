-- --host
-- A client's player coming back through a door, as its client gets it, over real connections. Two
-- server worlds, A and B, each in its own VM with a spawner and a point, each with a door linking
-- to the other: two joins, so the player leaves by one and comes back by the other, and each world
-- holds the other's player on the join it held none on. Their players are first person, as
-- Backrooms' are. This VM is the client's world of A; another VM is its world of B, only watching
-- at first. Each switch is the one a portal writes, and each world's presence follows as root's
-- flip sends it. Every return here is predicted: root's ask arrives stubbed, an entity carrying
-- `WorldMirror { world_id = 0 }`, at the door's node, before the switch, and stays once done.
--
--   RC1 the client's player in A is its own, its body dynamic
--   RC2 handed to B: B's player is the client's there, and A's copy is not its own here
--   RD1 back by the other door: A's player is its own again, its stand-in replaced
--   RD2 to B again: B's player is the client's there
--   RS1 the second return stands the player in here, beside the first return's done ask
--   RS2 the real player arriving takes the stand-in's place before the crossing is done
--   RC3 handed back: A's player is its own here again, the same entity, its body dynamic
--   RC4 ...and B's player is not the client's there
--   RS3 once done, the eye added last, which the screen shows, is the real player's, and on
require("modules/core/init.lua")
require("modules/core/net/client/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Net = require("modules/core/net/shared/net.lua")
local suite = helpers.create_suite("PlayerReturnDoorClientSuite")
local T = suite.assert_test
local reg = helpers.peer_registry()

local A_PORT, B_PORT, PLAYER = 15981, 15984, 41
local A, B = "zz:rd:a", "zz:rd:b"
local DEFAULTS = { a_ready = false, b_ready = false, a_linked = false, b_linked = false, to_b = 0, to_a = 0,
    b_net = false, b_owned = false, b_present = "", a_srv = "", b_srv = "" }
local ts = helpers.shared_state("ZzReturnDoorClientState", DEFAULTS)

local SERVER = [=[
require("modules/core/net/server/init.lua")
require("modules/core/net/peer/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local Net = require("modules/core/net/shared/net.lua")
local boot = Instances.boot_data()
local ts = helpers.shared_state("ZzReturnDoorClientState", boot.DEFAULTS)
app:add_systems(Startup, { World, Commands }, function(world, commands)
    Net.declare_ownership(world, commands)
    commands:spawn({ ["core/world/net"] = { mode = "server", name = boot.NAME, port = boot.PORT },
        ["core/net"] = { mode = "server", name = boot.NAME, port = boot.PORT }, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/listen"] = { name = boot.NAME .. "_peer", port = boot.PORT + 1, scope_key = boot.SCOPE,
        world_port = boot.PORT }, ["core/net/peer"] = {}, ["core/net/sync"] = false })
    commands:spawn({ ["core/net/peer/expose"] = { components = "all" }, ["core/net/peer/accept"] = { components = "all" },
        ["core/net/sync"] = false })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({ Name = "zz_rc", Transform = {}, ["player/spawner/point"] = {}, ["core/net/sync"] = false })
    -- Where the other world's door leads here.
    commands:spawn({ Name = boot.HERE, Transform = { translation = { x = 4, y = 0, z = 2 } }, ["core/net/sync"] = false })
    commands:spawn({ Transform = { translation = { x = 0, y = -0.5, z = 0 } }, RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 20, hy = 0.5, hz = 20 } }, ["core/net/sync"] = false })
    if boot.LINK then
        commands:spawn({ ["core/net/peer/link"] = { name = boot.NAME .. "_link", port = boot.LINK, scope_key = boot.OTHER,
            server_addr = "127.0.0.1", at = boot.THERE }, ["core/net/sync"] = false })
    end
end)
local switched = 0
-- A first-person world, as Backrooms' player mod makes one: first person goes in whenever the
-- library's third person is there, and takes the base over.
app:add_systems(First, {
    Query[{
        ["or"] = { added = { "player", "camera/3d", "camera/third_person" }, removed = { "camera/first_person" } },
        with = { "player" },
        optional = { "camera/third_person" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(players, commands)
    for _, e in ipairs(players:iter()) do
        if e:has("camera/third_person") then
            commands:entity(e:id()):entry("camera/first_person"):or_insert({})
        end
    end
end):in_set("zz/rd_first_person")
app:add_systems(Update, { World, Commands }, function(world, commands)
    ts[boot.KEY .. "_ready"] = true
    local l = world:query({ with = { "core/net/peer/link", "core/net/peer/link/state" } })[1]
    if l then ts[boot.KEY .. "_linked"] = l:get("core/net/peer/link/state").welcomed == true end
    local rows = {}
    for _, p in ipairs(world:query({ with = { "player" }, optional = { "core/net/owner", "core/net/peer/mirror" } })) do
        local m = p:get("core/net/peer/mirror")
        rows[#rows + 1] = string.format("%s:%s%s", tostring(p:id()), p:has("core/net/owner") and "owned" or "unowned",
            m and ((m.was_source and "/was_source" or "/mirror") .. "@" .. tostring(m.via)) or "")
    end
    ts[boot.KEY .. "_srv"] = table.concat(rows, " ")
    -- The switch a portal writes on the player walking in.
    if ts[boot.SWITCH] > switched then
        local p = world:query({ with = { "player", "core/net/owner" }, without = { "core/net/peer/mirror" } })[1]
        if p then
            switched = ts[boot.SWITCH]
            commands:entity(p:id()):insert({ ["core/net/peer/switch"] = { target_scope = boot.OTHER,
                link = boot.NAME .. "_link" } })
        end
    end
end):in_set("zz/rd_server")
]=]
helpers.make_fixture("modules/test_fixtures/gen_rd_server.lua", SERVER)

-- The client's world of B, in its own VM: it watches until told to play, as root's flip says.
helpers.make_fixture("modules/test_fixtures/gen_rd_b_client.lua", [=[
require("modules/core/net/client/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local Net = require("modules/core/net/shared/net.lua")
local boot = Instances.boot_data()
local ts = helpers.shared_state("ZzReturnDoorClientState", boot.DEFAULTS)
app:add_systems(Startup, { Commands }, function(commands)
    -- Only its net: a worker's world net that starts watching is never answered (measured).
    commands:spawn({ ["core/net"] = { mode = "client", name = "zzrd_bc", ip = "127.0.0.1", port = boot.PORT, player_id = boot.PLAYER,
            observer = true }, ["core/net/sync"] = false })
    commands:spawn({ Name = "zz_rc", Transform = {}, ["player/spawner/point"] = {}, ["core/net/sync"] = false,
        ["core/script/owner"] = false })
    commands:spawn({ Transform = { translation = { x = 0, y = -0.5, z = 0 } }, RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 20, hy = 0.5, hz = 20 } }, ["core/net/sync"] = false, ["core/script/owner"] = false })
    -- This world's own row: its net reads root's presence ask naming this scope.
    commands:spawn({ ["core/world/status"] = { scope_key = boot.SCOPE, mode = "client", status = "ready", observer = true },
        WorldShared = {}, ["core/net/sync"] = false })
end)
app:add_systems(Update, { World }, function(world)
    local wn = Net.world_net(world, "client")
    local st = wn and wn:get("core/net/state") or {}
    ts.b_net = st.connected == true
    local owned = false
    for _, p in ipairs(world:query({ with = { "player", "core/net/owner" } })) do
        if wn and p:get("core/net/owner") == wn:id() then owned = true end
    end
    ts.b_owned = owned
end):in_set("zz/rd_b_client")
]=])

reg.started(helpers.spawn_vm("modules/test_fixtures/gen_rd_server.lua", { DEFAULTS = DEFAULTS, NAME = "zzrd_b", PORT = B_PORT,
    SCOPE = B, OTHER = A, KEY = "b", SWITCH = "to_a", LINK = A_PORT + 1, HERE = "zz_b_entrance", THERE = "zz_a_entrance" }, { headless = true }), B)
reg.started(helpers.spawn_vm("modules/test_fixtures/gen_rd_server.lua", { DEFAULTS = DEFAULTS, NAME = "zzrd_a", PORT = A_PORT,
    SCOPE = A, OTHER = B, KEY = "a", SWITCH = "to_b", LINK = B_PORT + 1, HERE = "zz_a_entrance", THERE = "zz_b_entrance" }, { headless = true }), A)

--- Root's presence ask for `scope`, as the flip writes it: `from` only on a promotion.
local function present(world, commands, scope, observer, from)
    for _, e in ipairs(world:query({ with = { "core/world/presence" }, without = { "WorldMirror" } })) do
        if e:get("core/world/presence").scope_key == scope then
            commands:entity(e:id()):insert({ ["core/world/presence"] = { scope_key = scope, observer = observer,
                from = (not observer) and from or nil } })
            return
        end
    end
    commands:spawn({ ["core/world/presence"] = { scope_key = scope, observer = observer, from = (not observer) and from or nil },
        WorldShared = {} })
end

-- This VM's copy of A's map, and its own row.
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/status"] = { scope_key = A, mode = "client", status = "ready", observer = false },
        WorldShared = {}, ["core/net/sync"] = false })
    commands:spawn({ Name = "zz_rc", Transform = {}, ["player/spawner/point"] = {}, ["core/net/sync"] = false,
        ["core/script/owner"] = false })
    commands:spawn({ Transform = { translation = { x = 0, y = -0.5, z = 0 } }, RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 20, hy = 0.5, hz = 20 } }, ["core/net/sync"] = false, ["core/script/owner"] = false })
    -- The door the player comes back by.
    commands:spawn({ Name = "zz_a_entrance", Transform = { translation = { x = 4, y = 0, z = 2 } }, ["core/net/sync"] = false,
        ["core/script/owner"] = false })
end)

--- This VM's copy of A's player, whether it is this client's, and its body.
local function a_player(world)
    local wn = Net.world_net(world, "client")
    local full = wn and world:get_entity(wn:id())
    for _, p in ipairs(world:query({ with = { "player" }, without = { "player/spawner/standin" },
        optional = { "core/net/owner", "RigidBody3d" } })) do
        local mine = wn ~= nil and p:get("core/net/owner") == wn:id()
        local owns = false
        for _, id in ipairs(full and full:get("core/net/owns") or {}) do owns = owns or id == p:id() end
        return p, mine and owns, p:get("RigidBody3d")
    end
end

--- The stand-ins here.
local function standins(world)
    return world:query({ with = { "player/spawner/standin" }, without = { "core/world/flip" },
        optional = { "player", "RigidBody3d", "core/net/owner" } })
end

local function say(world)
    local p, mine, body = a_player(world)
    local wn = Net.world_net(world, "client")
    local full = wn and world:get_entity(wn:id())
    local owns = {}
    for _, id in ipairs(full and full:get("core/net/owns") or {}) do owns[#owns + 1] = tostring(id) end
    local si = {}
    for _, s in ipairs(standins(world)) do
        si[#si + 1] = string.format("%s:%s/%s", tostring(s:id()), tostring(s:get("RigidBody3d")), tostring(s:get("core/net/owner")))
    end
    local cam = p and world:get_entity(p:id()):get("camera") or {}
    return string.format("here: %s owner=%s mine=%s body=%s camera=%s/%s/%s owns=[%s] standins=[%s] | B client",
        tostring(p and p:id()), tostring(p and p:get("core/net/owner")), tostring(mine), tostring(body), tostring(cam.distance),
        tostring(cam.height), tostring(cam.offset and cam.offset.x), table.concat(owns, ","),
        table.concat(si, " ")) .. string.format(" owned=%s | A server: %s | B server: %s",
        tostring(ts.b_owned), ts.a_srv, ts.b_srv)
end

local phase, clock, first, rooted, earlier = "wait", 0, nil, nil, nil

-- The screen shows a world's camera added last (the engine's RTT retarget), so the eyes are kept in
-- the order they were added, each with its carrier.
local eyes = {}
app:add_systems(Last, { Query[{ added = { "camera/3d/eye" }, with = { "Camera" }, optional = { "ChildOf" } }] },
    function(added)
        for _, e in ipairs(added:iter()) do
            eyes[#eyes + 1] = { id = e:id(), carrier = e:get("ChildOf") }
        end
    end)

--- The eyes added, in order, and which are still there (`on`/`off`).
local function eyes_said(world)
    local out = {}
    for _, eye in ipairs(eyes) do
        local now = world:get_entity(eye.id)
        local cam = now and now:get("Camera")
        out[#out + 1] = string.format("%s<-%s:%s", tostring(eye.id), tostring(eye.carrier),
            cam == nil and "gone" or (cam.is_active and "on" or "off"))
    end
    return "eyes added=[" .. table.concat(out, " ") .. "]"
end

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    if phase == "wait" and ts.a_ready and ts.b_ready and ts.a_linked and ts.b_linked and clock > 0.5 then
        commands:spawn({ ["core/world/net"] = { mode = "client", name = "zzrd_ac", ip = "127.0.0.1", port = A_PORT, player_id = PLAYER },
            ["core/net"] = { mode = "client", name = "zzrd_ac", ip = "127.0.0.1", port = A_PORT, player_id = PLAYER },
            ["core/net/sync"] = false })
        helpers.spawn_vm("modules/test_fixtures/gen_rd_b_client.lua", { DEFAULTS = DEFAULTS, PORT = B_PORT, PLAYER = PLAYER, SCOPE = B },
            { headless = true })
        step("in_a")
    elseif phase == "in_a" then
        local p, mine, body = a_player(world)
        if not (mine and body == "Dynamic" and ts.b_net and clock > 1) and clock < 20 then return end
        first = p and p:id()
        T("RC1_the_client_s_player_in_a_is_its_own_its_body_dynamic", mine and body == "Dynamic", say(world))
        ts.to_b = 1
        step("switching_to_b")
    elseif phase == "switching_to_b" and clock > 0.5 then
        -- Root follows the switch: B plays, A watches.
        present(world, commands, B, false, A)
        present(world, commands, A, true)
        step("in_b")
    elseif phase == "in_b" then
        local _, mine = a_player(world)
        if not (ts.b_owned and not mine and clock > 1) and clock < 15 then return end
        T("RC2_handed_to_b_b_s_player_is_the_client_s_and_a_s_copy_is_not_its_own", ts.b_owned and not mine, say(world))
        -- The first return is predicted too; its ask stays, done, as root's pin for this world.
        earlier = commands:spawn({ ["core/world/flip"] = { scope = A, status = "predicted", predicted = { at = "zz_a_entrance",
                place = { translation = { x = 1, y = 1, z = 0 }, rotation = { x = 0, y = 0, z = 0, w = 1 },
                    scale = { x = 1, y = 1, z = 1 } },
                look = { yaw = 0.3, pitch = -0.1, distance = 6 } } },
            ["player/spawner/standin"] = {}, WorldMirror = { world_id = 0 }, ["core/net/sync"] = false }):id()
        step("round_predicting")
    elseif phase == "round_predicting" and clock > 0.5 then
        ts.to_a = 1
        step("round_a")
    elseif phase == "round_a" and clock > 0.2 then
        commands:entity(earlier):entry("core/world/flip"):and_modify(function(flip) flip.status = "promoting" end)
        present(world, commands, A, false, B)
        present(world, commands, B, true)
        step("round_in_a")
    elseif phase == "round_in_a" then
        local _, mine = a_player(world)
        if not (mine and not ts.b_owned and #standins(world) == 0 and clock > 1) and clock < 15 then return end
        commands:entity(earlier):entry("core/world/flip"):and_modify(function(flip) flip.status = "done" end)
        T("RD1_back_by_the_other_door_a_s_player_is_its_own_again_its_stand_in_replaced",
            mine and not ts.b_owned and #standins(world) == 0, say(world))
        ts.to_b = 2
        step("round_b")
    elseif phase == "round_b" and clock > 0.5 then
        present(world, commands, B, false, A)
        present(world, commands, A, true)
        step("round_in_b")
    elseif phase == "round_in_b" then
        local _, mine = a_player(world)
        if not (ts.b_owned and not mine and clock > 1) and clock < 15 then return end
        T("RD2_and_to_b_again_b_s_player_is_the_client_s", ts.b_owned and not mine, say(world))
        -- Root's predicted ask for the return, as it arrives here.
        rooted = commands:spawn({ ["core/world/flip"] = { scope = A, status = "predicted", predicted = { at = "zz_a_entrance",
                place = { translation = { x = 1, y = 1, z = 0 }, rotation = { x = 0, y = 0, z = 0, w = 1 },
                    scale = { x = 1, y = 1, z = 1 } },
                look = { yaw = 0.3, pitch = -0.1, distance = 6 } } },
            ["player/spawner/standin"] = {}, WorldMirror = { world_id = 0 }, ["core/net/sync"] = false }):id()
        step("predicting")
    elseif phase == "predicting" then
        local all = standins(world)
        local s = all[1]
        if not (s and s:has("player") and clock > 0.3) and clock < 5 then return end
        T("RS1_the_predicted_return_stands_the_player_in_here", #all == 1 and s:has("player"), say(world))
        ts.to_a = 2
        step("switching_to_a")
    elseif phase == "switching_to_a" and clock > 0.2 then
        -- Root confirms on the switch, and promotes.
        commands:entity(rooted):entry("core/world/flip"):and_modify(function(flip) flip.status = "promoting" end)
        present(world, commands, A, false, B)
        present(world, commands, B, true)
        step("promoting")
    elseif phase == "promoting" then
        local _, mine = a_player(world)
        if not (mine and #standins(world) == 0 and clock > 1) and clock < 10 then return end
        T("RS2_the_real_player_takes_the_stand_in_s_place_before_the_crossing_is_done",
            mine and #standins(world) == 0, say(world) .. " " .. eyes_said(world))
        commands:entity(rooted):entry("core/world/flip"):and_modify(function(flip) flip.status = "done" end)
        step("back")
    elseif phase == "back" then
        local p, mine, body = a_player(world)
        if not (mine and body == "Dynamic" and not ts.b_owned and clock > 1) and clock < 15 then return end
        T("RC3_handed_back_a_s_player_is_its_own_here_again_the_same_entity_its_body_dynamic",
            mine and body == "Dynamic" and p ~= nil and p:id() == first, say(world) .. " first=" .. tostring(first))
        T("RC4_and_b_s_player_is_not_the_client_s_there", not ts.b_owned, say(world))
        local last = eyes[#eyes]
        local shown = last and world:get_entity(last.id)
        T("RS3_the_eye_added_last_the_one_shown_is_the_real_player_s_and_on",
            shown ~= nil and p ~= nil and last.carrier == p:id() and shown:get("Camera").is_active == true, eyes_said(world))
        phase = "done"
        suite.finish("PlayerReturnDoorClientSuite")
    end
    if phase ~= "done" and clock > 30 then
        T("RC0_reached_" .. phase, false, say(world))
        phase = "done"
        suite.finish("PlayerReturnDoorClientSuite")
    end
end):in_set("zz/rd_suite")
