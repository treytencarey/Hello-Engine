-- transfers across VMs: two libraries in VMs of their own, a world using both (this VM) and a
-- second world using one. Each library VM states a download as core does, a shared
-- `core/library/download { ref, ... }` row, a child of its shared library entity; each world states
-- its own content library's download the same way, under a library entity of its own that is not
-- shared, and asks its libraries with `core/library/fetch` rows, as `core/library/require` writes them.
--
--   M1 measured: a mirrored row's ChildOf is the mirror of its library entity; under a parent that
--      is not shared, the mirror has none
--   T1 this world lists its own download and both its libraries', not the other world's
--   T2 the other world lists its own and the one library it asks, not this world's nor the library
--      it doesn't ask
--   T3 a library's download moving moves its line in both worlds that ask it
--   T4 a library's download gone is gone from the world's list
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("TransfersSharedSuite")
local T = suite.assert_test

local MB = 1024 * 1024
local DEFAULTS = { b_lines = "", l1_move = false, l2_drop = false }
local ts = helpers.shared_state("TransfersSharedState", DEFAULTS)

-- Reads a world's list: its lines' text, sorted, joined by " | ". Required by both worlds.
helpers.make_fixture("modules/test_fixtures/gen_transfers_shared_lines.lua", [=[
return function(world)
    local list = world:query({ with = { "transfers/list" } })[1]
    if not list then return "" end
    local parent = {}
    for _, e in ipairs(world:query({ with = { "ChildOf" } })) do parent[e:id()] = e:get("ChildOf") end
    local out = {}
    for _, t in ipairs(world:query({ with = { "Text", "ChildOf" } })) do
        local line = parent[t:id()]
        if line and parent[line] == list:id() then out[#out + 1] = tostring(t:get("Text")) end
    end
    table.sort(out)
    return table.concat(out, " | ")
end
]=])

-- A library VM: its shared library entity, then a download under it.
helpers.make_fixture("modules/test_fixtures/gen_transfers_shared_lib.lua", [=[
require("modules/core/mod_registry/init.lua")
local boot = require("modules/core/instances.lua").boot_data()
local ts = require("modules/core/test_helpers.lua").shared_state("TransfersSharedState", boot.DEFAULTS)
local frames, lib, row, moved, dropped = 0, nil, nil, false, false
app:add_systems(Update, { World, Commands }, function(world, commands)
    frames = frames + 1
    if not lib then
        lib = commands:spawn({ ["zz/trs/library"] = { ref = boot.ref }, WorldShared = {}, ["core/net/sync"] = false }):id()
    elseif not row and frames > 10 then
        row = commands:spawn({ ["core/library/download"] = { ref = boot.ref, path = boot.path, total = boot.total, got = boot.got },
            ChildOf = lib, WorldShared = {}, ["core/net/sync"] = false }):id()
    elseif row and boot.move and ts.l1_move and not moved then
        moved = true
        world:get_entity(row):set({ ["core/library/download"] = { ref = boot.ref, path = boot.path, total = boot.total, got = boot.move } })
    elseif row and boot.drop and ts.l2_drop and not dropped then
        dropped = true
        commands:entity(row):despawn()
    end
end)
]=])

-- The other world: its own content library's download, an ask of the first library, and its icon hovered.
helpers.make_fixture("modules/test_fixtures/gen_transfers_shared_world.lua", [=[
require("modules/core/mod_registry/init.lua")
local boot = require("modules/core/instances.lua").boot_data()
local ts = require("modules/core/test_helpers.lua").shared_state("TransfersSharedState", boot.DEFAULTS)
local lines = require("modules/test_fixtures/gen_transfers_shared_lines.lua")
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ transfers = {} })
    commands:spawn({ ["core/library/fetch"] = { ref = "zz:L1", paths = {} }, WorldShared = {}, ["core/net/sync"] = false })
    local own = commands:spawn({ ["zz/trs/own"] = {} }):id()
    commands:spawn({ ["core/library/download"] = { ref = "zz:worldB", path = "maps/b_own.glb", total = 8 * 1024 * 1024, got = 2 * 1024 * 1024 },
        ChildOf = own, WorldShared = {}, ["core/net/sync"] = false })
end)
app:add_systems(Update, { World, Commands }, function(world, commands)
    local icon = world:query({ with = { "transfers/icon" }, optional = { "Interaction" } })[1]
    if icon and icon:get("Interaction") ~= "Hovered" then
        commands:entity(icon:id()):insert({ Interaction = "Hovered" })
    end
    local said = lines(world)
    if said ~= ts.b_lines then ts.b_lines = said end
end)
]=])

local LIB = "modules/test_fixtures/gen_transfers_shared_lib.lua"
helpers.spawn_vm(LIB, { DEFAULTS = DEFAULTS, ref = "zz:L1", path = "maps/one.glb", total = 4 * MB, got = 1 * MB, move = 3 * MB },
    { headless = true })
helpers.spawn_vm(LIB, { DEFAULTS = DEFAULTS, ref = "zz:L2", path = "maps/two.glb", total = 6 * MB, got = 3 * MB, drop = true },
    { headless = true })
helpers.spawn_vm("modules/test_fixtures/gen_transfers_shared_world.lua", { DEFAULTS = DEFAULTS }, { headless = true })

local lines = require("modules/test_fixtures/gen_transfers_shared_lines.lua")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ transfers = {} })
    for _, ref in ipairs({ "zz:L1", "zz:L2" }) do
        commands:spawn({ ["core/library/fetch"] = { ref = ref, paths = {} }, WorldShared = {}, ["core/net/sync"] = false })
    end
    local own = commands:spawn({ ["zz/trs/own"] = {} }):id()
    commands:spawn({ ["core/library/download"] = { ref = "zz:worldA", path = "maps/a_own.glb", total = 2 * MB, got = 1 * MB },
        ChildOf = own, WorldShared = {}, ["core/net/sync"] = false })
end)

local A_OWN, ONE, TWO = "down  maps/a_own.glb  1.0 / 2.0 MB", "down  maps/one.glb  1.0 / 4.0 MB", "down  maps/two.glb  3.0 / 6.0 MB"
local B_OWN = "down  maps/b_own.glb  2.0 / 8.0 MB"
local MOVED = "down  maps/one.glb  3.0 / 4.0 MB"
local function joined(...)
    local t = { ... }
    table.sort(t)
    return table.concat(t, " | ")
end

local phase, clock = "wait", 0
app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(p) phase, clock = p, 0 end
    if phase == "done" then return end
    local icon = world:query({ with = { "transfers/icon" }, optional = { "Interaction" } })[1]
    if icon and icon:get("Interaction") ~= "Hovered" then
        commands:entity(icon:id()):insert({ Interaction = "Hovered" })
    end
    local mine = lines(world)

    if phase == "wait" then
        local want_a, want_b = joined(A_OWN, ONE, TWO), joined(B_OWN, ONE)
        if (mine ~= want_a or ts.b_lines ~= want_b) and clock < 20 then return end
        -- M1: where the mirrors hang.
        local libs, parent_of = {}, {}
        for _, l in ipairs(world:query({ with = { "zz/trs/library", "WorldMirror" } })) do
            libs[l:get("zz/trs/library").ref] = l:id()
        end
        for _, r in ipairs(world:query({ with = { "core/library/download", "WorldMirror" }, optional = { "ChildOf" } })) do
            parent_of[r:get("core/library/download").path] = r:get("ChildOf") or false
        end
        T("M1_a_mirrored_row_hangs_under_its_librarys_mirror",
            libs["zz:L1"] ~= nil and parent_of["maps/one.glb"] == libs["zz:L1"] and parent_of["maps/b_own.glb"] == false,
            string.format("L1 mirror %s, one.glb under %s, b_own.glb under %s", tostring(libs["zz:L1"]),
                tostring(parent_of["maps/one.glb"]), tostring(parent_of["maps/b_own.glb"])))
        T("T1_this_world_lists_its_own_and_both_libraries", mine == want_a, mine)
        T("T2_the_other_world_lists_its_own_and_its_one_library", ts.b_lines == want_b, ts.b_lines)
        ts.l1_move = true
        step("moved")
    elseif phase == "moved" then
        local want_a, want_b = joined(A_OWN, MOVED, TWO), joined(B_OWN, MOVED)
        if (mine ~= want_a or ts.b_lines ~= want_b) and clock < 10 then return end
        T("T3_a_library_download_moving_moves_it_in_both_worlds", mine == want_a and ts.b_lines == want_b,
            mine .. " || " .. ts.b_lines)
        ts.l2_drop = true
        step("dropped")
    elseif phase == "dropped" then
        local want_a = joined(A_OWN, MOVED)
        if mine ~= want_a and clock < 10 then return end
        T("T4_a_library_download_gone_leaves_the_list", mine == want_a, mine)
        phase = "done"
        suite.finish("TRANSFERS_SHARED")
    end
end):in_set("zz/transfers_shared_flow")
