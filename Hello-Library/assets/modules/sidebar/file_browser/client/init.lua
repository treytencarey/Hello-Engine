-- The client half of the file browser: a sidebar panel showing the files of the world's server, as
-- a tree with folders first, opened and closed by a click, a page at a time. It holds only what the
-- server answered, and changes nothing. While the server cannot read a folder, the folder says so.
--
-- sidebar/file_browser/state = {
--     open = <whether the panel is open>,
--     expanded = { <folder path> = true },
-- }
--
-- sidebar/file_browser/button = {}
--
-- sidebar/file_browser/view = {
--     folders = {
--         <folder path, "" for the top> = {
--             files = { { name, path, is_directory, size } },
--             has_more = <whether the server holds more>,
--             next = <offset of a page asked for by a click>,
--             unavailable = <present while the server cannot read it>,
--         },
--     },
-- }
--
-- sidebar/file_browser/row = {
--     index = <position among the rows>,
--     kind = <"folder", "file", "more" or "note">,
--     path = <the entry's path, or the folder a "more" or "note" row belongs to>,
--     depth = <folders above it>,
-- }
--
-- sidebar/file_browser/rows = {}
-- sidebar/file_browser/refresh = {}
-- sidebar/file_browser/mark = {}
-- sidebar/file_browser/name = {}
-- sidebar/file_browser/size = {}

local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")

-- Writing is a change edge, and most text stays as it was when the rows move.
local function write_text(line, text)
    if line:get("Text") ~= text then
        line:patch({ Text = { text = text } })
    end
end

-- What the panel keeps through a reload lives on the carrier, which a reload leaves alone, while
-- everything this mod spawned goes. `sidebar` taken off the carrier takes this state with it, as a
-- part of its name, and leaves the carrier: a closed panel starts again.
app:add_systems(First, {
    Query[{
        added = { "sidebar/file_browser" },
        optional = { "sidebar/file_browser/state" },
    }],
    Query[{
        removed = { "sidebar/file_browser/state" },
        with = { "sidebar/file_browser" },
    }],
    Commands,
}, function(carriers, stripped, commands)
    for _, e in ipairs(carriers:iter()) do
        if not e:has("sidebar/file_browser/state") then
            commands:entity(e:id()):insert({ ["sidebar/file_browser/state"] = { open = false, expanded = {} } })
        end
    end
    for _, e in ipairs(stripped:iter()) do
        commands:entity(e:id()):try_insert({ ["sidebar/file_browser/state"] = { open = false, expanded = {} } })
    end
end):in_set("sidebar/file_browser/init")

-- The button goes in the bar for a local player with the panel: on a new bar (the sidebar built
-- or reloaded), and on the panel itself (added, or this mod reloaded).
app:add_systems(Update, {
    Query[{ with = { "sidebar/file_browser", "core/net/local" } }],
    Query[{ with = { "sidebar/bar" } }],
    Query[{ with = { "sidebar/file_browser/button" } }],
    Commands,
}, function(carriers, bars, buttons, commands)
    local bar = bars:iter()[1]
    if bar ~= nil and not carriers:is_empty() and buttons:is_empty() then
        commands:spawn({
            ["sidebar/button"] = { title = "Files", order = 2 },
            ["sidebar/file_browser/button"] = {},
            ChildOf = bar:id(),
        })
    end
end):in_set("sidebar/file_browser/add_button"):run_if({
    Query[{ added = { "sidebar/bar" } }],
    Query[{
        ["or"] = {
            added = { "sidebar/file_browser", "core/net/local" },
        },
        with = { "sidebar/file_browser", "core/net/local" },
    }],
}, function(new_bars, new_carriers)
    return not new_bars:is_empty() or not new_carriers:is_empty()
end)

-- A new button that was open before a reload opens again, by the path a click takes. It waits for the
-- sidebar to make it an icon: an icon drawn active reacts to `sidebar/button/open` on a node.
app:add_systems(Update, {
    Query[{
        added = { "Node" },
        with = { "sidebar/file_browser/button" },
    }],
    Query[{ with = { "sidebar/file_browser", "sidebar/file_browser/state" } }],
    Query[{ with = { "sidebar/button/open" } }],
    Commands,
}, function(icons, carriers, open_buttons, commands)
    for _, icon in ipairs(icons:iter()) do
        local carrier = carriers:iter()[1]
        local state = carrier and carrier:get("sidebar/file_browser/state")
        if state ~= nil and state.open then
            local order = 0
            for _, o in ipairs(open_buttons:iter()) do
                local opened = o:get("sidebar/button/open")
                order = math.max(order, opened.order)
            end
            commands:entity(icon:id()):insert({ ["sidebar/button/open"] = { order = order + 1 } })
        end
    end
end):in_set("sidebar/file_browser/restore")

app:add_systems(Update, {
    Query[{
        added = { "sidebar/button/open" },
        with = { "sidebar/file_browser/button" },
    }],
    Query[{ with = { "sidebar/container" } }],
    Query[{ with = { "sidebar/file_browser", Mut["sidebar/file_browser/state"] } }],
    Commands,
}, function(opened, containers, carriers, commands)
    for _, _ in ipairs(opened:iter()) do
        local container = containers:iter()[1]
        local carrier = carriers:iter_mut()[1]
        if container ~= nil and carrier ~= nil then
            local config = carrier:get("sidebar/file_browser")
            commands:spawn({
                ["sidebar/panel"] = { width = config.width },
                ["sidebar/file_browser/view"] = { folders = {} },
                ChildOf = container:id(),
            })
            local state = carrier:get("sidebar/file_browser/state")
            if not state.open then
                carrier:patch({ ["sidebar/file_browser/state"] = { open = true } })
            end
        end
    end
end):in_set("sidebar/file_browser/open")

-- Only a button still here closing is someone closing the panel. A reload takes the button too, and
-- its edge comes the same: that closes nothing, because the panel is to come back.
app:add_systems(Update, {
    Query[{
        removed = { "sidebar/button/open" },
        with = { "sidebar/file_browser/button" },
    }],
    Query[{ with = { "sidebar/file_browser/button" } }],
    Query[{ with = { "sidebar/file_browser/view" } }],
    Query[{ with = { Mut["sidebar/file_browser/state"] } }],
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
            row:patch({ ["sidebar/file_browser/state"] = { open = false } })
        end
    end
end):in_set("sidebar/file_browser/close")

-- An answer is read once: its key leaves the request, which tells the server to drop it. With no view
-- open it is only dropped: a view asks again for what it needs.
app:add_systems(Update, {
    Query[{
        with = { "sidebar/file_browser/answer", Mut["sidebar/file_browser/request"] },
    }],
    Query[{ with = { Mut["sidebar/file_browser/view"] } }],
}, function(carriers, views)
    for _, carrier in ipairs(carriers:iter_mut()) do
        local answers = carrier:get("sidebar/file_browser/answer")
        local request = carrier:get("sidebar/file_browser/request")
        local view = views:iter_mut()[1]
        local folders = {}
        if view ~= nil then
            for path, folder in pairs(view:get("sidebar/file_browser/view").folders) do
                folders[path] = folder
            end
        end
        local taken = {}
        for key, asked in pairs(request) do
            local answer = answers[key]
            if answer ~= nil then
                taken[key] = null
                local files = {}
                local existing = folders[asked.path]
                if existing ~= nil and asked.offset > 0 then
                    for _, file in ipairs(existing.files) do
                        files[#files + 1] = file
                    end
                end
                -- A page that does not follow what is held is an old one: its folder has moved on.
                if #files == asked.offset then
                    for _, file in ipairs(answer.files or {}) do
                        files[#files + 1] = file
                    end
                    folders[asked.path] = {
                        files = files,
                        has_more = answer.has_more == true,
                        unavailable = answer.error == "not available" or nil,
                    }
                end
            end
        end
        if next(taken) ~= nil then
            carrier:patch({ ["sidebar/file_browser/request"] = taken })
            if view ~= nil then
                view:set({ ["sidebar/file_browser/view"] = { folders = folders } })
            end
        end
    end
end):in_set("sidebar/file_browser/receive"):after("sidebar/file_browser/close"):run_if({
    Query[{ changed = { "sidebar/file_browser/answer" } }],
}, function(answered)
    return not answered:is_empty()
end)

-- What the view lacks is asked for, a few at a time, once the server has listed the request: a value
-- written before its sync entry arrives is never sent. The key is the ask itself, so an ask still in
-- flight through a reload is asked for once, and its answer reaches the new view. A key whose old
-- answer still stands waits for the server to drop it: asked now, the old answer would read as new.
app:add_systems(Update, {
    Query[{ with = { "sidebar/file_browser/view" } }],
    Query[{
        with = { "sidebar/file_browser", "sidebar/file_browser/state", "core/net/sync", "core/net/local" },
        optional = { "sidebar/file_browser/request", "sidebar/file_browser/answer" },
    }],
    Commands,
}, function(views, carriers, commands)
    local view = views:iter()[1]
    local carrier = carriers:iter()[1]
    if view ~= nil and carrier ~= nil then
        local sync = carrier:get("core/net/sync")
        if type(sync) == "table" and sync["sidebar/file_browser/request"] ~= nil then
            local config = carrier:get("sidebar/file_browser")
            local state = carrier:get("sidebar/file_browser/state")
            local folders = view:get("sidebar/file_browser/view").folders
            local pending = carrier:get("sidebar/file_browser/request") or {}
            local standing = carrier:get("sidebar/file_browser/answer") or {}
            local count = 0
            for _ in pairs(pending) do count = count + 1 end
            local paths = {}
            for path in pairs(state.expanded) do paths[#paths + 1] = path end
            paths[#paths + 1] = ""
            table.sort(paths)
            local asks = {}
            for _, path in ipairs(paths) do
                local folder = folders[path]
                local offset = 0
                if folder ~= nil then offset = folder.next end
                if offset ~= nil and count < config.max_requests then
                    local key = offset .. ":" .. path
                    if pending[key] == nil and standing[key] == nil then
                        count = count + 1
                        asks[key] = { op = "list", path = path, offset = offset, limit = config.page_size }
                    end
                end
            end
            if next(asks) ~= nil then
                commands:entity(carrier:id()):patch({ ["sidebar/file_browser/request"] = asks })
            end
        end
    end
end):in_set("sidebar/file_browser/ask"):after("sidebar/file_browser/receive"):run_if({
    Query[{ changed = { "sidebar/file_browser/view" } }],
    Query[{ changed = { "sidebar/file_browser/state" } }],
    Query[{ changed = { "sidebar/file_browser/request" } }],
    Query[{ changed = { "sidebar/file_browser/answer" } }],
    Query[{
        changed = { "core/net/sync" },
        with = { "sidebar/file_browser", "core/net/local" },
    }],
}, function(views, states, requests, answers, syncs)
    return not views:is_empty() or not states:is_empty() or not requests:is_empty() or not answers:is_empty() or not syncs:is_empty()
end)

-- Rows are slots by position: a slot whose row is unchanged is not written. Content the panel's
-- reload took is spawned again here.
app:add_systems(Update, {
    Query[{ with = { "sidebar/file_browser/view", Mut["sidebar/panel"] } }],
    Query[{ with = { "sidebar/file_browser", "sidebar/file_browser/state" } }],
    Query[{ with = { "sidebar/panel/scroll" } }],
    Query[{ with = { "sidebar/file_browser/rows" } }],
    Query[{ with = { Mut["sidebar/file_browser/row"], Mut["Node"] } }],
    Query[{ with = { "sidebar/file_browser/mark", Mut["Text"] } }],
    Query[{ with = { "sidebar/file_browser/name", Mut["Text"], Mut["ui/style"] } }],
    Query[{ with = { "sidebar/file_browser/size", Mut["Text"] } }],
    Commands,
}, function(views, carriers, scrolls, lists, slots, marks, names, sizes, commands)
    local view = views:iter_mut()[1]
    local carrier = carriers:iter()[1]
    local parts = view and scrolls:iter_descendants(view:id()) or {}
    local scroll = scrolls:iter_many(parts)[1]
    if carrier ~= nil and scroll ~= nil then
        local state = carrier:get("sidebar/file_browser/state")
        local folders = view:get("sidebar/file_browser/view").folders

        local rows = {}
        local function walk(path, depth)
            local folder = folders[path]
            if folder ~= nil then
                for _, file in ipairs(folder.files) do
                    local open = file.is_directory and state.expanded[file.path] == true
                    local size = ""
                    if not file.is_directory then
                        if file.size < 1024 then
                            size = file.size .. " B"
                        elseif file.size < 1024 * 1024 then
                            size = string.format("%.1f KB", file.size / 1024)
                        else
                            size = string.format("%.1f MB", file.size / (1024 * 1024))
                        end
                    end
                    rows[#rows + 1] = {
                        kind = file.is_directory and "folder" or "file",
                        path = file.path,
                        depth = depth,
                        mark = file.is_directory and (open and "v" or ">") or "",
                        text = file.name,
                        size = size,
                        role = file.is_directory and "accent" or "text",
                    }
                    if open then walk(file.path, depth + 1) end
                end
                if folder.unavailable then
                    rows[#rows + 1] = { kind = "note", path = path, depth = depth, mark = "", text = "Listing isn't available yet", size = "", role = "text_dim" }
                end
                if folder.has_more then
                    rows[#rows + 1] = { kind = "more", path = path, depth = depth, mark = "", text = "Load more...", size = "", role = "text_dim" }
                end
            end
        end
        walk("", 0)

        local list = lists:iter_many(parts)[1]
        local list_id = list and list:id()
        if list == nil then
            local refresh = commands:spawn({
                ["sidebar/file_browser/refresh"] = {},
                Button = {},
                Node = {
                    flex_shrink = 0,
                    margin = { bottom = { Px = 6 } },
                    padding = { left = { Px = 4 }, right = { Px = 4 }, top = { Px = 2 }, bottom = { Px = 2 } },
                },
                ["ui/style"] = { background = "row_alt", hover = "row_hover" },
                ChildOf = scroll:id(),
            })
            refresh:observe(On[Pointer[Click]], {
                Query[{ with = { Mut["sidebar/file_browser/view"] } }],
            }, function(event, open_views)
                for _, open in ipairs(open_views:iter_mut()) do
                    open:set({ ["sidebar/file_browser/view"] = { folders = {} } })
                end
            end)
            commands:spawn({
                Text = { text = "Refresh" },
                TextFont = { font_size = 11 },
                ["ui/style"] = { text = "text_dim" },
                ChildOf = refresh:id(),
            })
            list_id = commands:spawn({
                ["sidebar/file_browser/rows"] = {},
                Node = {
                    flex_direction = "Column",
                    align_items = "Stretch",
                    flex_shrink = 0,
                },
                ChildOf = scroll:id(),
            }):id()
        end

        local by_index = {}
        for _, slot in ipairs(slots:iter_many_mut(parts)) do
            local data = slot:get("sidebar/file_browser/row")
            if data.index > #rows then
                commands:entity(slot:id()):despawn()
            else
                by_index[data.index] = slot
            end
        end

        for index, row in ipairs(rows) do
            local slot = by_index[index]
            if slot == nil then
                local new_slot = commands:spawn({
                    ["sidebar/file_browser/row"] = { index = index, kind = row.kind, path = row.path, depth = row.depth },
                    Button = {},
                    Node = {
                        flex_direction = "Row",
                        align_items = "Center",
                        flex_shrink = 0,
                        column_gap = { Px = 4 },
                        padding = { left = { Px = 4 + row.depth * 12 }, right = { Px = 4 }, top = { Px = 2 }, bottom = { Px = 2 } },
                    },
                    ["ui/style"] = { background = index % 2 == 1 and "row_bg" or "row_alt", hover = "row_hover" },
                    ChildOf = list_id,
                })
                new_slot:observe(On[Pointer[Click]], {
                    Query[{ with = { "sidebar/file_browser/row" } }],
                    Query[{ with = { Mut["sidebar/file_browser/state"] } }],
                    Query[{ with = { Mut["sidebar/file_browser/view"] } }],
                }, function(event, clicked, states, open_views)
                    local slot_row = clicked:get(event.entity)
                    if slot_row ~= nil then
                        local data = slot_row:get("sidebar/file_browser/row")
                        if data.kind == "folder" then
                            for _, holder in ipairs(states:iter_mut()) do
                                local current = holder:get("sidebar/file_browser/state")
                                local closing = current.expanded[data.path] == true
                                holder:patch({
                                    ["sidebar/file_browser/state"] = { expanded = { [data.path] = closing and null or true } },
                                })
                                -- A folder opened again is asked for again.
                                if closing then
                                    for _, open in ipairs(open_views:iter_mut()) do
                                        open:patch({ ["sidebar/file_browser/view"] = { folders = { [data.path] = null } } })
                                    end
                                end
                            end
                        elseif data.kind == "more" then
                            for _, open in ipairs(open_views:iter_mut()) do
                                local held = open:get("sidebar/file_browser/view").folders[data.path]
                                if held ~= nil and held.has_more then
                                    open:patch({ ["sidebar/file_browser/view"] = { folders = { [data.path] = { next = #held.files } } } })
                                end
                            end
                        end
                    end
                end)
                commands:spawn({
                    ["sidebar/file_browser/mark"] = {},
                    Text = { text = row.mark },
                    TextFont = { font_size = 11 },
                    Node = { width = { Px = 10 }, flex_shrink = 0 },
                    ["ui/style"] = { text = "text_dim" },
                    ChildOf = new_slot:id(),
                })
                commands:spawn({
                    ["sidebar/file_browser/name"] = {},
                    Text = { text = row.text },
                    TextFont = { font_size = 12 },
                    Node = { flex_grow = 1, flex_shrink = 1, min_width = { Px = 0 } },
                    ["ui/style"] = { text = row.role },
                    ChildOf = new_slot:id(),
                })
                commands:spawn({
                    ["sidebar/file_browser/size"] = {},
                    Text = { text = row.size },
                    TextFont = { font_size = 11 },
                    Node = { flex_shrink = 0 },
                    ["ui/style"] = { text = "text_dim" },
                    ChildOf = new_slot:id(),
                })
            else
                local data = slot:get("sidebar/file_browser/row")
                if data.kind ~= row.kind or data.path ~= row.path or data.depth ~= row.depth then
                    slot:patch({ ["sidebar/file_browser/row"] = { kind = row.kind, path = row.path, depth = row.depth } })
                end
                if data.depth ~= row.depth then
                    slot:patch({ Node = { padding = { left = { Px = 4 + row.depth * 12 } } } })
                end
                local inside = names:iter_descendants(slot:id())
                for _, part in ipairs(marks:iter_many_mut(inside)) do
                    write_text(part, row.mark)
                end
                for _, part in ipairs(names:iter_many_mut(inside)) do
                    write_text(part, row.text)
                    if part:get("ui/style").text ~= row.role then
                        part:patch({ ["ui/style"] = { text = row.role } })
                    end
                end
                for _, part in ipairs(sizes:iter_many_mut(inside)) do
                    write_text(part, row.size)
                end
            end
        end

        local panel = view:get("sidebar/panel")
        if panel.title == nil and folders[""] ~= nil then
            view:patch({ ["sidebar/panel"] = { title = "Files" } })
        end
    end
end):in_set("sidebar/file_browser/render"):after("sidebar/file_browser/receive"):run_if({
    Query[{ changed = { "sidebar/file_browser/view" } }],
    Query[{ changed = { "sidebar/file_browser/state" } }],
    Query[{ added = { "sidebar/panel/scroll" } }],
}, function(views, states, scrolls)
    return not views:is_empty() or not states:is_empty() or not scrolls:is_empty()
end)

return {
    defaults = {
        ["sidebar/file_browser/view"] = {
            folders = {},
        },
    },
}
