-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")
local AssetServer = require("bevy::asset::AssetServer")

local suite = helpers.create_suite("VolumesSuite")

-- A floor of half size `half` with its top at y = 0, 200 m apart per slot.
local function floor_at(commands, slot, half)
    commands:spawn({
        ["zz/floor"] = { slot = slot },
        Transform = { translation = { x = slot * 200, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = half, hy = 0.5, hz = half } },
    })
end

-- A carrier with one volume below it, half size `half`, floor at y = 0.
local function carrier(commands, name, slot, half, cfg)
    local parent = commands:spawn({
        ["zz/name"] = { name = name },
        ["ai/nav/volumes"] = cfg,
        Transform = { translation = { x = slot * 200, y = 0, z = 0 } },
    }):id()
    commands:spawn({
        ["zz/volume"] = { name = name },
        ["ai/nav/volume"] = { hx = half, hy = 1, hz = half },
        Transform = { translation = { x = 0, y = 1, z = 0 } },
        ChildOf = parent,
    })
end

app:add_systems(Startup, { Commands, Res[AssetServer] }, function(commands, assets)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })

    floor_at(commands, 1, 20)
    carrier(commands, "open", 1, 5, { cost = 3 })
    -- A mover standing on it is not floor, and a mover is not a hole.
    commands:spawn({
        ["zz/mover"] = {},
        Transform = { translation = { x = 200, y = 0.6, z = 0 } },
        RigidBody3d = "Dynamic",
        Collider3d = { cuboid = { hx = 1, hy = 0.5, hz = 1 } },
    })

    floor_at(commands, 2, 20)
    carrier(commands, "holed", 2, 5, {})
    commands:spawn({
        ["zz/pillar"] = {},
        Transform = { translation = { x = 400, y = 2, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 1, hy = 2, hz = 1 } },
    })

    carrier(commands, "void", 3, 5, {})

    carrier(commands, "trusted", 4, 3, { sample = false })

    floor_at(commands, 5, 40)
    carrier(commands, "sliced", 5, 10, { rays_per_frame = 10 })

    floor_at(commands, 6, 20)
    carrier(commands, "slow", 6, 2, { settle = 1.5 })

    -- its own volume, with no child
    floor_at(commands, 7, 20)
    commands:spawn({
        ["zz/name"] = { name = "itself" },
        ["ai/nav/volumes"] = {},
        ["ai/nav/volume"] = { hx = 2, hy = 0, hz = 2 },
        Transform = { translation = { x = 1400, y = 0, z = 0 } },
    })

    floor_at(commands, 8, 20)
    carrier(commands, "resized", 8, 2, {})

    floor_at(commands, 9, 20)
    carrier(commands, "doomed", 9, 2, {})

    carrier(commands, "late", 10, 2, {})

    -- A budget of one ray a frame, so its frames count its rays: one floor, then one under a slab.
    floor_at(commands, 14, 20)
    carrier(commands, "one storey", 14, 2, { rays_per_frame = 1 })
    floor_at(commands, 15, 20)
    commands:spawn({
        Transform = { translation = { x = 3000, y = 3, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 15, hy = 0.1, hz = 15 } },
    })
    carrier(commands, "two storeys", 15, 2, { rays_per_frame = 1 })
    -- A plate thinner than the ray's step under a floor: the ray is under it, not in it.
    floor_at(commands, 16, 20)
    commands:spawn({
        Transform = { translation = { x = 3200, y = 3, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 15, hy = 0.002, hz = 15 } },
    })
    carrier(commands, "plate", 16, 2, {})
    -- A headroom of its own: the same slab, too low for this one.
    floor_at(commands, 17, 20)
    commands:spawn({
        Transform = { translation = { x = 3400, y = 3, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 15, hy = 0.1, hz = 15 } },
    })
    carrier(commands, "tall", 17, 2, { headroom = 3 })

    -- Changed while it samples.
    floor_at(commands, 12, 40)
    carrier(commands, "midway", 12, 10, { rays_per_frame = 5 })

    floor_at(commands, 13, 20)
    carrier(commands, "emptied", 13, 2, {})

    -- Its floor goes without any other change; a changed scene file is what makes it look again.
    commands:spawn({
        ["zz/refloor"] = {},
        Transform = { translation = { x = 2200, y = -0.5, z = 0 } },
        RigidBody3d = "Fixed",
        Collider3d = { cuboid = { hx = 20, hy = 0.5, hz = 20 } },
        SceneRoot = assets:load("Placeholder-Character/Model.glb#Scene0"),
    })
    carrier(commands, "reexported", 11, 2, {})
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/nav/volumes", "ai/nav/volumes/job", "ai/nav/volumes/due", "Children" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function regions_of(world, name)
    local e = named(world, name)
    local out = {}
    for _, r in ipairs(world:query({
        iter_many = e and (e:get("Children") or {}) or {},
        with = { "ai/nav/region", "ai/nav/volumes/region" },
    })) do
        out[#out + 1] = r:get("ai/nav/region")
    end
    return out
end

local function near(a, b, tolerance) return a ~= nil and math.abs(a - b) < (tolerance or 1e-3) end

local function covers(regions, x, z)
    for _, r in ipairs(regions) do
        if x > r.min_x and x < r.max_x and z > r.min_z and z < r.max_z then
            return true
        end
    end
    return false
end

-- How many frames showed a job in flight, and regions ever added.
local job_seen = 0
local added_regions = 0
app:add_systems(Update, {
    Query[{ added = { "ai/nav/volumes/region" } }],
}, function(added)
    for _ in ipairs(added:iter()) do
        added_regions = added_regions + 1
    end
end):in_set("zz/volumes_suite_count")

local slow_early, midway_changed = nil, false
local job_frames = { ["one storey"] = 0, ["two storeys"] = 0 }
local phase, clock = "settling", 0
local added_before = 0

app:add_systems(Update, { World, Res[Time], Res[AssetServer], Res["ai/nav/graph"], Commands }, function(world, time, assets, graph, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    local sliced = named(world, "sliced")
    if sliced and sliced:has("ai/nav/volumes/job") then
        job_seen = job_seen + 1
    end

    for name in pairs(job_frames) do
        local counted = named(world, name)
        if counted and counted:has("ai/nav/volumes/job") then
            job_frames[name] = job_frames[name] + 1
        end
    end

    local midway = named(world, "midway")
    if midway and midway:has("ai/nav/volumes/job") and not midway_changed then
        midway_changed = true
        for _, v in ipairs(world:query({ with = { "zz/volume" } })) do
            if v:get("zz/volume").name == "midway" then
                commands:entity(v:id()):patch({ ["ai/nav/volume"] = { hx = 5 } })
            end
        end
    end

    if phase == "settling" and clock > 1 then
        slow_early = #regions_of(world, "slow")
        step("baked")

    elseif phase == "baked" and #regions_of(world, "sliced") > 0 and #regions_of(world, "slow") > 0
        and #regions_of(world, "midway") > 0 and #regions_of(world, "two storeys") > 0 and #regions_of(world, "one storey") > 0 then
        local cfg = named(world, "open"):get("ai/nav/volumes")
        local given = named(world, "sliced"):get("ai/nav/volumes")
        suite.assert_test("V1_missing_fields_get_defaults_and_given_ones_stay",
            cfg.sample == true and cfg.cell == 1 and near(cfg.max_step, 0.45) and cfg.cost == 3 and near(cfg.settle, 0.35)
                and cfg.rays_per_frame == 400 and given.rays_per_frame == 10, "")

        local open = regions_of(world, "open")
        suite.assert_test("V2_a_clear_floor_is_one_region_of_the_volumes_size_at_its_height",
            #open == 1 and open[1].min_x == 195 and open[1].max_x == 205 and open[1].min_z == -5 and open[1].max_z == 5
                and near(open[1].y, 0, 0.01), "regions " .. #open)
        suite.assert_test("V3_a_region_has_the_cost_given", open[1].cost == 3, tostring(open[1].cost))

        local holed = regions_of(world, "holed")
        local answer = {}
        for _, r in ipairs(holed) do
            answer[#answer + 1] = string.format("%g %g %g %g %.3f", r.min_x, r.max_x, r.min_z, r.max_z, r.y)
        end
        table.sort(answer)
        -- As it stood before floors were counted: a single-floor map gives exactly this.
        suite.assert_test("V4b_a_single_floor_map_gives_what_it_always_gave", table.concat(answer, "|")
            == "395 398 -1 5 0.000|395 399 -2 -1 0.000|395 405 -5 -2 0.000|398 399 1 5 0.000|399 401 2 5 0.000|401 402 1 5 0.000|401 405 -2 -1 0.000|402 405 -1 5 0.000",
            table.concat(answer, "|"))
        suite.assert_test("V4_an_obstacle_is_a_hole_the_ground_around_it_stays",
            #holed >= 2 and not covers(holed, 400, 0) and covers(holed, 396, 0) and covers(holed, 404, 4),
            "regions " .. #holed)
        suite.assert_test("V5_no_floor_is_no_regions", #regions_of(world, "void") == 0 and not named(world, "void"):has("ai/nav/volumes/due"), "")

        local trusted = regions_of(world, "trusted")
        suite.assert_test("V6_sample_false_trusts_the_volume_with_no_floor_under_it",
            #trusted == 1 and trusted[1].min_x == 797 and trusted[1].max_x == 803 and near(trusted[1].y, 0, 0.01), "")

        local cut = regions_of(world, "sliced")
        suite.assert_test("V7_a_small_budget_bakes_over_frames_to_the_same_answer",
            job_seen > 5 and #cut == 1 and cut[1].min_x == 990 and cut[1].max_x == 1010, "job frames " .. job_seen)
        suite.assert_test("V8_nothing_is_baked_before_it_settles", slow_early == 0 and #regions_of(world, "slow") == 1,
            "early " .. tostring(slow_early))

        local itself = regions_of(world, "itself")
        suite.assert_test("V9_a_volume_on_the_entity_itself_counts", #itself == 1 and itself[1].min_x == 1398, "")

        suite.assert_test("V7b_a_column_on_one_floor_costs_one_ray", job_frames["one storey"] >= 15 and job_frames["one storey"] <= 17,
            "frames " .. job_frames["one storey"])
        suite.assert_test("V7c_a_storey_above_it_costs_three_more", job_frames["two storeys"] >= 63 and job_frames["two storeys"] <= 65,
            "frames " .. job_frames["two storeys"])
        local floors_of = function(name)
            local ys = {}
            for _, r in ipairs(regions_of(world, name)) do
                ys[#ys + 1] = string.format("%.1f", r.y)
            end
            table.sort(ys)
            return table.concat(ys, " ")
        end
        suite.assert_test("V7d_it_finds_each_floor_under_a_slab", floors_of("two storeys") == "0.0 3.1", floors_of("two storeys"))
        suite.assert_test("V7e_and_under_a_plate_too_thin_to_be_inside", floors_of("plate") == "0.0 3.0", floors_of("plate"))
        suite.assert_test("V7f_headroom_is_a_field", floors_of("tall") == "3.1", floors_of("tall"))
        suite.assert_test("V7g_headroom_defaults_to_two_metres", named(world, "open"):get("ai/nav/volumes").headroom == 2, "")
        local mid = regions_of(world, "midway")
        suite.assert_test("V10b_a_change_while_it_samples_starts_it_again",
            #mid == 1 and mid[1].min_x == 2395 and mid[1].max_x == 2405,
            string.format("regions %d x %s", #mid, tostring(mid[1] and mid[1].min_x)))
        suite.assert_test("V10_a_finished_bake_leaves_no_job",
            not named(world, "open"):has("ai/nav/volumes/job") and not named(world, "open"):has("ai/nav/volumes/due"), "")

        for _, v in ipairs(world:query({ with = { "zz/volume" } })) do
            if v:get("zz/volume").name == "resized" then
                commands:entity(v:id()):patch({ ["ai/nav/volume"] = { hx = 4 } })
            end
        end
        for _, m in ipairs(world:query({ with = { "zz/mover" } })) do
            commands:entity(m:id()):despawn()
        end
        commands:spawn({ ["zz/name"] = { name = "scout" }, ["ai/nav"] = {} })
        step("resized")

    elseif phase == "resized" and #regions_of(world, "resized") == 1 and regions_of(world, "resized")[1].max_x == 1604 then
        suite.assert_test("V11_a_changed_volume_replaces_its_regions_and_stacks_none", true, "")
        for _, v in ipairs(world:query({ with = { "zz/volume" } })) do
            if v:get("zz/volume").name == "emptied" then
                commands:entity(v:id()):despawn()
            end
        end
        local ok, g = pcall(function() return graph:get() end)
        local whole = false
        for _, r in ipairs(ok and g.regions or {}) do
            whole = whole or (r.min_x == 195 and r.max_x == 205)
        end
        suite.assert_test("V13_the_graph_holds_what_was_baked", whole, "")
        step("emptying")

    -- Any volume going owes every carrier a bake, so the next steps wait for that to be over.
    elseif phase == "emptying" and clock > 0.8 then
        floor_at(commands, 10, 20)
        step("floor arriving")

    -- A plain collider arriving looks like nothing, but a scene arriving makes it look again.
    elseif phase == "floor arriving" and clock > 0.8 then
        suite.assert_test("V14_a_new_collider_alone_rebakes_nothing", #regions_of(world, "late") == 0, "")
        suite.assert_test("V14b_with_its_last_volume_gone_its_regions_go", #regions_of(world, "emptied") == 0, "")
        commands:spawn({ Transform = {}, SceneRoot = assets:load("Placeholder-Character/Model.glb#Scene0") })
        step("scene arrived")

    elseif phase == "scene arrived" and #regions_of(world, "late") == 1 then
        suite.assert_test("V15_a_new_scene_rebakes", true, "")
        for _, f in ipairs(world:query({ with = { "zz/refloor" } })) do
            commands:entity(f:id()):remove("Collider3d")
        end
        step("refloor gone")

    elseif phase == "refloor gone" and clock > 0.5 then
        suite.assert_test("V16_a_collider_going_rebakes_nothing", #regions_of(world, "reexported") == 1,
            "regions " .. #regions_of(world, "reexported"))
        local glb = "assets/Placeholder-Character/Model.glb"
        write_file_bytes(glb, read_file_bytes(glb))
        step("reexported")

    elseif phase == "reexported" and #regions_of(world, "reexported") == 0 then
        suite.assert_test("V17_a_changed_scene_file_rebakes", true, "")
        added_before = added_regions
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local path = "assets/modules/ai/nav/volumes/server/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloaded")

    -- The watcher polls the file every 5 s; the reload reaps the regions and bakes them again.
    elseif phase == "reloaded" and added_regions > added_before and clock > 0.5
        and not named(world, "open"):has("ai/nav/volumes/due") and not named(world, "sliced"):has("ai/nav/volumes/due") then
        local open = regions_of(world, "open")
        suite.assert_test("V18_after_a_reload_each_has_its_regions_once",
            #open == 1 and open[1].cost == 3 and #regions_of(world, "sliced") == 1 and #regions_of(world, "resized") == 1,
            string.format("open %d sliced %d resized %d", #open, #regions_of(world, "sliced"), #regions_of(world, "resized")))
        commands:entity(named(world, "doomed"):id()):remove("ai/nav/volumes")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        local doomed = named(world, "doomed")
        suite.assert_test("V19_removing_it_takes_its_regions_and_keeps_the_entity",
            #regions_of(world, "doomed") == 0 and not doomed:has("ai/nav/volumes"), "regions " .. #regions_of(world, "doomed"))
        suite.assert_test("V20_the_others_keep_theirs", #regions_of(world, "open") == 1, "")
        phase = "done"
        suite.finish("VolumesSuite")
    end

    if phase ~= "done" and clock > 15 then
        suite.assert_test("V0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 15 s")
        phase = "done"
        suite.finish("VolumesSuite")
    end
end):in_set("zz/volumes_suite")
