-- --host
-- A bake when the frame's slice is already spent: a system ahead of it burns the slice, so each run
-- casts two rays, the first poll of a run answering false, and stops. Two storeys, half a floor under a slab, and a calm bake to compare with.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("VolumesBudgetSuite")

local function building(commands, name, x)
    commands:spawn({
        Transform = { translation = { x = x, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 20, hy = 0.5, hz = 20 } },
    })
    commands:spawn({
        Transform = { translation = { x = x + 2, y = 3.9, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 2, hy = 0.1, hz = 8 } },
    })
    commands:spawn({
        ["zz/name"] = { name = name },
        ["ai/nav/volumes/box"] = { hx = 4, hz = 4, hy = 3, y = 3 },
        Transform = { translation = { x = x, y = 0, z = 0 } },
    })
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    building(commands, "calm", 0)
end)

local hogging = false
app:add_systems(Update, {}, function()
    if hogging then
        local from = os.clock()
        repeat until os.clock() - from > 0.006
    end
end):in_set("zz/volumes_budget_suite_hog"):before("ai/nav/volumes/bake")

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/nav/volumes/due", "ai/nav/volumes/job", "Children" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function baked(world, name)
    local e = named(world, name)
    return e ~= nil and not e:has("ai/nav/volumes/due") and not e:has("ai/nav/volumes/job")
        and #world:query({ iter_many = e:get("Children") or {}, with = { "ai/nav/volumes/region" } }) > 0
end

-- Its regions, placed relative to its entity, so two buildings compare.
local function regions_of(world, name, at)
    local out = {}
    for _, r in ipairs(world:query({
        iter_many = named(world, name):get("Children") or {},
        with = { "ai/nav/region", "ai/nav/volumes/region" },
    })) do
        local v = r:get("ai/nav/region")
        out[#out + 1] = string.format("%g %g %g %g %.2f %.2f %.2f", v.min_x - at, v.max_x - at, v.min_z, v.max_z, v.y, v.min_y, v.max_y)
    end
    table.sort(out)
    return table.concat(out, "|")
end

-- How far a job has got, as one value.
local function cursor(job)
    return string.format("%s %s %s %s %s %s", tostring(job.vi), tostring(job.iz), tostring(job.ix), tostring(job.y),
        tostring(job.inside), tostring(job.grid and "grid"))
end

local phase, clock = "calm", 0
local frames, stalls, crowded = 0, 0, 0
local last = {}
local midway_changed = false

-- A new volume owes every carrier a bake, so several jobs can be open. Each frame with one open,
-- how many of them got further: none is a stall, and more than one means the slice was not shared.
app:add_systems(Update, {
    Query[{ with = { "zz/name", "ai/nav/volumes/job" } }],
}, function(jobs)
    local moved, now = 0, {}
    for _, e in ipairs(jobs:iter()) do
        local name = e:get("zz/name").name
        now[name] = cursor(e:get("ai/nav/volumes/job"))
        if now[name] ~= last[name] then
            moved = moved + 1
        end
    end
    -- A job that finished got further too, though it has no row now.
    for name in pairs(last) do
        if now[name] == nil then
            moved = moved + 1
        end
    end
    if next(now) ~= nil and hogging then
        frames = frames + 1
        stalls = stalls + (moved == 0 and 1 or 0)
        crowded = crowded + (moved > 1 and 1 or 0)
    end
    last = now
end):in_set("zz/volumes_budget_suite_count")

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "calm" and baked(world, "calm") then
        hogging = true
        building(commands, "slow", 200)
        step("slow")

    elseif phase == "slow" and baked(world, "slow") then
        hogging = false
        -- 64 columns at most two rays a frame
        suite.assert_test("VB1_with_the_slice_spent_a_bake_carries_on_across_frames", frames >= 32, "frames " .. frames)
        suite.assert_test("VB2_and_gets_further_every_frame", stalls == 0, "stalls " .. stalls)
        local calm, spent = regions_of(world, "calm", 0), regions_of(world, "slow", 200)
        suite.assert_test("VB3_and_gives_the_same_regions", calm == spent and #calm > 0, "\n" .. calm .. "\n" .. spent)
        crowded = 0
        hogging = true
        building(commands, "first", 400)
        building(commands, "second", 600)
        step("two")

    elseif phase == "two" then
        if baked(world, "first") and baked(world, "second") then
            hogging = false
            suite.assert_test("VB4_only_one_carrier_gets_further_in_a_frame", crowded == 0, "frames with more " .. crowded)
            suite.assert_test("VB5_and_each_gives_its_regions", regions_of(world, "first", 400) == regions_of(world, "calm", 0)
                and regions_of(world, "second", 600) == regions_of(world, "calm", 0), "")
            hogging = true
            building(commands, "midway", 800)
            step("midway")
        end

    elseif phase == "midway" then
        local midway = named(world, "midway")
        if midway and midway:has("ai/nav/volumes/job") and not midway_changed then
            midway_changed = true
            commands:entity(midway:id()):patch({ ["ai/nav/volumes/box"] = { hx = 3 } })
        end
        if midway_changed and baked(world, "midway") then
            hogging = false
            local xs = {}
            for _, r in ipairs(world:query({
                iter_many = midway:get("Children") or {},
                with = { "ai/nav/region", "ai/nav/volumes/region" },
            })) do
                xs[#xs + 1] = r:get("ai/nav/region").min_x
            end
            table.sort(xs)
            suite.assert_test("VB6_a_change_while_it_samples_starts_it_again", xs[1] == 797, "lowest x " .. tostring(xs[1]))
            phase = "done"
            suite.finish("VolumesBudgetSuite")
        end
    end

    if phase ~= "done" and clock > 25 then
        suite.assert_test("VB0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 25 s")
        phase = "done"
        hogging = false
        suite.finish("VolumesBudgetSuite")
    end
end):in_set("zz/volumes_budget_suite")
