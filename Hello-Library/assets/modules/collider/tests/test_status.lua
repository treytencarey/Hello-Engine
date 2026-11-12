-- `collider`'s books: `collider/status` on the nearest SceneRoot above its carriers.
--
-- Server side. A recorder ordered after `collider/status` reads every root's status each frame and
-- counts its edges, and checks each "done" against the carriers under that root.
--
-- K1 five hand-made `collider/mesh` carriers under one SceneRoot, built a few a frame (a system
--    ahead of the build spends the frame's slice): "building" while any is unbuilt, "done" after
--    the last, never "done" before, and one change for the one transition
-- K2 markers.glb through `gltf/mod_registry`, `fx_floor` (`collider/mesh`) and `fx_box`
--    (`collider/bb`): "done" only once both are built
-- K3 a re-export of that scene goes back to "building" or removes the status, then "done" again
-- K4 the status goes with the scene's last carrier, and another scene's stays untouched
-- K5 every carrier of one pass gets the base in the same frame, though `collider/mesh` is loaded
--    (K1) and `collider/bb` loads with this scene, and the status is never "done" early
-- K6 `collider/mesh` on a SceneRoot whose file is not there yet: "building" while it loads, and
--    "done" only once every primitive of the scene that arrives has its shape
-- K7 the base's file is edited (hot reload): each root with carriers has its status, "done",
--    and every carrier still has exactly one shape
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local AssetServer = require("bevy::asset::AssetServer")
local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local Cuboid = require("bevy::math::primitives::Cuboid")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("ColliderStatusSuite")
local T = suite.assert_test

local SOURCE = read_file_bytes("assets/modules/gltf/mod_registry/tests/fixtures/markers.glb")
local COPY = "modules/collider/tests/zz_status_copy.glb"
write_file_bytes("assets/" .. COPY, SOURCE)
local LATE = "modules/collider/tests/zz_status_late.glb"
os.remove("assets/" .. LATE)

local phase, clock, frames, frame = "k1", 0, 0, 0
local hand, scene, late

app:add_systems(Startup, { Commands, Res[AssetServer], ResMut[Assets[Mesh]] }, function(commands, asset_server, meshes)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    hand = commands:spawn({
        SceneRoot = asset_server:load("modules/gltf/mod_registry/tests/fixtures/markers.glb#Scene0"),
        Transform = { translation = { x = 100, y = 0, z = 0 } },
    }):id()
    local cube = meshes:add(Cuboid.new(1, 1, 1))
    for i = 1, 5 do
        commands:spawn({
            Mesh3d = cube,
            Transform = { translation = { x = i * 2, y = 0, z = 0 } },
            ["collider/mesh"] = {},
            ChildOf = hand,
        })
    end
end)

-- Spends the frame's slice ahead of the build while K1 runs, so it builds a few a frame.
app:add_systems(Update, {}, function()
    if phase == "k1" then
        local from = os.clock()
        repeat until os.clock() - from > 0.03
    end
end):in_set("zz/status_suite_hog"):before("collider/mesh/build")

-- Per root: { added, changed, removed, states, early }. `early` counts frames whose "done"
-- had a carrier under the root that was not built.
local seen = { hand = { added = 0, changed = 0, removed = 0, states = {}, early = 0 },
               scene = { added = 0, changed = 0, removed = 0, states = {}, early = 0 },
               late = { added = 0, changed = 0, removed = 0, states = {}, early = 0 } }
-- The frame each of the scene's carriers first had the base.
local based = {}

local function which(id)
    if id == hand then
        return seen.hand
    elseif id == scene then
        return seen.scene
    elseif id == late then
        return seen.late
    end
end

local function status_of(world, id)
    local row = world:query({ iter_many = { id }, with = { "collider/status" } })[1]
    return row and row:get("collider/status").state
end

local function shapes_under(world, id)
    return world:query({ iter_many = world:descendants(id), with = { "collider/mesh/shape" } })
end

local function unbuilt_under(world, id)
    local n = 0
    for _, e in ipairs(world:query({
        iter_many = world:descendants(id),
        any_of = { "collider/mesh", "collider/bb" },
        optional = { "collider", "Name" },
    })) do
        local c = e:get("collider")
        if c == nil or c.built ~= true then
            n = n + 1
        end
        local name = e:has("Name") and e:get("Name").name
        if c ~= nil and name ~= nil and based[name] == nil then
            based[name] = frame
        end
    end
    return n
end

app:add_systems(Update, {
    World,
    Query[{ added = { "collider/status" } }],
    Query[{ changed = { "collider/status" } }],
    Query[{ removed = { "collider/status" } }],
}, function(world, added, changed, removed)
    frame = frame + 1
    for _, e in ipairs(added:iter()) do
        local s = which(e:id())
        if s then s.added = s.added + 1 end
    end
    for _, e in ipairs(changed:iter()) do
        local s = which(e:id())
        if s then s.changed = s.changed + 1 end
    end
    for _, e in ipairs(removed:iter()) do
        local s = which(e:id())
        if s then
            s.removed = s.removed + 1
            s.states[#s.states + 1] = "removed"
        end
    end
    for _, id in ipairs({ hand, scene }) do
        local s = which(id)
        local row = world:query({ iter_many = { id }, with = { "collider/status" } })[1]
        local state = row and row:get("collider/status").state
        if state ~= nil and state ~= s.states[#s.states] then
            s.states[#s.states + 1] = state
        end
        if state == "done" and unbuilt_under(world, id) > 0 then
            s.early = s.early + 1
        elseif id == scene then
            unbuilt_under(world, id)
        end
    end
    if late ~= nil then
        local state = status_of(world, late)
        if state ~= nil and state ~= seen.late.states[#seen.late.states] then
            seen.late.states[#seen.late.states + 1] = state
        end
        if state == "done" and #shapes_under(world, late) < 2 then
            seen.late.early = seen.late.early + 1
        end
    end
end):in_set("zz/status_suite_recorder"):after("collider/status")

local reloaded = {}

app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        reloaded[#reloaded + 1] = tostring(event.path)
    end
end):in_set("zz/status_suite_reloads")

local function was_reloaded(file)
    for _, path in ipairs(reloaded) do
        if path:find(file, 1, true) then
            return true
        end
    end
    return false
end

local function touch(file)
    local path = "assets/" .. file
    write_file_bytes(path, read_file_bytes(path))
end

local function status(world, id)
    local row = world:query({ iter_many = { id }, with = { "collider/status" } })[1]
    return row and row:get("collider/status").state
end

local function reset(s)
    s.added, s.changed, s.removed, s.states, s.early = 0, 0, 0, {}, 0
end

app:add_systems(Update, { World, Commands, Res[AssetServer] }, function(world, commands, asset_server)
    clock = clock + (world:delta_time() or 0)
    frames = frames + 1
    local function step(next_phase) phase, clock, frames = next_phase, 0, 0 end

    -- The wait also lets Bevy's watcher report the copy's creation before the copy is loaded.
    if phase == "k1" and status(world, hand) == "done" and clock > 1.5 then
        local s = seen.hand
        print("[STATUS SUITE] K1 states " .. table.concat(s.states, " > "))
        T("K1_building_first", s.states[1] == "building", table.concat(s.states, " > "))
        T("K1_done_after_the_last", s.states[#s.states] == "done" and unbuilt_under(world, hand) == 0,
            table.concat(s.states, " > "))
        T("K1_never_done_early", s.early == 0, s.early .. " early frames")
        T("K1_one_add_and_one_change", s.added == 1 and s.changed == 2,
            string.format("added %d changed %d", s.added, s.changed))
        scene = commands:spawn({
            SceneRoot = asset_server:load(COPY .. "#Scene0"),
            Transform = {},
            ["gltf/mod_registry"] = {},
        }):id()
        step("k2")

    elseif phase == "k2" and status(world, scene) == "done" and frames > 10 then
        local s = seen.scene
        print("[STATUS SUITE] K2 states " .. table.concat(s.states, " > ") .. string.format(
            " | base frames floor %s box %s", tostring(based.fx_floor), tostring(based.fx_box)))
        T("K2_done_once_both_kinds_are_built", unbuilt_under(world, scene) == 0, "unbuilt left")
        T("K5_every_carrier_of_one_pass_gets_the_base_in_the_same_frame",
            based.fx_floor ~= nil and based.fx_floor == based.fx_box,
            string.format("floor %s box %s", tostring(based.fx_floor), tostring(based.fx_box)))
        T("K5_never_done_early", s.early == 0, s.early .. " early frames")
        reset(s)
        reset(seen.hand)
        -- Same length, so the binary chunk's offsets stay right.
        write_file_bytes("assets/" .. COPY, (SOURCE:gsub("fx/json", "fx/nosj")))
        step("k3")

    -- The first state recorded is the "done" it had before the re-export.
    elseif phase == "k3" and #seen.scene.states >= 3 and status(world, scene) == "done" and clock > 1 then
        local s = seen.scene
        print("[STATUS SUITE] K3 states " .. table.concat(s.states, " > "))
        T("K3_a_reexport_leaves_done", s.states[1] == "done" and (s.states[2] == "building" or s.states[2] == "removed"),
            table.concat(s.states, " > "))
        T("K3_then_done_again", s.states[#s.states] == "done" and unbuilt_under(world, scene) == 0,
            table.concat(s.states, " > "))
        T("K3_never_done_early", s.early == 0, s.early .. " early frames")
        reset(s)
        commands:entity(scene):remove("gltf/mod_registry")
        step("k4")

    elseif phase == "k4" and clock > 1 then
        local s = seen.scene
        T("K4_the_status_goes_with_the_last_carrier", status(world, scene) == nil and s.removed == 1,
            "status " .. tostring(status(world, scene)) .. " removed " .. s.removed)
        T("K4_another_scenes_status_is_untouched", status(world, hand) == "done"
            and seen.hand.added + seen.hand.changed + seen.hand.removed == 0,
            string.format("added %d changed %d removed %d", seen.hand.added, seen.hand.changed, seen.hand.removed))
        late = commands:spawn({
            SceneRoot = asset_server:load(LATE .. "#Scene0"),
            Transform = { translation = { x = 200, y = 0, z = 0 } },
            ["collider/mesh"] = {},
        }):id()
        step("k6")

    elseif phase == "k6" and clock > 2 then
        T("K6_building_while_its_scene_loads", status(world, late) == "building" and #shapes_under(world, late) == 0,
            "status " .. tostring(status(world, late)) .. " shapes " .. #shapes_under(world, late))
        write_file_bytes("assets/" .. LATE, SOURCE)
        step("k6_loaded")

    elseif phase == "k6_loaded" and status(world, late) == "done" and clock > 1 then
        local prims = world:query({ iter_many = world:descendants(late), with = { "Mesh3d" } })
        print("[STATUS SUITE] K6 states " .. table.concat(seen.late.states, " > "))
        T("K6_done_once_its_scene_has_its_shapes", #prims == 2 and #shapes_under(world, late) == #prims,
            "shapes " .. #shapes_under(world, late) .. " primitives " .. #prims)
        T("K6_never_done_early", seen.late.early == 0, seen.late.early .. " early frames")
        touch("modules/collider/init.lua")
        step("k7")

    elseif phase == "k7" and was_reloaded("collider/init.lua") then
        step("k7_reloaded")

    elseif phase == "k7_reloaded" and clock > 1.5 then
        T("K7_after_a_reload_each_root_is_done_with_one_shape_a_carrier",
            status(world, hand) == "done" and status(world, late) == "done"
                and #shapes_under(world, hand) == 5 and #shapes_under(world, late) == 2,
            string.format("hand %s %d shapes, late %s %d shapes", tostring(status(world, hand)),
                #shapes_under(world, hand), tostring(status(world, late)), #shapes_under(world, late)))
        os.remove("assets/" .. COPY)
        os.remove("assets/" .. LATE)
        phase = "done"
        suite.finish("ColliderStatusSuite")
    end

    if phase ~= "done" and clock > 15 then
        T("K0_reached_" .. phase, false, "stuck for 15 s; scene states "
            .. table.concat(seen.scene.states, " > ") .. "; hand " .. table.concat(seen.hand.states, " > "))
        os.remove("assets/" .. COPY)
        os.remove("assets/" .. LATE)
        phase = "done"
        suite.finish("ColliderStatusSuite")
    end
end):in_set("zz/status_suite"):after("zz/status_suite_recorder")
