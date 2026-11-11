-- --host
-- scope/portal/view on a client. Root is stubbed: its answer is an entity carrying
-- `WorldMirror { world_id = 0 }`, as root's arrives in a world's VM. A lookalike is a mirror from
-- another VM, or this VM's own entity.
-- The look (sphere, colours) needs StandardMaterial assets, which a headless run lacks.
--
--   V1  a placed portal to another world gets one observe ask, its child, shared with root
--   V2  two portals to one world each get their own ask
--   V3  a portal to this world's own scope gets none
--   V4  a portal being placed gets none, and one once placed
--   V14 a portal seen being placed asks to start its world (`join_only = false`); one placed
--       already when it came (a door, one placed before) asks join-only
--   V5  `scope/portal/hosted` puts `hosted` on its ask, and taking it off takes `hosted` out
--   V6  root's `allowed` puts the stencil on a 3d portal
--   V7  a lookalike answer, another world's mirror or this world's own entity, changes nothing
--   V8  root's `refused` locks the portal with the reason; a later `allowed` unlocks it
--   V9  on a "none" carrier with no mesh, `allowed` puts the stencil on its mesh children
--   V10 a changed target replaces the ask
--   V11 in a world that only observes, no portal asks; promoted, it catches up
--   V12 taking the view off a portal that stays takes its ask and its stencil
--   V13 a reload of the mod keeps each ask, once
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("ScopePortalViewSuite")
local T = suite.assert_test

local HERE = "github:zzview/here:main"
local OTHER = "github:zzview/other:main"
local SECOND = "github:zzview/second:main"
local DOOR = "github:zzview/door:main"
local LATER = "github:zzview/later:main"
local MOVED = "github:zzview/moved:main"
local VIEW_SOURCE = "assets/modules/scope/portal/view/client/init.lua"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
    commands:spawn({
        ["core/world/status"] = { scope_key = HERE, mode = "client", status = "ready", observer = false },
        WorldShared = {},
        ["core/net/sync"] = false,
        ["zz/view/row"] = {},
    })
end)

local function portal(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/view/p" },
        optional = { "scope/portal", "scope/portal/view", "scope/portal/locked", "core/compositor/stencil", "Children" },
    })) do
        if e:get("zz/view/p").name == name then return e end
    end
end

local function asks_of(world, p)
    local out = {}
    if p == nil then return out end
    for _, child in ipairs(p:get("Children") or {}) do
        local e = world:get_entity(child)
        local ask = e and e:get("core/world/observe")
        if ask ~= nil then out[#out + 1] = { entity = e, ask = ask } end
    end
    return out
end

local function row(world)
    return world:query({ with = { "zz/view/row", "core/world/status" } })[1]
end

local function stencil_on(world, id)
    local e = world:get_entity(id)
    return e and e:get("core/compositor/stencil")
end

local phase, clock = "spawn", 0
local door_kids = {}
local kept_ask

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({ ["scope/portal"] = { target = OTHER }, ["scope/portal/view"] = { mode = "3d" },
            ["core/net/sync"] = false, ["zz/view/p"] = { name = "a" } })
        commands:spawn({ ["scope/portal"] = { target = OTHER }, ["scope/portal/view"] = { mode = "3d" },
            ["core/net/sync"] = false, ["zz/view/p"] = { name = "b" } })
        commands:spawn({ ["scope/portal"] = { target = HERE }, ["scope/portal/view"] = { mode = "3d" },
            ["core/net/sync"] = false, ["zz/view/p"] = { name = "self" } })
        commands:spawn({ ["scope/portal"] = { target = SECOND }, ["scope/portal/view"] = { mode = "3d" },
            placement = {}, ["core/net/sync"] = false, ["zz/view/p"] = { name = "placing" } })
        local door = commands:spawn({ ["scope/portal"] = { target = DOOR }, ["scope/portal/view"] = { mode = "none" },
            ["core/net/sync"] = false, ["zz/view/p"] = { name = "door" } }):id()
        door_kids[1] = commands:spawn({ Mesh3d = {}, ["zz/view/prim"] = {}, ChildOf = door }):id()
        door_kids[2] = commands:spawn({ Mesh3d = {}, ["zz/view/prim"] = {}, ChildOf = door }):id()
        step("asked")

    elseif phase == "asked" and #asks_of(world, portal(world, "a")) > 0 and clock > 0.3 then
        local a, b = asks_of(world, portal(world, "a")), asks_of(world, portal(world, "b"))
        local ask = a[1] and a[1].ask
        T("V1_a_placed_portal_asks_once_as_its_child",
            #a == 1 and ask.ref == OTHER and ask.hosted == nil and type(ask.libraries) == "table"
                and a[1].entity:has("WorldShared"),
            string.format("asks=%d ref=%s", #a, tostring(ask and ask.ref)))
        T("V2_each_portal_to_one_world_asks", #b == 1 and b[1].ask.ref == OTHER, "asks=" .. #b)
        T("V3_a_portal_to_this_world_asks_nothing", #asks_of(world, portal(world, "self")) == 0, "")
        T("V4a_a_portal_being_placed_asks_nothing", #asks_of(world, portal(world, "placing")) == 0, "")
        commands:entity(portal(world, "placing"):id()):remove("placement")
        commands:entity(portal(world, "a"):id()):insert({ ["scope/portal/hosted"] = {} })
        step("placed")

    elseif phase == "placed" and clock > 0.3 then
        local placing = asks_of(world, portal(world, "placing"))
        T("V4b_once_placed_it_asks", #placing == 1 and placing[1].ask.ref == SECOND, "asks=" .. #placing)
        local door = asks_of(world, portal(world, "door"))
        T("V14_a_portal_seen_being_placed_asks_to_start_its_world", #placing == 1 and placing[1].ask.join_only == false,
            tostring(placing[1] and placing[1].ask.join_only))
        local before = asks_of(world, portal(world, "a"))
        T("V14_one_placed_when_it_came_asks_join_only", #before == 1 and before[1].ask.join_only == nil and #door == 1
            and door[1].ask.join_only == nil, "")
        local a = asks_of(world, portal(world, "a"))
        T("V5a_hosted_rides_the_ask", #a == 1 and a[1].ask.hosted == true, "")
        commands:entity(portal(world, "a"):id()):remove("scope/portal/hosted")
        -- Root's answers, and two lookalikes for SECOND: a world's mirror, and this VM's own entity.
        commands:spawn({ ["core/world/observe/answer"] = { ref = OTHER, state = "allowed" },
            WorldMirror = { world_id = 0 }, ["core/net/sync"] = false })
        commands:spawn({ ["core/world/observe/answer"] = { ref = DOOR, state = "allowed" },
            WorldMirror = { world_id = 0 }, ["core/net/sync"] = false })
        commands:spawn({ ["core/world/observe/answer"] = { ref = SECOND, state = "refused", reason = "zz-forged" },
            WorldMirror = { world_id = 7 }, ["core/net/sync"] = false })
        commands:spawn({ ["core/world/observe/answer"] = { ref = SECOND, state = "refused", reason = "zz-own" },
            ["core/net/sync"] = false })
        step("answered")

    elseif phase == "answered" and clock > 0.3 then
        local a = asks_of(world, portal(world, "a"))
        T("V5b_hosted_taken_off_leaves_the_ask", #a == 1 and a[1].ask.hosted == nil, "")
        local pa = portal(world, "a")
        local s = pa:get("core/compositor/stencil")
        T("V6_allowed_puts_the_stencil_on_a_3d_portal",
            s ~= nil and s.world == OTHER and not pa:has("scope/portal/locked"), "")
        local placing = portal(world, "placing")
        T("V7_a_lookalike_answer_changes_nothing",
            not placing:has("scope/portal/locked") and not placing:has("core/compositor/stencil"), "")
        local door = portal(world, "door")
        local k1, k2 = stencil_on(world, door_kids[1]), stencil_on(world, door_kids[2])
        T("V9_a_none_carrier_shows_it_on_its_mesh_children",
            k1 ~= nil and k1.world == DOOR and k2 ~= nil and k2.world == DOOR
                and not door:has("core/compositor/stencil"), "")
        commands:spawn({ ["core/world/observe/answer"] = { ref = SECOND, state = "refused", reason = "not-running" },
            WorldMirror = { world_id = 0 }, ["core/net/sync"] = false, ["zz/view/second"] = {} })
        step("refused")

    elseif phase == "refused" and clock > 0.3 then
        local placing = portal(world, "placing")
        local locked = placing:get("scope/portal/locked")
        T("V8a_refused_locks_it_with_the_reason",
            locked ~= nil and locked.reason == "not-running" and not placing:has("core/compositor/stencil"), "")
        for _, e in ipairs(world:query({ with = { "zz/view/second", "core/world/observe/answer" } })) do
            commands:entity(e:id()):insert({ ["core/world/observe/answer"] = { ref = SECOND, state = "allowed" } })
        end
        commands:entity(portal(world, "b"):id()):insert({ ["scope/portal"] = { target = MOVED } })
        step("reopened")

    elseif phase == "reopened" and clock > 0.3 then
        local placing = portal(world, "placing")
        local s = placing:get("core/compositor/stencil")
        T("V8b_a_later_allowed_unlocks_it", not placing:has("scope/portal/locked") and s ~= nil and s.world == SECOND, "")
        local b = asks_of(world, portal(world, "b"))
        T("V10_a_changed_target_replaces_the_ask", #b == 1 and b[1].ask.ref == MOVED, "asks=" .. #b)
        commands:entity(row(world):id()):insert({
            ["core/world/status"] = { scope_key = HERE, mode = "client", status = "ready", observer = true },
        })
        step("watching")

    elseif phase == "watching" and clock > 0.2 then
        commands:spawn({ ["scope/portal"] = { target = LATER }, ["scope/portal/view"] = { mode = "3d" },
            ["core/net/sync"] = false, ["zz/view/p"] = { name = "later" } })
        step("observing")

    elseif phase == "observing" and clock > 0.4 then
        T("V11a_an_observer_world_asks_nothing", #asks_of(world, portal(world, "later")) == 0, "")
        commands:entity(row(world):id()):insert({
            ["core/world/status"] = { scope_key = HERE, mode = "client", status = "ready", observer = false },
        })
        step("promoted")

    elseif phase == "promoted" and clock > 0.3 then
        local later = asks_of(world, portal(world, "later"))
        T("V11b_promoted_it_catches_up", #later == 1 and later[1].ask.ref == LATER, "asks=" .. #later)
        commands:entity(portal(world, "a"):id()):remove("scope/portal/view")
        step("unviewed")

    elseif phase == "unviewed" and clock > 0.3 then
        local pa = portal(world, "a")
        T("V12_taking_the_view_off_takes_its_ask_and_stencil",
            #asks_of(world, pa) == 0 and not pa:has("core/compositor/stencil") and pa:has("scope/portal"), "")
        local later = asks_of(world, portal(world, "later"))
        kept_ask = later[1] and later[1].entity:id()
        write_file_bytes(VIEW_SOURCE, read_file_bytes(VIEW_SOURCE))
        step("reloaded")

    elseif phase == "reloaded" and clock > 2 then
        local later = asks_of(world, portal(world, "later"))
        T("V13_a_reload_keeps_each_ask_once",
            kept_ask ~= nil and #later == 1 and later[1].entity:id() == kept_ask,
            string.format("asks=%d same=%s", #later, tostring(later[1] and later[1].entity:id() == kept_ask)))
        phase = "done"
        suite.finish("ScopePortalViewSuite")
    end

    if phase ~= "done" and clock > 10 then
        T("V0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("ScopePortalViewSuite")
    end
end):in_set("zz/view_suite")
