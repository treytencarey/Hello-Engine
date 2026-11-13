-- test_head_dirty.lua: git/world/head on a server tells each writer, and only writers, the tree's
-- live edits: `git/world/head/dirty` on their own player, synced to that player alone. The suite
-- stands in for root's status answers, for the players and for their connections' proofs.
--
-- D1  the writer's player gets the tree's dirty files and an owner-only sync entry for them
-- D2  a player whose proof is not "writer", and one with no proof, get nothing
-- D3  a proof that stops being "writer" takes the list and its sync entry off that player
-- D4  the served tree changing (its `core/library/files` rows) asks again, and the list follows
-- D5  the head gone: every list goes

require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("GitHeadDirtySuite")
local T = suite.assert_test

local SHA = "1111111111111111111111111111111111111111"
local answer = { { path = "assets/modules/maps/lab/assets/lab.glb", op = "write" },
    { path = "assets/modules/x/server/init.lua", op = "create" } }

local head, files, conn1
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    for id, state in pairs({ [1] = "writer", [2] = "absent" }) do
        local c = commands:spawn({
            ["core/net/connection"] = { client_id = id },
            ["git/collaborators/authorize/proof"] = { user = "u" .. id, nonce = "n" .. id, state = state, asked_at = 0 },
            ["core/net/sync"] = false,
        }):id()
        if id == 1 then conn1 = c end
    end
    commands:spawn({ ["core/net/connection"] = { client_id = 3 }, ["core/net/sync"] = false })
    for id = 1, 3 do
        commands:spawn({ player = { client_id = id }, ["zz/dirty/player"] = { id = id }, ["core/net/sync"] = {} })
    end
    files = commands:spawn({ ["core/library/files"] = { ref = "served:zz", root = "", top = "maps", files = {} },
        ["core/net/sync"] = false }):id()
end)

-- Root's stand-in: every status request under the head gets the scripted answer; root's own
-- refusal (the suite is root) is taken off first.
local asks = 0
app:add_systems(First, {
    Query[{ with = { "vault/git/status", "Request" }, optional = { "vault/git/status/reply" } }],
    Commands,
}, function(requests, commands)
    for _, r in ipairs(requests:iter()) do
        if r:has("vault/git/status/reply") then
            if r:get("vault/git/status/reply").status == "refused" then
                commands:entity(r:id()):remove("vault/git/status/reply")
            end
        else
            asks = asks + 1
            commands:entity(r:id()):insert({ ["vault/git/status/reply"] = { status = "ok", head = SHA, entries = answer } })
        end
    end
end):in_set("zz/head_dirty_root")

local function player(world, id)
    for _, e in ipairs(world:query({ with = { "zz/dirty/player" }, optional = { "git/world/head/dirty", "core/net/sync" } })) do
        if e:get("zz/dirty/player").id == id then return e end
    end
end
local function dirty(world, id)
    local p = player(world, id)
    return p and p:has("git/world/head/dirty") and p:get("git/world/head/dirty") or nil
end
local function synced(world, id)
    local p = player(world, id)
    local sync = p and p:get("core/net/sync")
    local entry = type(sync) == "table" and sync["git/world/head/dirty"] or nil
    return entry and entry.target == "owner" and entry.authority == "server"
end

local phase, clock = "start", 0
app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(p) phase, clock = p, 0 end
    local function finish()
        phase = "done"
        suite.finish("GIT_HEAD_DIRTY")
    end
    if phase == "done" then return end

    if phase == "start" and clock > 0.3 then
        head = commands:spawn({ ["git/world/head"] = {}, ["core/net/sync"] = false }):id()
        step("d1")
    elseif phase == "d1" and (dirty(world, 1) or clock > 5) then
        local d = dirty(world, 1) or {}
        T("D1_the_writer_is_told_the_live_edits_on_their_own_player",
            d["modules/maps/lab/assets/lab.glb"] == "write" and d["modules/x/server/init.lua"] == "create" and synced(world, 1),
            "dirty=" .. tostring(d["modules/maps/lab/assets/lab.glb"]) .. " synced=" .. tostring(synced(world, 1)))
        T("D2_a_non_writer_is_told_nothing", dirty(world, 2) == nil and dirty(world, 3) == nil
            and not synced(world, 2) and not synced(world, 3), "")
        commands:entity(conn1):insert({ ["git/collaborators/authorize/proof"] = { user = "u1", nonce = "n1", state = "absent", asked_at = 0 } })
        step("d3")
    elseif phase == "d3" and (dirty(world, 1) == nil or clock > 5) then
        T("D3_a_proof_no_longer_writer_takes_the_list_off", dirty(world, 1) == nil and not synced(world, 1), "")
        commands:entity(conn1):insert({ ["git/collaborators/authorize/proof"] = { user = "u1", nonce = "n1", state = "writer", asked_at = 0 } })
        step("d4 back")
    elseif phase == "d4 back" and (dirty(world, 1) or clock > 5) then
        answer = { { path = "assets/modules/maps/new.lua", op = "create" } }
        commands:entity(files):insert({ ["core/library/files"] = { ref = "served:zz", root = "", top = "maps", files = { ["modules/maps/new.lua"] = { s = 1 } } } })
        step("d4")
    elseif phase == "d4" and ((dirty(world, 1) or {})["modules/maps/new.lua"] or clock > 5) then
        local d = dirty(world, 1) or {}
        T("D4_the_tree_changing_asks_again_and_the_list_follows",
            d["modules/maps/new.lua"] == "create" and d["modules/maps/lab/assets/lab.glb"] == nil, "")
        commands:entity(head):despawn()
        step("d5")
    elseif phase == "d5" and ((dirty(world, 1) == nil and not synced(world, 1)) or clock > 5) then
        T("D5_the_head_gone_every_list_goes", dirty(world, 1) == nil and not synced(world, 1),
            "dirty=" .. tostring(dirty(world, 1) ~= nil) .. " synced=" .. tostring(synced(world, 1)))
        finish()
    end
    if phase ~= "done" and clock > 10 then
        T("D0_reached_" .. phase, false, "stuck")
        finish()
    end
end):in_set("zz/head_dirty_flow")
