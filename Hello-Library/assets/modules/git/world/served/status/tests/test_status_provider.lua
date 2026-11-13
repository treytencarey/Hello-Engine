-- test_status_provider.lua: git/world/served/status tells core it provides the edit facts, with
-- `core/library/edit/provider` on its carrier. The suite stands in for root's scans: it puts each
-- `vault/git/status/reply` under the carrier itself.
--
-- P1  the checkout on the world's commit and branch: `{ ref }`, active
-- P2  the checkout on another branch than the world's: paused
-- P3  the checkout on another commit of the world's branch: no marker
-- P4  root's identity signed out: paused
-- P5  git/world/served/status taken off the carrier: the marker goes
-- P6  a fact whose file the world changed too (`git/world/head/dirty` on this player) says `both`;
--     one the world did not change does not
-- P7  the world's list changing restates `both`

require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("GitStatusProviderSuite")
local T = suite.assert_test

local SCOPE = "github:zzprov/proj:main"
local SHA = "1111111111111111111111111111111111111111"
local OTHER = "2222222222222222222222222222222222222222"

local carrier, identity
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ ["core/world/status"] = { scope_key = SCOPE, mode = "client", status = "ready" },
        WorldShared = {}, ["core/net/sync"] = false })
    identity = commands:spawn({ ["core/player/identity"] = { site_user_id = "zz-user" }, ["core/net/sync"] = false }):id()
    commands:spawn({ ["git/world/head"] = { sha = SHA }, ["core/net/sync"] = false })
    carrier = commands:spawn({ ["git/world/served/status"] = {}, ["zz/prov/carrier"] = {}, ["core/net/sync"] = false }):id()
end)

local function marker(world)
    for _, e in ipairs(world:query({ with = { "zz/prov/carrier" }, optional = { "core/library/edit/provider" } })) do
        return e:has("core/library/edit/provider") and e:get("core/library/edit/provider") or false
    end
end
local function scan(commands, head, branch)
    commands:spawn({ ["vault/git/status/reply"] = { status = "ok", head = head, branch = branch, entries = {} },
        ChildOf = carrier })
end
local dirty_entity
local function scan_with(commands, entries)
    commands:spawn({ ["vault/git/status/reply"] = { status = "ok", head = SHA, branch = "main", entries = entries },
        ChildOf = carrier })
end
local function fact(world, path)
    for _, e in ipairs(world:query({ with = { "core/library/edit" } })) do
        local f = e:get("core/library/edit")
        if f.path == path then return f end
    end
end
local function said(m)
    if m == false then return "none" end
    if m == nil then return "no carrier" end
    return string.format("{ ref = %s, paused = %s }", tostring(m.ref), tostring(m.paused))
end

local phase, clock = "start", 0
app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(p) phase, clock = p, 0 end
    local function finish()
        phase = "done"
        suite.finish("GIT_STATUS_PROVIDER")
    end
    if phase == "done" then return end
    local m = marker(world)

    if phase == "start" and clock > 0.5 then
        scan(commands, SHA, "main")
        step("p1")
    elseif phase == "p1" and ((m and not m.paused) or clock > 5) then
        T("P1_on_the_worlds_commit_and_branch_the_marker_is_active", m and m.ref == SCOPE and not m.paused, said(m))
        dirty_entity = commands:spawn({ ["git/world/head/dirty"] = { ["modules/a.lua"] = "write" }, ["core/net/sync"] = false }):id()
        step("p6 dirty")
    elseif phase == "p6 dirty" and clock > 0.3 then
        scan_with(commands, { { path = "assets/modules/a.lua", op = "write" }, { path = "assets/modules/b.lua", op = "write" } })
        step("p6")
    elseif phase == "p6" and ((fact(world, "modules/a.lua") and fact(world, "modules/b.lua")) or clock > 5) then
        local a, b = fact(world, "modules/a.lua") or {}, fact(world, "modules/b.lua") or {}
        T("P6_a_file_the_world_changed_too_is_both", a.both == true and b.both == nil,
            "a=" .. tostring(a.both) .. " b=" .. tostring(b.both))
        commands:entity(dirty_entity):insert({ ["git/world/head/dirty"] = { ["modules/b.lua"] = "write" } })
        step("p7")
    elseif phase == "p7" and (((fact(world, "modules/b.lua") or {}).both == true) or clock > 5) then
        local a, b = fact(world, "modules/a.lua") or {}, fact(world, "modules/b.lua") or {}
        T("P7_the_worlds_list_changing_restates_both", a.both == nil and b.both == true,
            "a=" .. tostring(a.both) .. " b=" .. tostring(b.both))
        scan(commands, SHA, "elsewhere")
        step("p2")
    elseif phase == "p2" and ((m and m.paused) or clock > 5) then
        T("P2_another_branch_pauses", m and m.ref == SCOPE and m.paused == true, said(m))
        scan(commands, OTHER, "main")
        step("p3")
    elseif phase == "p3" and (m == false or clock > 5) then
        T("P3_another_commit_takes_the_marker_off", m == false, said(m))
        commands:entity(identity):insert({ ["core/player/identity"] = {} })
        step("p4")
    elseif phase == "p4" and ((m and m.paused) or clock > 5) then
        T("P4_signed_out_pauses", m and m.paused == true, said(m))
        commands:entity(carrier):remove("git/world/served/status")
        step("p5")
    elseif phase == "p5" and (m == false or clock > 5) then
        T("P5_the_marker_goes_with_the_sub_mod", m == false, said(m))
        finish()
    end
    if phase ~= "done" and clock > 10 then
        T("P0_reached_" .. phase, false, "stuck")
        finish()
    end
end):in_set("zz/status_provider_flow")
