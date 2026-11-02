-- --host
-- Searches when the frame's slice is already spent: a system ahead of them burns the slice, so each
-- run looks at two regions, the first poll of a run answering false, and stops. A strip of regions, which a search walks end to end.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("NavBudgetSuite")

local LENGTH = 120

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    for i = 1, LENGTH do
        commands:spawn({ ["ai/nav/region"] = { min_x = i * 10, max_x = (i + 1) * 10, min_z = 0, max_z = 10 } })
    end
    for _, name in ipairs({ "a", "b", "c", "calm", "dropped", "moved", "handed" }) do
        commands:spawn({
            ["zz/name"] = { name = name },
            ["ai/nav"] = {},
            Transform = { translation = { x = 15, y = 0, z = 5 } },
        })
    end
end)

local hogging = false
app:add_systems(PreUpdate, {}, function()
    if hogging then
        local from = os.clock()
        repeat until os.clock() - from > 0.006
    end
end):in_set("zz/nav_budget_suite_hog"):before("ai/nav/solve")

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/nav/request", "ai/nav/path", "ai/nav/serving", "ai/nav/search" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local function ask(commands, world, name, x)
    commands:entity(named(world, name):id()):patch({ ["ai/nav/request"] = { go = { to = { x = x, y = 0, z = 5 } } } })
end

local function last_of(path)
    return path.path[#path.path]
end

local function regions_looked_at(job)
    local n = 0
    for _ in pairs(job.closed) do
        n = n + 1
    end
    return n
end

-- Frames a job was under way, frames it got no further, and the most under way at once.
local job_frames, stalls, most_started, last_looked = 0, 0, 0, nil
app:add_systems(Update, {
    Query[{ with = { "zz/name", "ai/nav/search" } }],
}, function(rows)
    local started = 0
    for _, e in ipairs(rows:iter()) do
        local job = e:get("ai/nav/search").job
        if job then
            started = started + 1
            local looked = regions_looked_at(job)
            if last_looked ~= nil and looked <= last_looked and started == 1 then
                stalls = stalls + 1
            end
            last_looked = started == 1 and looked or last_looked
        end
    end
    if started > 0 then
        job_frames = job_frames + 1
    else
        last_looked = nil
    end
    most_started = math.max(most_started, started)
end):in_set("zz/nav_budget_suite_count")

local phase, clock = "ready", 0
local END_X = (LENGTH + 0.5) * 10

app:add_systems(Update, { World, Res[Time], Res["ai/nav/graph"], Commands }, function(world, time, graph, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local ok, g = pcall(function() return graph:get() end)
    local count = ok and #g.regions or 0

    if phase == "ready" and count == LENGTH and named(world, "calm"):has("ai/nav/request") then
        ask(commands, world, "calm", END_X)
        step("calm")

    elseif phase == "calm" and named(world, "calm"):has("ai/nav/path") then
        local p = named(world, "calm"):get("ai/nav/path")
        suite.assert_test("B0a_with_the_frame_to_itself_it_finds_the_way", p.status == "ready" and #p.path == LENGTH, "waypoints " .. #p.path)
        job_frames, stalls, most_started = 0, 0, 0
        hogging = true
        ask(commands, world, "a", END_X)
        step("one")

    elseif phase == "one" and named(world, "a"):has("ai/nav/path") then
        local p = named(world, "a"):get("ai/nav/path")
        suite.assert_test("B1_with_the_slice_spent_a_search_carries_on_across_frames", job_frames >= LENGTH / 3, "frames " .. job_frames)
        suite.assert_test("B1b_and_gets_further_every_frame", stalls == 0, "stalls " .. stalls)
        suite.assert_test("B2_and_finds_the_same_way", p.status == "ready" and #p.path == LENGTH and #p.regions == LENGTH,
            "waypoints " .. #p.path)
        suite.assert_test("B3_the_search_goes_when_it_is_answered", not named(world, "a"):has("ai/nav/search"), "")
        most_started = 0
        ask(commands, world, "a", END_X - 10)
        ask(commands, world, "b", END_X)
        ask(commands, world, "c", END_X)
        step("three")

    elseif phase == "three" and last_of(named(world, "a"):get("ai/nav/path")).x == END_X - 10
        and named(world, "b"):has("ai/nav/path") and named(world, "c"):has("ai/nav/path") then
        suite.assert_test("B4_searches_go_one_at_a_time", most_started == 1, "most under way at once " .. most_started)
        suite.assert_test("B4b_and_every_one_is_answered", #named(world, "b"):get("ai/nav/path").path == LENGTH
            and #named(world, "c"):get("ai/nav/path").path == LENGTH, "")
        ask(commands, world, "dropped", END_X)
        step("dropping")

    elseif phase == "dropping" and named(world, "dropped"):has("ai/nav/search")
        and named(world, "dropped"):get("ai/nav/search").job then
        commands:entity(named(world, "dropped"):id()):patch({ ["ai/nav/request"] = { go = null } })
        step("dropped")

    elseif phase == "dropped" and clock > 0.5 then
        local d = named(world, "dropped")
        suite.assert_test("B5_a_search_whose_entry_has_gone_is_dropped",
            not d:has("ai/nav/search") and not d:has("ai/nav/path") and not d:has("ai/nav/serving"), "")
        ask(commands, world, "moved", END_X)
        step("moving")

    elseif phase == "moving" and named(world, "moved"):has("ai/nav/search")
        and named(world, "moved"):get("ai/nav/search").job then
        ask(commands, world, "moved", END_X - 200)
        step("moved")

    elseif phase == "moved" and named(world, "moved"):has("ai/nav/path") then
        suite.assert_test("B6_a_search_for_an_old_place_is_not_answered",
            last_of(named(world, "moved"):get("ai/nav/path")).x == END_X - 200,
            "goal " .. tostring(last_of(named(world, "moved"):get("ai/nav/path")).x))
        ask(commands, world, "handed", 16)
        step("short answer")

    elseif phase == "short answer" and named(world, "handed"):has("ai/nav/path") then
        commands:entity(named(world, "handed"):id()):patch({
            ["ai/nav/request"] = { go = null, other = { to = { x = END_X, y = 0, z = 5 } } },
        })
        step("handing over")

    elseif phase == "handing over" and named(world, "handed"):has("ai/nav/search")
        and named(world, "handed"):get("ai/nav/search").job then
        suite.assert_test("B7_a_path_whose_entry_has_gone_goes_at_once_with_the_next_still_searching",
            not named(world, "handed"):has("ai/nav/path"), "")
        step("handed over")

    elseif phase == "handed over" and named(world, "handed"):has("ai/nav/path") then
        suite.assert_test("B8_and_the_next_is_answered", last_of(named(world, "handed"):get("ai/nav/path")).x == END_X, "")
        -- Answers that need no search: a run answers two and stops.
        ask(commands, world, "b", 16)
        ask(commands, world, "c", 17)
        ask(commands, world, "calm", 18)
        step("near")

    elseif phase == "near" and last_of(named(world, "b"):get("ai/nav/path")).x == 16 and last_of(named(world, "c"):get("ai/nav/path")).x == 17
        and last_of(named(world, "calm"):get("ai/nav/path")).x == 18 then
        local b, c, calm = named(world, "b"):get("ai/nav/path").solved_id, named(world, "c"):get("ai/nav/path").solved_id,
            named(world, "calm"):get("ai/nav/path").solved_id
        suite.assert_test("B9_answers_with_no_search_spend_the_slice_too", not (b == c and c == calm), "")
        hogging = false
        phase = "done"
        suite.finish("NavBudgetSuite")
    end

    if phase ~= "done" and clock > 20 then
        suite.assert_test("B0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 20 s")
        hogging = false
        phase = "done"
        suite.finish("NavBudgetSuite")
    end
end):in_set("zz/nav_budget_suite")
