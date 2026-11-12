-- --host
-- The profiler panel on a real player, driven headless: `player/client` adds the carrier, a real
-- click on the sidebar's button opens it, and the store is the VM's own. What only a window can
-- show (layout, the pointer's hover) is in test_profiler_windowed.lua.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local DiagnosticsStore = require("bevy::diagnostic::DiagnosticsStore")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("ProfilerSuite")
local T = suite.assert_test

local MOD_FILE = "assets/modules/sidebar/profiler/init.lua"
local PANEL_FILE = "assets/modules/sidebar/panel/init.lua"
local SIDEBAR_FILE = "assets/modules/sidebar/init.lua"

-- A real reload rewrites a file under an immediate watcher. The watcher skips a file whose bytes it
-- has seen, so each rewrite differs, by a comment at the end, and the end of the suite puts them back.

local originals = {}
local rewrites = 0

local function reload(path, change_from, change_to)
    originals[path] = originals[path] or read_file_bytes(path)
    local source = originals[path]
    if change_from ~= nil then
        local from, to = source:find(change_from, 1, true)
        source = source:sub(1, from - 1) .. change_to .. source:sub(to + 1)
    end
    rewrites = rewrites + 1
    write_file_bytes(path, source .. "\n-- zz " .. rewrites .. "\n")
end

local function finish()
    for path, source in pairs(originals) do
        write_file_bytes(path, source)
    end
    suite.finish("PROFILER")
end

local camera, player

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ ["ui/theme/dark"] = {} })
    commands:spawn({ ["zz/work"] = {} })
    camera = commands:spawn({ ["zz/camera"] = {} }):id()
    player = commands:spawn({
        ["zz/player"] = {},
        player = { client_id = 1, spawn_index = 1 },
        ["core/net/sync"] = false,
    }):id()
    commands:spawn({
        ["zz/remote"] = {},
        player = { client_id = 2, spawn_index = 1 },
        ["core/net/sync"] = false,
    })
end)

local function spin(count)
    for _ = 1, count do local _ = math.sqrt(2) end
end

-- The suite's costs, set per phase.
local work = { own = 40000, other = 20000, slow = 0, ran_out = true }

app:add_systems(Update, { Query[{ with = { "zz/work" } }] }, function(rows)
    rows:iter()
    spin(work.own)
end):in_set("zz/profiler/own")

app:add_systems(Update, { Query[{ with = { "zz/work" } }] }, function(rows)
    rows:iter()
    spin(work.other)
end):in_set("zz/profiler/other")

local doomed = app:add_systems(Update, { Query[{ with = { "zz/work" } }] }, function(rows)
    rows:iter()
    spin(30000)
end):in_set("zz/profiler/doomed")

-- Ran, then stop: each average falls to about 0 as its history fills with 0.0, and lands a little
-- above or below it, differently each run. Eight, so one lands below in all but about 1 run in 256.
app:add_systems(Update, {}, function()
    spin(3000)
end):in_set("zz/profiler/ran_out_a"):run_if(function() return work.ran_out end)

app:add_systems(Update, {}, function()
    spin(5000)
end):in_set("zz/profiler/ran_out_b"):run_if(function() return work.ran_out end)

app:add_systems(Update, {}, function()
    spin(7000)
end):in_set("zz/profiler/ran_out_c"):run_if(function() return work.ran_out end)

app:add_systems(Update, {}, function()
    spin(3500)
end):in_set("zz/profiler/ran_out_d"):run_if(function() return work.ran_out end)

app:add_systems(Update, {}, function()
    spin(5500)
end):in_set("zz/profiler/ran_out_e"):run_if(function() return work.ran_out end)

app:add_systems(Update, {}, function()
    spin(7500)
end):in_set("zz/profiler/ran_out_f"):run_if(function() return work.ran_out end)

app:add_systems(Update, {}, function()
    spin(2500)
end):in_set("zz/profiler/ran_out_g"):run_if(function() return work.ran_out end)

app:add_systems(Update, {}, function()
    spin(4500)
end):in_set("zz/profiler/ran_out_h"):run_if(function() return work.ran_out end)

-- Slow frames, for the span line: 120 frames last longer.
app:add_systems(Update, {}, function()
    local from = current_time()
    while current_time() - from < 40 do spin(100) end
end):in_set("zz/profiler/slow"):run_if(function() return work.slow > 0 end)

-- Every change of the summary's Text, which a refresh writes because Lua memory moves: what it
-- said, and the store at that moment.
local summary_writes = 0
local summary_seen
app:add_systems(Update, {
    Res[DiagnosticsStore],
    Query[{
        changed = { "Text" },
        with = { "sidebar/profiler/summary" },
    }],
}, function(store, changes)
    for _, e in ipairs(changes:iter()) do
        summary_writes = summary_writes + 1
        summary_seen = {
            text = e:get("Text"),
            fps = store:get("fps"):smoothed(),
            frame = store:get("frame_time"):smoothed(),
        }
    end
end):in_set("zz/profiler/watch"):after("sidebar/profiler/refresh")

-- Each refresh, which writes the view: what the span line said, and the store at that moment. The
-- line itself may not change: frames that hold steady read the same to a tenth of a second.
local span_seen = {}
app:add_systems(Update, {
    Res[DiagnosticsStore],
    Query[{ changed = { "sidebar/profiler/view" } }],
    Query[{ with = { "sidebar/profiler/span", "Text" } }],
}, function(store, refreshed, lines)
    for _, _ in ipairs(refreshed:iter()) do
        for _, line in ipairs(lines:iter()) do
            local row = store:get("frame_time")
            span_seen[#span_seen + 1] = {
                text = line:get("Text"),
                frames = row:history_len(),
                seconds = row:duration(),
            }
        end
    end
end):in_set("zz/profiler/span_watch"):after("sidebar/profiler/refresh")

local reloads = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        local path = tostring(event.path)
        if path:find("sidebar/profiler/init.lua", 1, true) or path:find("sidebar/panel/init.lua", 1, true)
            or path:find("sidebar/init.lua", 1, true) then
            reloads = reloads + 1
        end
    end
end):in_set("zz/profiler/reload_watch")

local function buttons(world)
    return world:query({ with = { "sidebar/profiler/button" }, optional = { "sidebar/button", "sidebar/button/open", "Button", "ChildOf" } })
end

local function views(world)
    return world:query({ with = { "sidebar/profiler/view" }, optional = { "sidebar/panel", "ChildOf" } })
end

local function count(world, name)
    return #world:query({ with = { name } })
end

-- A row's parts, read through its descendants.
local function read_row(world, row)
    local inside = world:descendants(row:id())
    local name = world:query({ iter_many = inside, with = { "sidebar/profiler/name", "Text" } })[1]
    local cost = world:query({ iter_many = inside, with = { "sidebar/profiler/cost", "Text", "ui/style" } })[1]
    local lines = world:query({ iter_many = inside, with = { "sidebar/profiler/query", "Text" } })
    local queries = {}
    for _, line in ipairs(lines) do queries[#queries + 1] = line:get("Text") end
    local cost_text = cost and cost:get("Text") or ""
    local data = row:get("sidebar/profiler/row")
    return {
        id = row:id(),
        rank = data.rank,
        name = data.name,
        label = name and name:get("Text"),
        cost_text = cost_text,
        cost_role = cost and cost:get("ui/style").text,
        average = tonumber(cost_text:match("^(%-?[%d%.]+) /")),
        max = tonumber(cost_text:match("/ (%-?[%d%.]+)$")),
        queries = queries,
        background = row:get("ui/style").background,
        color = row:get("BackgroundColor"),
    }
end

local function rows(world)
    local out = {}
    for _, row in ipairs(world:query({ with = { "sidebar/profiler/row", "ui/style" }, optional = { "BackgroundColor" } })) do
        out[#out + 1] = read_row(world, row)
    end
    table.sort(out, function(a, b) return a.rank < b.rank end)
    return out
end

local function row_named(world, name)
    for _, row in ipairs(rows(world)) do
        if row.name == name then return row end
    end
end

local function children_in_rank_order(world)
    local list = world:query({ with = { "sidebar/profiler/rows", "Children" } })[1]
    local rank = 0
    for _, child in ipairs(list:get("Children")) do
        local slot = world:query({ iter_many = { child }, with = { "sidebar/profiler/row" } })[1]
        if slot == nil or slot:get("sidebar/profiler/row").rank ~= rank + 1 then return false end
        rank = rank + 1
    end
    return rank > 0
end

local function text_of(world, marker)
    local e = world:query({ with = { marker, "Text" } })[1]
    return e and e:get("Text")
end

local function total_systems(store)
    local total = 0
    for _, row in ipairs(store:iter()) do
        local path = row:path()
        if path:sub(1, 4) == "lua/" and not path:find("/queries/", 1, true) and row:average() ~= nil then
            total = total + 1
        end
    end
    return total
end

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

local function state_of(world)
    local me = world:query({ with = { "zz/player" }, optional = { "sidebar/profiler/state" } })[1]
    return me:get("sidebar/profiler/state") or {}
end

local function expanded_of(world)
    return state_of(world).expanded
end

local function title_of(world)
    return text_of(world, "sidebar/panel/title")
end

-- The panel as it was left: open, this row expanded, and one of everything in it.
local function open_once(world, rows_wanted)
    local list = rows(world)
    local ranks, unique = {}, true
    for _, row in ipairs(list) do
        unique = unique and not ranks[row.rank]
        ranks[row.rank] = true
    end
    local own = row_named(world, "zz/profiler/own")
    local b = buttons(world)[1]
    local text = string.format("buttons %d views %d rows %d summaries %d spans %d lists %d mores %d scrolls %d open %s expanded %s own queries %d",
        #buttons(world), #views(world), #list, count(world, "sidebar/profiler/summary"), count(world, "sidebar/profiler/span"),
        count(world, "sidebar/profiler/rows"), count(world, "sidebar/profiler/more"), count(world, "sidebar/panel/scroll"),
        tostring(state_of(world).open), tostring(state_of(world).expanded), own and #own.queries or -1)
    return unique and #buttons(world) == 1 and b:has("sidebar/button/open") and #views(world) == 1 and #list == rows_wanted
        and count(world, "sidebar/profiler/summary") == 1 and count(world, "sidebar/profiler/span") == 1
        and count(world, "sidebar/profiler/rows") == 1 and count(world, "sidebar/profiler/more") == 1
        and count(world, "sidebar/panel/scroll") == 1 and state_of(world).open == true
        and state_of(world).expanded == "zz/profiler/own" and own ~= nil and #own.queries == 1, text
end

local function sorted_view(list)
    local parts = {}
    for _, row in ipairs(list) do parts[#parts + 1] = row.name .. "=" .. tostring(row.average) end
    return table.concat(parts, " | ")
end

local phase, clock, frames = "arrived", 0, 0
local mark = {}

app:add_systems(Update, {
    World,
    Res[DiagnosticsStore],
    Commands,
}, function(world, store, commands)
    clock = clock + (world:delta_time() or 0)
    frames = frames + 1
    local function step(next_phase) phase, clock, frames = next_phase, 0, 0 end

    -- The net client marks its own player local frames after it arrives.
    if phase == "arrived" and clock > 0.3 then
        local me = world:query({ with = { "zz/player" }, optional = { "sidebar/profiler" } })[1]
        T("P0_nothing_before_the_player_is_ours", not me:has("sidebar/profiler") and #buttons(world) == 0)
        commands:entity(player):patch({ ["core/net/local"] = {} })
        step("button")

    elseif phase == "button" and #buttons(world) > 0 and clock > 0.2 then
        local me = world:query({ with = { "zz/player" }, optional = { "sidebar", "sidebar/profiler" } })[1]
        T("P1_player_client_adds_the_carrier_beside_the_sidebar", me:has("sidebar") and me:has("sidebar/profiler"))
        local remote = world:query({ with = { "zz/remote" }, optional = { "sidebar/profiler" } })[1]
        T("P1_a_remote_player_gets_no_carrier", not remote:has("sidebar/profiler"))
        local config = me:get("sidebar/profiler") or {}
        T("P1_with_its_defaults", config.interval == 1 and config.max_rows == 40, tostring(config.max_rows))
        local b = buttons(world)[1]
        local bar = world:query({ with = { "sidebar/bar" } })[1]
        T("P2_one_button_in_the_bar", #buttons(world) == 1 and b:get("ChildOf") == bar:id()
            and b:get("sidebar/button").title == "Profiler" and b:has("Button"))
        T("P2_closed_there_is_no_view", #views(world) == 0 and count(world, "sidebar/profiler/row") == 0)
        T("P2_its_state_starts_closed", state_of(world).open == false, tostring(state_of(world).open))
        commands:entity(player):patch({ ["sidebar/open"] = {} })
        mark.reloads = reloads
        mark.button = b:id()
        reload(MOD_FILE)
        step("never_opened_reloading")

    elseif phase == "never_opened_reloading" and reloads > mark.reloads then
        step("never_opened_reloaded")

    elseif phase == "never_opened_reloaded" and clock > 1 and #buttons(world) > 0 then
        local b = buttons(world)[1]
        T("Q1_a_panel_never_opened_stays_closed_through_a_reload", #buttons(world) == 1 and b:id() ~= mark.button
            and not b:has("sidebar/button/open") and #views(world) == 0 and state_of(world).open == false)
        click(commands, b:id())
        step("opening")

    elseif phase == "opening" and text_of(world, "sidebar/profiler/span") ~= nil and #rows(world) > 0 then
        local v = views(world)[1]
        local container = world:query({ with = { "sidebar/container" } })[1]
        T("O1_a_click_opens_a_plain_panel_in_the_container", #views(world) == 1 and v:get("ChildOf") == container:id()
            and v:has("sidebar/panel"))
        T("O2_the_content_is_in_the_panel_s_scroll_area", world:query({
            iter_many = world:descendants(v:id()),
            with = { "sidebar/profiler/row" },
        })[1] ~= nil and world:query({
            iter_many = world:descendants(world:query({ iter_many = world:descendants(v:id()), with = { "sidebar/panel/scroll" } })[1]:id()),
            with = { "sidebar/profiler/summary" },
        })[1] ~= nil)
        step("title")

    elseif phase == "title" and clock > 0.2 then
        local v = views(world)[1]
        T("O3_the_title_ends_the_loading_text", v:get("sidebar/panel").title == "Profiler"
            and count(world, "sidebar/panel/loading") == 0)
        step("data")

    -- A full history, so `average` and the span have settled.
    elseif phase == "data" and frames >= 130 and clock > 1.5 then
        local list = rows(world)
        local own = row_named(world, "zz/profiler/own")
        T("R1_a_real_labelled_system_has_a_row_with_a_number_above_0", own ~= nil and own.average ~= nil and own.average > 0,
            sorted_view(list))
        T("R1_its_max_comes_from_its_history", own ~= nil and own.max ~= nil and own.max >= own.average and own.max > 0,
            own and own.cost_text or "no row")
        T("R1_it_reads_as_its_name", own ~= nil and own.label == "zz/profiler/own", own and tostring(own.label) or "no row")
        local sorted = #list > 2
        for i = 2, #list do
            sorted = sorted and list[i - 1].average >= list[i].average
        end
        T("R2_rows_sort_costliest_first", sorted, sorted_view(list))
        local costlier, cheaper = row_named(world, "zz/profiler/own"), row_named(world, "zz/profiler/other")
        T("R2_the_costlier_of_two_ranks_above_it", costlier ~= nil and cheaper ~= nil and costlier.rank < cheaper.rank)
        local ranks_right = true
        for i, row in ipairs(list) do
            ranks_right = ranks_right and row.rank == i
        end
        T("R2_ranks_run_from_1", ranks_right)
        T("R2_the_list_lays_them_out_in_rank_order", children_in_rank_order(world))
        local summary = summary_seen.text
        T("R3_the_summary_has_fps_frame_time_and_lua_memory",
            summary:match("^FPS [%d%.]+   frame [%d%.]+ ms   Lua [%d%.]+ MB$") ~= nil, summary)
        local fps, frame = tonumber(summary:match("^FPS ([%d%.]+)")), tonumber(summary:match("frame ([%d%.]+) ms"))
        T("R3_the_fps_is_the_store_s", fps ~= nil and math.abs(fps - summary_seen.fps) < 0.1,
            tostring(fps) .. " against " .. tostring(summary_seen.fps))
        T("R3_the_frame_time_is_the_store_s", frame ~= nil and math.abs(frame - summary_seen.frame) < 0.01,
            tostring(frame) .. " against " .. tostring(summary_seen.frame))
        local total = total_systems(store)
        T("C1_more_systems_than_the_default_cap", total > 40, tostring(total))
        T("C1_the_default_cap_holds", #list == math.min(total, 40), #list .. " of " .. total)
        local more = text_of(world, "sidebar/profiler/more") or ""
        T("C1_the_rest_are_counted", more == string.format("+%d more", total - #list), more .. " with " .. total)
        local first_ids = {}
        for _, row in ipairs(list) do first_ids[row.rank] = row.id end
        mark.first_ids = first_ids
        span_seen = {}
        step("span")

    elseif phase == "span" and #span_seen >= 2 then
        local seen = span_seen[#span_seen]
        local frames_said, seconds_said = seen.text:match("^last (%d+) frames, ([%d%.]+) s")
        T("S1_the_span_line_reads_the_store_s_frames", tonumber(frames_said) == seen.frames, seen.text .. " against " .. tostring(seen.frames))
        T("S1_the_span_line_reads_the_store_s_duration", seen.seconds ~= nil and tonumber(seconds_said) ~= nil
            and math.abs(tonumber(seconds_said) - seen.seconds) < 0.06,
            seen.text .. " against " .. tostring(seen.seconds))
        mark.span_before = tonumber(seconds_said)
        work.slow = 1
        step("span_slow")

    -- Slow frames: the same 120 frames span more seconds, and the line says so.
    elseif phase == "span_slow" and clock > 7 and #span_seen > 0 then
        local seen = span_seen[#span_seen]
        local seconds_said = tonumber(seen.text:match(", ([%d%.]+) s"))
        T("S2_at_a_low_frame_rate_the_span_says_the_longer_time", seconds_said ~= nil and seconds_said > mark.span_before + 1
            and math.abs(seconds_said - seen.seconds) < 0.06,
            seen.text .. " before " .. tostring(mark.span_before) .. " store " .. tostring(seen.seconds))
        work.slow = 0
        step("interval_start")

    elseif phase == "interval_start" and clock > 0.5 then
        summary_writes = 0
        step("interval")

    elseif phase == "interval" and clock > 3.2 then
        T("I1_it_refreshes_about_once_a_second", summary_writes >= 2 and summary_writes <= 4,
            summary_writes .. " writes in " .. clock .. " s and " .. frames .. " frames")
        T("I1_and_not_each_frame", frames > summary_writes * 3,
            summary_writes .. " writes in " .. frames .. " frames")
        local stayed = true
        for _, row in ipairs(rows(world)) do
            stayed = stayed and mark.first_ids[row.rank] == row.id
        end
        T("I2_a_refresh_rewrites_the_same_row_entities", stayed)
        commands:entity(player):patch({ ["sidebar/profiler"] = { max_rows = 3, good_below = 0, warn_from = 0, bad_from = 0 } })
        step("small_cap")

    elseif phase == "small_cap" and #rows(world) == 3 and clock > 1.2 then
        local more = text_of(world, "sidebar/profiler/more") or ""
        local total = total_systems(store)
        T("C2_a_smaller_cap_takes_the_rows_above_it", count(world, "sidebar/profiler/row") == 3)
        T("C2_and_counts_them", more == string.format("+%d more", total - 3), more .. " with " .. total)
        T("L1_a_cost_past_its_bound_reads_bad", rows(world)[1].cost_role == "text_bad", tostring(rows(world)[1].cost_role))
        commands:entity(player):patch({ ["sidebar/profiler"] = { max_rows = 400, good_below = 0, warn_from = 1e9, bad_from = 1e9 } })
        step("all_rows")

    elseif phase == "all_rows" and text_of(world, "sidebar/profiler/more") == "" and clock > 0.2 then
        local total = total_systems(store)
        T("C3_a_cap_above_the_total_counts_none_more", #rows(world) == total, #rows(world) .. " of " .. total)
        T("C3_the_list_stays_in_rank_order", children_in_rank_order(world))
        T("L2_a_cost_within_its_bounds_reads_plain", rows(world)[1].cost_role == "text", tostring(rows(world)[1].cost_role))
        commands:entity(player):patch({ ["sidebar/profiler"] = { max_rows = 40, good_below = 0.5, warn_from = 2, bad_from = 8 } })
        step("expand")

    elseif phase == "expand" and #rows(world) == 40 and row_named(world, "zz/profiler/own") ~= nil then
        local own = row_named(world, "zz/profiler/own")
        T("E0_nothing_expanded_yet", #own.queries == 0 and expanded_of(world) == nil)
        -- Headless, a Pointer event does not propagate: the row is clicked itself. The windowed suite
        -- clicks its text, which a real pointer lands on.
        click(commands, own.id)
        step("expanded")

    elseif phase == "expanded" and clock > 0.1 and #(row_named(world, "zz/profiler/own") or { queries = {} }).queries > 0 then
        local own = row_named(world, "zz/profiler/own")
        T("E1_a_click_expands_at_once_not_at_the_next_refresh", clock < 0.9, tostring(clock))
        T("E2_its_query_rows_show_with_an_average", own.queries[1]:match("^zz/work  [%d%.]+$") ~= nil, tostring(own.queries[1]))
        T("E2_no_call_counts", not own.queries[1]:lower():find("call", 1, true))
        local others = 0
        for _, row in ipairs(rows(world)) do
            if row.name ~= "zz/profiler/own" then others = others + #row.queries end
        end
        T("E3_no_other_row_shows_any", others == 0, tostring(others))
        T("E4_the_row_reads_selected", own.background == "row_selected", tostring(own.background))
        mark.writes = #span_seen
        step("expanded_color")

    elseif phase == "expanded_color" and clock > 0.2 then
        local color = row_named(world, "zz/profiler/own").color
        local srgba = color and color.Srgba
        T("E4_with_the_theme_s_colour", srgba ~= nil and math.abs(srgba.red - 0.25) < 1e-3 and math.abs(srgba.blue - 0.5) < 1e-3)
        step("expanded_survives")

    elseif phase == "expanded_survives" and #span_seen >= mark.writes + 3 then
        local own = row_named(world, "zz/profiler/own")
        T("E5_it_survives_refreshes", expanded_of(world) == "zz/profiler/own" and #own.queries == 1, tostring(expanded_of(world)))
        -- The expanded system falls in the order: the slots move, and it stays with its name.
        mark.rank_before = own.rank
        work.own, work.other = 0, 60000
        step("expanded_moves")

    elseif phase == "expanded_moves" and (row_named(world, "zz/profiler/own") or { rank = mark.rank_before }).rank ~= mark.rank_before and clock > 1 then
        local own = row_named(world, "zz/profiler/own")
        local was = rows(world)[mark.rank_before]
        T("E6_it_follows_its_system_to_another_rank", #own.queries == 1 and expanded_of(world) == "zz/profiler/own"
            and own.background == "row_selected", tostring(own.rank))
        T("E6_the_old_slot_lets_go", #was.queries == 0 and was.background ~= "row_selected", was.name)
        work.own, work.other = 40000, 20000
        click(commands, own.id)
        step("collapsed")

    elseif phase == "collapsed" and expanded_of(world) == nil and clock > 0.2 then
        T("E7_a_second_click_collapses", count(world, "sidebar/profiler/query") == 0, tostring(count(world, "sidebar/profiler/query")))
        step("doomed_ready")

    elseif phase == "doomed_ready" and row_named(world, "zz/profiler/doomed") ~= nil then
        click(commands, row_named(world, "zz/profiler/doomed").id)
        step("doomed_open")

    elseif phase == "doomed_open" and #(row_named(world, "zz/profiler/doomed") or { queries = {} }).queries > 0 then
        unregister_system_by_id(doomed:id())
        step("doomed_gone")

    elseif phase == "doomed_gone" and store:get("lua/zz/profiler/doomed") == nil and row_named(world, "zz/profiler/doomed") == nil and clock > 1.2 then
        T("D1_a_system_removed_drops_its_row", true)
        T("D2_and_what_it_had_expanded_shows_nothing", count(world, "sidebar/profiler/query") == 0,
            tostring(count(world, "sidebar/profiler/query")))
        work.ran_out = false
        step("rounding")

    -- The systems that ran out have a history of 0.0 by now.
    elseif phase == "rounding" and frames >= 130 and clock > 2 then
        commands:entity(player):patch({ ["sidebar/profiler"] = { max_rows = 400 } })
        step("rounding_read")

    elseif phase == "rounding_read" and clock > 1.5 then
        local odd = {}
        for _, row in ipairs(rows(world)) do
            if row.cost_text:find("-0.000", 1, true) or row.cost_text:find("e-", 1, true) then odd[#odd + 1] = row.name .. " " .. row.cost_text end
        end
        T("N1_a_row_that_stopped_reads_as_0", row_named(world, "zz/profiler/ran_out_a") ~= nil
            and row_named(world, "zz/profiler/ran_out_a").average == 0, tostring((row_named(world, "zz/profiler/ran_out_a") or {}).cost_text))
        T("N2_nothing_prints_unrounded", #odd == 0, table.concat(odd, " | "))
        T("L3_no_cost_reads_good", row_named(world, "zz/profiler/ran_out_a").cost_role == "text_good", tostring(row_named(world, "zz/profiler/ran_out_a").cost_role))
        commands:entity(player):patch({ ["sidebar/profiler"] = { max_rows = 40 } })
        step("close")

    elseif phase == "close" and #rows(world) == 40 then
        click(commands, buttons(world)[1]:id())
        step("closed")

    elseif phase == "closed" and #views(world) == 0 and clock > 0.2 then
        T("K1_closing_takes_the_view_and_all_in_it", count(world, "sidebar/profiler/row") == 0
            and count(world, "sidebar/profiler/summary") == 0 and count(world, "sidebar/panel/scroll") == 0)
        T("K1_the_button_stays", #buttons(world) == 1)
        summary_writes = 0
        step("closed_idle")

    -- A whole history closed: the refresh has cost nothing in any of those frames.
    elseif phase == "closed_idle" and frames >= 130 and clock > 2 then
        local refresh = store:get("lua/sidebar/profiler/refresh")
        local most = 0
        for _, value in ipairs(refresh and refresh:values() or { 1 }) do most = math.max(most, value) end
        T("K2_closed_it_does_nothing", refresh ~= nil and most == 0 and summary_writes == 0, tostring(most))
        click(commands, buttons(world)[1]:id())
        step("reopen")

    elseif phase == "reopen" and #rows(world) == 40 then
        T("K3_opened_again_it_is_a_new_view", #views(world) == 1 and state_of(world).open == true)
        click(commands, row_named(world, "zz/profiler/own").id)
        step("reload_ready")

    elseif phase == "reload_ready" and #(row_named(world, "zz/profiler/own") or { queries = {} }).queries > 0 then
        mark.reloads = reloads
        mark.button = buttons(world)[1]:id()
        reload(MOD_FILE)
        step("reloading")

    elseif phase == "reloading" and reloads > mark.reloads then
        step("reloaded")

    elseif phase == "reloaded" and clock > 2 then
        T("H1_a_real_reload_leaves_one_button", #buttons(world) == 1, tostring(#buttons(world)))
        T("H1_a_new_one", buttons(world)[1] ~= nil and buttons(world)[1]:id() ~= mark.button)
        local kept, why = open_once(world, 40)
        T("H2_its_own_reload_leaves_it_open_with_its_row_expanded_and_one_of_everything", kept, why)
        T("H2_it_doubles_nothing_of_the_sidebar", count(world, "sidebar/container") == 1 and count(world, "sidebar/bar") == 1)
        local b = world:query({ with = { "sidebar/profiler/button", "ui/style" } })[1]
        local style = b and b:get("ui/style") or {}
        T("H2_its_icon_is_drawn_open", style.background == "icon_active", tostring(style.background))
        local own = row_named(world, "zz/profiler/own")
        if own ~= nil then click(commands, own.id) end
        step("after_reload_click")

    elseif phase == "after_reload_click" and expanded_of(world) == nil and clock > 0.2 then
        T("H3_after_it_a_click_on_a_row_works", count(world, "sidebar/profiler/query") == 0)
        click(commands, row_named(world, "zz/profiler/own").id)
        step("after_reload_click_back")

    elseif phase == "after_reload_click_back" and #(row_named(world, "zz/profiler/own") or { queries = {} }).queries == 1 then
        T("H4_and_expands_again", expanded_of(world) == "zz/profiler/own")
        mark.reloads = reloads
        reload(PANEL_FILE)
        step("panel_reloading")

    elseif phase == "panel_reloading" and reloads > mark.reloads then
        step("panel_reloaded")

    elseif phase == "panel_reloaded" and clock > 2.5 then
        local kept, why = open_once(world, 40)
        T("H5_a_reload_of_the_panel_brings_the_content_back_once_with_its_row_expanded", kept, why)
        mark.reloads = reloads
        mark.button = buttons(world)[1]:id()
        mark.container = world:query({ with = { "sidebar/container" } })[1]:id()
        reload(SIDEBAR_FILE)
        step("sidebar_reloading")

    elseif phase == "sidebar_reloading" and reloads > mark.reloads then
        step("sidebar_reloaded")

    elseif phase == "sidebar_reloaded" and clock > 2.5 then
        T("H6_a_reload_of_the_sidebar_gives_its_new_bar_one_new_button", #buttons(world) == 1 and buttons(world)[1]:id() ~= mark.button,
            tostring(#buttons(world)))
        local kept, why = open_once(world, 40)
        T("H6_and_leaves_the_panel_open_with_its_row_expanded_and_one_of_everything", kept, why)
        local container = world:query({ with = { "sidebar/container" } })[1]
        local v = views(world)[1]
        T("H6_in_the_new_container", count(world, "sidebar/container") == 1 and container:id() ~= mark.container
            and v ~= nil and v:get("ChildOf") == container:id())
        -- A change to the UI shows in the panel that stays open.
        mark.reloads = reloads
        reload(MOD_FILE, '["sidebar/panel"] = { title = "Profiler" }', '["sidebar/panel"] = { title = "Profiler zz" }')
        step("ui_changing")

    elseif phase == "ui_changing" and reloads > mark.reloads then
        step("ui_changed")

    elseif phase == "ui_changed" and clock > 2 then
        T("H7_a_change_to_the_mod_s_ui_shows_in_the_open_panel", title_of(world) == "Profiler zz", tostring(title_of(world)))
        local kept, why = open_once(world, 40)
        T("H7_still_open_with_its_row_expanded", kept, why)
        mark.reloads = reloads
        reload(MOD_FILE)
        step("ui_restoring")

    elseif phase == "ui_restoring" and reloads > mark.reloads then
        step("ui_restored")

    elseif phase == "ui_restored" and clock > 2 then
        T("H7_and_the_file_put_back_shows_too", title_of(world) == "Profiler", tostring(title_of(world)))
        -- Another panel opening or closing is none of this one's business.
        local bar = world:query({ with = { "sidebar/bar" } })[1]
        mark.other = commands:spawn({ ["sidebar/button"] = { title = "Other", order = 2 }, ChildOf = bar:id() }):id()
        step("other_ready")

    elseif phase == "other_ready" and clock > 0.3 then
        click(commands, mark.other)
        step("other_open")

    elseif phase == "other_open" and clock > 0.3 then
        T("A1_another_panel_opening_leaves_this_one_open", state_of(world).open == true and #views(world) == 1
            and world:query({ iter_many = { mark.other }, with = { "sidebar/button/open" } })[1] ~= nil)
        click(commands, mark.other)
        step("other_closed")

    elseif phase == "other_closed" and clock > 0.3 then
        T("A2_and_closing_leaves_it_open", state_of(world).open == true and #views(world) == 1
            and world:query({ iter_many = { mark.other }, with = { "sidebar/button/open" } })[1] == nil)
        commands:entity(mark.other):despawn()
        mark.second = commands:spawn({ ["zz/second"] = {}, ["sidebar/profiler"] = {}, ["core/net/local"] = {}, ["core/net/sync"] = false }):id()
        step("second_carrier")

    elseif phase == "second_carrier" and clock > 0.5 then
        T("M1_a_second_local_carrier_adds_no_button", #buttons(world) == 1 and #views(world) == 1)
        commands:entity(mark.second):remove("sidebar/profiler")
        step("second_gone")

    elseif phase == "second_gone" and clock > 0.5 then
        T("M2_and_leaving_takes_nothing", #buttons(world) == 1 and #views(world) == 1 and #rows(world) > 0)
        commands:entity(mark.second):despawn()
        click(commands, buttons(world)[1]:id())
        step("user_closed")

    -- Someone closing it is what a later reload must keep.
    elseif phase == "user_closed" and #views(world) == 0 and clock > 0.2 then
        T("Q2_closing_it_saves_closed", state_of(world).open == false, tostring(state_of(world).open))
        mark.reloads = reloads
        mark.button = buttons(world)[1]:id()
        reload(MOD_FILE)
        step("user_closed_reloading")

    elseif phase == "user_closed_reloading" and reloads > mark.reloads then
        step("user_closed_reloaded")

    elseif phase == "user_closed_reloaded" and clock > 1.5 and #buttons(world) > 0 then
        local b = buttons(world)[1]
        T("Q2_and_after_a_reload_it_stays_closed", #buttons(world) == 1 and b:id() ~= mark.button
            and not b:has("sidebar/button/open") and #views(world) == 0 and state_of(world).open == false)
        T("Q2_keeping_its_row_for_next_time", expanded_of(world) == "zz/profiler/own", tostring(expanded_of(world)))
        click(commands, b:id())
        step("user_reopen")

    elseif phase == "user_reopen" and #(row_named(world, "zz/profiler/own") or { queries = {} }).queries == 1 then
        T("Q3_opened_again_its_row_is_expanded", state_of(world).open == true)
        commands:entity(player):remove("sidebar/open")
        step("sidebar_closed")

    elseif phase == "sidebar_closed" and #views(world) == 0 and clock > 0.3 then
        T("Q4_the_sidebar_closing_closes_it_and_saves_closed", #views(world) == 0 and state_of(world).open == false,
            string.format("views %d open %s sidebar/open %s button open %s", #views(world), tostring(state_of(world).open),
                tostring(#world:query({ with = { "zz/player", "sidebar/open" } })), tostring(buttons(world)[1]:has("sidebar/button/open"))))
        commands:entity(player):patch({ ["sidebar/open"] = {} })
        step("sidebar_opened")

    elseif phase == "sidebar_opened" and clock > 0.3 then
        T("Q4_and_opening_the_sidebar_leaves_it_closed", #views(world) == 0)
        click(commands, buttons(world)[1]:id())
        step("before_sidebar_gone")

    elseif phase == "before_sidebar_gone" and #rows(world) > 0 then
        commands:entity(player):remove("sidebar")
        step("sidebar_gone")

    elseif phase == "sidebar_gone" and clock > 0.5 then
        T("B1_the_sidebar_gone_takes_button_and_view", #buttons(world) == 0 and #views(world) == 0 and count(world, "sidebar/profiler/row") == 0)
        commands:entity(player):patch({ sidebar = {} })
        step("sidebar_back")

    elseif phase == "sidebar_back" and clock > 1 and #buttons(world) > 0 then
        T("B2_a_new_bar_gets_one_new_button", #buttons(world) == 1)
        T("B3_a_sidebar_taken_off_and_added_back_is_closed_and_so_is_the_panel", #views(world) == 0 and state_of(world).open == false
            and not buttons(world)[1]:has("sidebar/button/open"), tostring(state_of(world).open))
        click(commands, buttons(world)[1]:id())
        step("removal_open")

    elseif phase == "removal_open" and #rows(world) > 0 then
        commands:entity(player):remove("sidebar/profiler")
        step("removed")

    elseif phase == "removed" and clock > 1 and frames >= 130 then
        local names = {
            "sidebar/profiler/button", "sidebar/profiler/view", "sidebar/profiler/row", "sidebar/profiler/summary",
            "sidebar/profiler/span", "sidebar/profiler/rows", "sidebar/profiler/more", "sidebar/profiler/line",
            "sidebar/profiler/name", "sidebar/profiler/cost", "sidebar/profiler/query", "sidebar/panel",
            "sidebar/profiler/state",
        }
        local left = {}
        for _, name in ipairs(names) do
            if count(world, name) > 0 then left[#left + 1] = name end
        end
        T("U1_removing_the_carrier_leaves_no_entity_or_component", #left == 0, table.concat(left, " "))
        -- Other panels' buttons stay: `player/client` adds more panels than this one.
        local titled = 0
        for _, b in ipairs(world:query({ with = { "sidebar/button" } })) do
            if b:get("sidebar/button").title == "Profiler" then titled = titled + 1 end
        end
        T("U2_the_sidebar_stays", count(world, "sidebar/bar") == 1 and titled == 0,
            string.format("bars %d profiler buttons %d", count(world, "sidebar/bar"), titled))
        local script_left = false
        for _, row in ipairs(world:query({ with = { "core/script" } })) do
            local entry = row:get("core/script").entry
            if type(entry) == "string" and entry:find("sidebar/profiler", 1, true) then script_left = true end
        end
        T("U3_its_script_stopped", not script_left)
        local rows_left = {}
        for _, row in ipairs(store:iter()) do
            if row:path():sub(1, 20) == "lua/sidebar/profiler" then rows_left[#rows_left + 1] = row:path() end
        end
        T("U4_its_store_rows_went", #rows_left == 0, table.concat(rows_left, " "))
        local me = world:query({ with = { "zz/player" }, optional = { "sidebar/profiler" } })[1]
        commands:entity(me:id()):patch({ ["sidebar/profiler"] = {} })
        step("carrier_back")

    elseif phase == "carrier_back" and #buttons(world) > 0 and clock > 0.3 then
        T("U5_added_again_it_gets_its_button_closed", #buttons(world) == 1 and #views(world) == 0 and state_of(world).open == false)
        commands:entity(player):remove("player")
        step("player_gone")

    elseif phase == "player_gone" and clock > 0.5 then
        local me = world:query({ with = { "zz/player" }, optional = { "sidebar", "sidebar/profiler" } })[1]
        T("P3_removing_player_takes_off_the_carrier", me ~= nil and not me:has("sidebar/profiler") and not me:has("sidebar"))
        phase = "done"
        finish()
    end

    if phase ~= "done" and clock > 25 then
        T("Z_reached_" .. phase, false, "stuck in phase '" .. phase .. "'")
        phase = "done"
        finish()
    end
end):in_set("zz/profiler/suite"):after("sidebar/profiler/refresh")
