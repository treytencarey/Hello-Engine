-- A sidebar panel showing what this VM's frames cost, from its `DiagnosticsStore`: FPS, frame
-- time, Lua memory, and a row per Lua system, the costliest first. A click on a row shows
-- that system's query rows. It reads the store only at a refresh, and only while it is open.
--
-- sidebar/profiler = {
--     interval = <seconds between refreshes>,
--     max_rows = <system rows shown>,
--     width = <panel pixels>,
--     good_below = <ms: a cost below this reads good>,
--     warn_from = <ms: from this it reads as a warning>,
--     bad_from = <ms: from this it reads as bad>,
-- }
--
-- sidebar/profiler/state = {
--     open = <whether the panel is open>,
--     expanded = <system name whose query rows show>,
-- }
--
-- sidebar/profiler/button = {}
--
-- sidebar/profiler/view = {
--     next = <seconds: when the next refresh is due>,
-- }
--
-- sidebar/profiler/row = {
--     rank = <position among the rows, 1 the costliest>,
--     name = <system name>,
-- }
--
-- sidebar/profiler/summary = {}
-- sidebar/profiler/span = {}
-- sidebar/profiler/rows = {}
-- sidebar/profiler/more = {}
-- sidebar/profiler/line = {}
-- sidebar/profiler/name = {}
-- sidebar/profiler/cost = {}
-- sidebar/profiler/query = {}

local DiagnosticsStore = require("bevy::diagnostic::DiagnosticsStore")
local Time = require("bevy::time::Time")
local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")

-- A row's average can read about +-1e-18, which plain formatting prints as -0.000.
local function ms(value)
    return string.format("%.3f", math.floor(value * 1000 + 0.5) / 1000)
end

-- Writing is a change edge, and most text is the same from one refresh to the next.
local function write_text(line, text)
    local current = line:get("Text")
    if current ~= text then
        line:patch({ Text = { text = text } })
    end
end

local function by_average(a, b)
    if a.average ~= b.average then return a.average > b.average end
    return a.path < b.path
end

-- What the panel keeps through a reload lives on the carrier, which a reload leaves alone, while
-- everything this mod spawned goes. The reload re-fires this edge, and a state already there stays.
-- `sidebar` taken off the carrier takes this state with it, as a part of its name, and leaves the
-- carrier: a closed panel starts again.
app:add_systems(First, {
    Query[{
        added = { "sidebar/profiler" },
        optional = { "sidebar/profiler/state" },
    }],
    Query[{
        removed = { "sidebar/profiler/state" },
        with = { "sidebar/profiler" },
    }],
    Commands,
}, function(carriers, stripped, commands)
    for _, e in ipairs(carriers:iter()) do
        if not e:has("sidebar/profiler/state") then
            commands:entity(e:id()):insert({ ["sidebar/profiler/state"] = { open = false } })
        end
    end
    for _, e in ipairs(stripped:iter()) do
        commands:entity(e:id()):try_insert({ ["sidebar/profiler/state"] = { open = false } })
    end
end):in_set("sidebar/profiler/init")

-- The button goes in the bar for a local player with the panel: on a new bar (the sidebar built
-- or reloaded), and on the panel itself (added, or this mod reloaded).
app:add_systems(Update, {
    Query[{ with = { "sidebar/profiler", "core/net/local" } }],
    Query[{ with = { "sidebar/bar" } }],
    Query[{ with = { "sidebar/profiler/button" } }],
    Commands,
}, function(carriers, bars, buttons, commands)
    local bar = bars:iter()[1]
    if bar ~= nil and not carriers:is_empty() and buttons:is_empty() then
        commands:spawn({
            ["sidebar/button"] = { title = "Profiler", order = 1 },
            ["sidebar/profiler/button"] = {},
            ChildOf = bar:id(),
        })
    end
end):in_set("sidebar/profiler/add_button"):run_if({
    Query[{ added = { "sidebar/bar" } }],
    Query[{
        ["or"] = {
            added = { "sidebar/profiler", "core/net/local" },
        },
        with = { "sidebar/profiler", "core/net/local" },
    }],
}, function(new_bars, new_carriers)
    return not new_bars:is_empty() or not new_carriers:is_empty()
end)

-- A new button that was open before a reload opens again, by the path a click takes. It waits for the
-- sidebar to make it an icon: an icon drawn active reacts to `sidebar/button/open` on a node.
app:add_systems(Update, {
    Query[{
        added = { "Node" },
        with = { "sidebar/profiler/button" },
    }],
    Query[{ with = { "sidebar/profiler", "sidebar/profiler/state" } }],
    Query[{ with = { "sidebar/button/open" } }],
    Commands,
}, function(icons, carriers, open_buttons, commands)
    for _, icon in ipairs(icons:iter()) do
        local carrier = carriers:iter()[1]
        local state = carrier and carrier:get("sidebar/profiler/state")
        if state ~= nil and state.open then
            local order = 0
            for _, o in ipairs(open_buttons:iter()) do
                local opened = o:get("sidebar/button/open")
                order = math.max(order, opened.order)
            end
            commands:entity(icon:id()):insert({ ["sidebar/button/open"] = { order = order + 1 } })
        end
    end
end):in_set("sidebar/profiler/restore")

app:add_systems(Update, {
    Query[{
        added = { "sidebar/button/open" },
        with = { "sidebar/profiler/button" },
    }],
    Query[{ with = { "sidebar/container" } }],
    Query[{ with = { "sidebar/profiler", Mut["sidebar/profiler/state"] } }],
    Commands,
}, function(opened, containers, carriers, commands)
    for _, _ in ipairs(opened:iter()) do
        local container = containers:iter()[1]
        local carrier = carriers:iter_mut()[1]
        if container ~= nil and carrier ~= nil then
            local config = carrier:get("sidebar/profiler")
            commands:spawn({
                ["sidebar/panel"] = { width = config.width },
                ["sidebar/profiler/view"] = {},
                ChildOf = container:id(),
            })
            local state = carrier:get("sidebar/profiler/state")
            if not state.open then
                carrier:patch({ ["sidebar/profiler/state"] = { open = true } })
            end
        end
    end
end):in_set("sidebar/profiler/open")

-- Only a button still here closing is someone closing the panel. A reload takes the button too, and
-- its edge comes the same: that closes nothing, because the panel is to come back.
app:add_systems(Update, {
    Query[{
        removed = { "sidebar/button/open" },
        with = { "sidebar/profiler/button" },
    }],
    Query[{ with = { "sidebar/profiler/button" } }],
    Query[{ with = { "sidebar/profiler/view" } }],
    Query[{ with = { Mut["sidebar/profiler/state"] } }],
    Commands,
}, function(closed, buttons, views, states, commands)
    local ids = {}
    for _, b in ipairs(closed:iter()) do
        ids[#ids + 1] = b:id()
    end
    for _, _ in ipairs(buttons:iter_many(ids)) do
        for _, view in ipairs(views:iter()) do
            commands:entity(view:id()):try_despawn()
        end
        for _, row in ipairs(states:iter_mut()) do
            row:patch({ ["sidebar/profiler/state"] = { open = false } })
        end
    end
end):in_set("sidebar/profiler/close")

-- Rows are read afresh and kept by nothing past this run: a query row leaves the store after
-- 120 idle frames, and a row held past that raises. Reading them takes a couple of ms, so this
-- is timed work, and `values()` is called only for the rows shown. Slots are kept and rewritten,
-- so a refresh writes only what changed. Content the panel's reload took is spawned again here.
-- After `close`: a view it took gets no more writes.
app:add_systems(Update, {
    Res[Time],
    Res[DiagnosticsStore],
    Query[{ with = { Mut["sidebar/profiler/view"], Mut["sidebar/panel"] } }],
    Query[{ with = { "sidebar/profiler", "sidebar/profiler/state" } }],
    Query[{ with = { "sidebar/panel/scroll" } }],
    Query[{ with = { "sidebar/profiler/rows" } }],
    Query[{ with = { "sidebar/profiler/summary", Mut["Text"] } }],
    Query[{ with = { "sidebar/profiler/span", Mut["Text"] } }],
    Query[{ with = { "sidebar/profiler/more", Mut["Text"] } }],
    Query[{ with = { Mut["sidebar/profiler/row"], Mut["ui/style"] } }],
    Query[{ with = { "sidebar/profiler/name", Mut["Text"] } }],
    Query[{ with = { "sidebar/profiler/cost", Mut["Text"], Mut["ui/style"] } }],
    Query[{ with = { "sidebar/profiler/query", Mut["Text"] } }],
    Commands,
}, function(time, store, views, carriers, scrolls, lists, summaries, spans, mores, slots, names, costs, query_lines, commands)
    local view = views:iter_mut()[1]
    local carrier = carriers:iter()[1]
    local config = carrier:get("sidebar/profiler")
    local state = carrier:get("sidebar/profiler/state")
    local expanded = state.expanded

    local systems, expanded_queries = {}, {}
    local query_prefix = expanded ~= nil and "lua/" .. expanded .. "/queries/" or nil
    for _, row in ipairs(store:iter()) do
        local path, average = row:path(), row:average()
        if average ~= nil and path:sub(1, 4) == "lua/" then
            if not path:find("/queries/", 1, true) then
                local name = path:sub(5)
                systems[#systems + 1] = { path = path, name = name, average = average, row = row }
            elseif query_prefix ~= nil and path:sub(1, #query_prefix) == query_prefix then
                expanded_queries[#expanded_queries + 1] = { path = path, name = path:sub(#query_prefix + 1), average = average }
            end
        end
    end
    table.sort(systems, by_average)
    table.sort(expanded_queries, by_average)

    local fps = store:get("fps")
    local frame_time = store:get("frame_time")
    local fps_now = fps and fps:smoothed()
    local frame_now = frame_time and frame_time:smoothed()
    local summary_text = string.format("FPS %s   frame %s ms   Lua %.1f MB",
        fps_now and string.format("%.1f", fps_now) or "-",
        frame_now and string.format("%.2f", frame_now) or "-",
        collectgarbage("count") / 1024)
    -- History is frames, not seconds: 2 s at 60 FPS, 60 s at 2 FPS.
    local span_text = string.format("last %d frames, %.1f s: average / max, ms per frame",
        frame_time and frame_time:history_len() or 0,
        frame_time and frame_time:duration() or 0)
    local shown = math.min(#systems, config.max_rows)
    local more_text = #systems > shown and string.format("+%d more", #systems - shown) or ""

    local parts = scrolls:iter_descendants(view:id())
    local list = lists:iter_many(parts)[1]
    local list_id
    if list == nil then
        local scroll = scrolls:iter_many(parts)[1]
        commands:spawn({
            ["sidebar/profiler/summary"] = {},
            Text = { text = summary_text },
            TextFont = { font_size = 13 },
            ["ui/style"] = { text = "text" },
            ChildOf = scroll:id(),
        })
        commands:spawn({
            ["sidebar/profiler/span"] = {},
            Text = { text = span_text },
            TextFont = { font_size = 11 },
            Node = { margin = { bottom = { Px = 6 } } },
            ["ui/style"] = { text = "text_dim" },
            ChildOf = scroll:id(),
        })
        list_id = commands:spawn({
            ["sidebar/profiler/rows"] = {},
            Node = {
                flex_direction = "Column",
                align_items = "Stretch",
                flex_shrink = 0,
            },
            ChildOf = scroll:id(),
        }):id()
        commands:spawn({
            ["sidebar/profiler/more"] = {},
            Text = { text = more_text },
            TextFont = { font_size = 11 },
            ["ui/style"] = { text = "text_dim" },
            ChildOf = scroll:id(),
        })
    else
        list_id = list:id()
        for _, line in ipairs(summaries:iter_many_mut(parts)) do
            write_text(line, summary_text)
        end
        for _, line in ipairs(spans:iter_many_mut(parts)) do
            write_text(line, span_text)
        end
        for _, line in ipairs(mores:iter_many_mut(parts)) do
            write_text(line, more_text)
        end
    end

    local by_rank = {}
    for _, slot in ipairs(slots:iter_many_mut(parts)) do
        local data = slot:get("sidebar/profiler/row")
        if data.rank > shown then
            commands:entity(slot:id()):despawn()
        else
            by_rank[data.rank] = slot
        end
    end

    for rank = 1, shown do
        local system = systems[rank]
        local is_expanded = system.name == expanded
        local max = 0
        for _, value in ipairs(system.row:values()) do
            max = math.max(max, value)
        end
        local cost_text = ms(system.average) .. " / " .. ms(max)
        local role = "text_bad"
        if system.average < config.good_below then
            role = "text_good"
        elseif system.average < config.warn_from then
            role = "text"
        elseif system.average < config.bad_from then
            role = "text_warn"
        end
        local background = rank % 2 == 1 and "row_bg" or "row_alt"
        local hover = "row_hover"
        if is_expanded then
            background, hover = "row_selected", "row_selected"
        end

        local slot = by_rank[rank]
        local slot_id
        local lines = {}
        if slot == nil then
            local new_slot = commands:spawn({
                ["sidebar/profiler/row"] = { rank = rank, name = system.name },
                Button = {},
                Node = {
                    flex_direction = "Column",
                    align_items = "Stretch",
                    flex_shrink = 0,
                    padding = { left = { Px = 4 }, right = { Px = 4 }, top = { Px = 2 }, bottom = { Px = 2 } },
                },
                ["ui/style"] = { background = background, hover = hover },
                ChildOf = list_id,
            })
            slot_id = new_slot:id()
            new_slot:observe(On[Pointer[Click]], {
                Query[{ with = { "sidebar/profiler/row" } }],
                Query[{ with = { Mut["sidebar/profiler/state"] } }],
                Query[{ with = { Mut["sidebar/profiler/view"] } }],
            }, function(event, clicked, states, open_views)
                local row = clicked:get(event.entity)
                if row ~= nil then
                    local data = row:get("sidebar/profiler/row")
                    for _, carrier in ipairs(states:iter_mut()) do
                        local current = carrier:get("sidebar/profiler/state")
                        carrier:patch({
                            ["sidebar/profiler/state"] = {
                                expanded = current.expanded == data.name and null or data.name,
                            },
                        })
                    end
                    for _, open in ipairs(open_views:iter_mut()) do
                        open:patch({ ["sidebar/profiler/view"] = { next = 0 } })
                    end
                end
            end)
            local line = commands:spawn({
                ["sidebar/profiler/line"] = {},
                Node = {
                    flex_direction = "Row",
                    justify_content = "SpaceBetween",
                    column_gap = { Px = 8 },
                },
                ChildOf = slot_id,
            }):id()
            commands:spawn({
                ["sidebar/profiler/name"] = {},
                Text = { text = system.name },
                TextFont = { font_size = 11 },
                ["ui/style"] = { text = "text" },
                ChildOf = line,
            })
            commands:spawn({
                ["sidebar/profiler/cost"] = {},
                Text = { text = cost_text },
                TextFont = { font_size = 11 },
                Node = { flex_shrink = 0 },
                ["ui/style"] = { text = role },
                ChildOf = line,
            })
        else
            slot_id = slot:id()
            local data = slot:get("sidebar/profiler/row")
            if data.name ~= system.name then
                slot:patch({ ["sidebar/profiler/row"] = { name = system.name } })
            end
            local style = slot:get("ui/style")
            if style.background ~= background or style.hover ~= hover then
                slot:patch({ ["ui/style"] = { background = background, hover = hover } })
            end
            local inside = names:iter_descendants(slot_id)
            for _, part in ipairs(names:iter_many_mut(inside)) do
                write_text(part, system.name)
            end
            for _, part in ipairs(costs:iter_many_mut(inside)) do
                write_text(part, cost_text)
                local cost_style = part:get("ui/style")
                if cost_style.text ~= role then
                    part:patch({ ["ui/style"] = { text = role } })
                end
            end
            lines = query_lines:iter_many_mut(inside)
        end

        local wanted = is_expanded and #expanded_queries or 0
        for i, line in ipairs(lines) do
            if i > wanted then
                commands:entity(line:id()):despawn()
            else
                write_text(line, expanded_queries[i].name .. "  " .. ms(expanded_queries[i].average))
            end
        end
        for i = #lines + 1, wanted do
            commands:spawn({
                ["sidebar/profiler/query"] = {},
                Text = { text = expanded_queries[i].name .. "  " .. ms(expanded_queries[i].average) },
                TextFont = { font_size = 10 },
                Node = { margin = { left = { Px = 8 } } },
                ["ui/style"] = { text = "accent" },
                ChildOf = slot_id,
            })
        end
    end

    view:patch({ ["sidebar/profiler/view"] = { next = time:elapsed_secs() + config.interval } })
    local panel = view:get("sidebar/panel")
    if panel.title == nil then
        view:patch({ ["sidebar/panel"] = { title = "Profiler" } })
    end
end):in_set("sidebar/profiler/refresh"):after("sidebar/profiler/close"):run_if({
    Res[Time],
    Query[{ with = { "sidebar/profiler/view" } }],
    Query[{ with = { "sidebar/profiler", "sidebar/profiler/state" } }],
    Query[{ with = { "sidebar/panel/scroll" } }],
}, function(time, views, carriers, scrolls)
    local view = views:iter()[1]
    if view == nil or carriers:is_empty() then
        return false
    end
    local timing = view:get("sidebar/profiler/view")
    return time:elapsed_secs() >= timing.next
        and #scrolls:iter_many(scrolls:iter_descendants(view:id())) > 0
end)

return {
    defaults = {
        ["sidebar/profiler"] = {
            interval = 1,
            max_rows = 40,
            width = 320,
            good_below = 0.5,
            warn_from = 2,
            bad_from = 8,
        },
        ["sidebar/profiler/view"] = {
            next = 0,
        },
    },
}
