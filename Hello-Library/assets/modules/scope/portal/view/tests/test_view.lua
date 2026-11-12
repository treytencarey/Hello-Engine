-- --host
-- scope/portal/view on a client. Root is stubbed: its answer is an entity carrying
-- `WorldMirror { world_id = 0 }`, as root's arrives in a world's VM. A lookalike is a mirror from
-- another VM, or this VM's own entity.
-- The look (sphere, colours) needs StandardMaterial assets, which a headless run lacks.
--
--   V1  a placed portal to another world gets one observe ask, its child, shared with root
--   V2  two portals to one world each get their own ask
--   V3  a portal to this world's own scope gets none
--   V15 ...and root allowing a look at this world (another world's portal asked) shows nothing
--       through it
--   V4  a portal being placed gets none, and one once placed
--   V14 a portal seen being placed asks to start its world (`join_only = false`); one placed
--       already when it came (one placed before) asks join-only
--   V16 a door, a portal that arrives with its scene (a `SceneRoot` above it, here a real glTF
--       scene), asks to start its world as it loads
--   V5  `scope/portal/hosted` puts `hosted` on its ask, and taking it off takes `hosted` out
--   V6  root's `allowed` puts the stencil on a 3d portal
--   V7  a lookalike answer, another world's mirror or this world's own entity, changes nothing
--   V8  root's `refused` locks the portal with the reason; a later `allowed` unlocks it
--   V9  on a "none" carrier with no mesh, `allowed` puts the stencil on its mesh children
--   V17 a door's (`at`, on a named node) stencils carry its `at`, its world transform as `frame`
--       and its `Name` as `view`
--   V18 a portal without `at` writes none of them
--   V19 the door moved, its stencils' `frame` follows
--   V10 a changed target replaces the ask
--   V11 in a world that only observes, no portal asks; promoted, it catches up
--   V12 taking the view off a portal that stays takes its ask and its stencil
--   V13 a reload of the mod keeps each ask, once
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local AssetServer = require("bevy::asset::AssetServer")
local Quat = require("bevy::math::Quat")

local suite = helpers.create_suite("ScopePortalViewSuite")
local T = suite.assert_test

local HERE = "github:zzview/here:main"
local OTHER = "github:zzview/other:main"
local SECOND = "github:zzview/second:main"
local DOOR = "github:zzview/door:main"
local LATER = "github:zzview/later:main"
local MOVED = "github:zzview/moved:main"
local MAPPED = "github:zzview/mapped:main"
local VIEW_SOURCE = "assets/modules/scope/portal/view/client/init.lua"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
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

local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-3 end

-- Whether both of the mapped door's primitives show MAPPED from the door standing at (x, y, z),
-- turned a quarter about Y, and what the first says.
local function mapped_at(world, kids, x, y, z)
    local said, ok = "none", #kids == 2
    for _, id in ipairs(kids) do
        local s = stencil_on(world, id)
        local frame = s and s.frame or {}
        local at = frame.translation or {}
        local yaw = frame.rotation and Quat.to_euler(frame.rotation, "YXZ")[1]
        ok = ok and s ~= nil and s.world == MAPPED and s.at == "zz_arrival" and s.view == "zz_door"
            and near(at.x, x) and near(at.y, y) and near(at.z, z) and near(yaw, math.pi / 2)
            and frame.scale ~= nil and near(frame.scale.x, 1)
        said = string.format("world=%s at=%s view=%s frame=%s,%s,%s yaw=%s", tostring(s and s.world),
            tostring(s and s.at), tostring(s and s.view), tostring(at.x), tostring(at.y), tostring(at.z), tostring(yaw))
    end
    return ok, said
end

local phase, clock = "spawn", 0
local door_kids, mapped_kids = {}, {}
local kept_ask

app:add_systems(Update, { World, Commands, Res[AssetServer] }, function(world, commands, assets)
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
        -- A map's door: a node under the map's scene.
        local map = commands:spawn({
            SceneRoot = assets:load("modules/gltf/mod_registry/tests/fixtures/markers.glb#Scene0"),
            ["core/net/sync"] = false,
        }):id()
        local door = commands:spawn({ ["scope/portal"] = { target = DOOR }, ["scope/portal/view"] = { mode = "none" },
            ["core/net/sync"] = false, ["zz/view/p"] = { name = "door" }, ChildOf = map }):id()
        door_kids[1] = commands:spawn({ Mesh3d = {}, ["zz/view/prim"] = {}, ChildOf = door }):id()
        door_kids[2] = commands:spawn({ Mesh3d = {}, ["zz/view/prim"] = {}, ChildOf = door }):id()
        -- A door mapped to a place in its target: `at`, on a named node, turned a quarter.
        local mapped = commands:spawn({ ["scope/portal"] = { target = MAPPED, at = "zz_arrival" },
            ["scope/portal/view"] = { mode = "none" }, Name = "zz_door",
            Transform = { translation = { x = 4, y = 1, z = -2 }, rotation = Quat.from_rotation_y(math.pi / 2) },
            ["core/net/sync"] = false, ["zz/view/p"] = { name = "mapped" } }):id()
        mapped_kids[1] = commands:spawn({ Mesh3d = {}, ["zz/view/prim"] = {}, ChildOf = mapped }):id()
        mapped_kids[2] = commands:spawn({ Mesh3d = {}, ["zz/view/prim"] = {}, ChildOf = mapped }):id()
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
        T("V14_one_placed_when_it_came_asks_join_only", #before == 1 and before[1].ask.join_only == nil, "")
        T("V16_a_door_that_arrives_with_its_scene_asks_to_start_its_world", #door == 1
            and door[1].ask.join_only == false, tostring(door[1] and door[1].ask.join_only))
        local a = asks_of(world, portal(world, "a"))
        T("V5a_hosted_rides_the_ask", #a == 1 and a[1].ask.hosted == true, "")
        commands:entity(portal(world, "a"):id()):remove("scope/portal/hosted")
        -- Root's answers, and two lookalikes for SECOND: a world's mirror, and this VM's own entity.
        commands:spawn({ ["core/world/observe/answer"] = { ref = OTHER, state = "allowed" },
            WorldMirror = { world_id = 0 }, ["core/net/sync"] = false })
        commands:spawn({ ["core/world/observe/answer"] = { ref = DOOR, state = "allowed" },
            WorldMirror = { world_id = 0 }, ["core/net/sync"] = false })
        commands:spawn({ ["core/world/observe/answer"] = { ref = MAPPED, state = "allowed" },
            WorldMirror = { world_id = 0 }, ["core/net/sync"] = false })
        commands:spawn({ ["core/world/observe/answer"] = { ref = HERE, state = "allowed" },
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
        local own = portal(world, "self")
        T("V15_an_allowed_look_at_this_world_shows_nothing_through_a_portal_to_it",
            not own:has("core/compositor/stencil") and not own:has("scope/portal/locked")
                and #asks_of(world, own) == 0, "")
        local ok, said = mapped_at(world, mapped_kids, 4, 1, -2)
        T("V17_a_door_s_stencils_carry_at_its_frame_and_its_view", ok, said)
        T("V18_a_portal_without_at_writes_none_of_them",
            s ~= nil and s.at == nil and s.frame == nil and s.view == nil and k1 ~= nil and k1.at == nil
                and k1.frame == nil and k1.view == nil, "")
        -- Moved alone, so nothing else here runs the view's systems.
        commands:entity(portal(world, "mapped"):id()):insert({
            Transform = { translation = { x = 9, y = 1, z = 6 }, rotation = Quat.from_rotation_y(math.pi / 2) },
        })
        step("moved")

    elseif phase == "moved" and clock > 0.3 then
        local ok, said = mapped_at(world, mapped_kids, 9, 1, 6)
        T("V19_the_door_moved_its_stencils_frame_follows", ok, said)
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
