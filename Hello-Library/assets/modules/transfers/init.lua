-- transfers: this world's files in transit, in a screen corner. Core states each as a child row of
-- its library, never synced: `core/library/download { ref, path, total, got }` in bytes, shared
-- across the process's VMs, and `core/library/upload { path, bytes, total, got, state = "waiting" |
-- "sending" }`, this VM's own, with `total` and `got` in chunks of a `bytes` long file. While any row
-- of more than one chunk is here, an icon sits in the bottom-right corner saying how many go each
-- way; hovered, it shows one line per transfer: its direction, path, "x / y MB" and a bar, or that an
-- upload still waits for the world.
--
-- transfers = {}: the carrier, which a world's boot names in its `base` list.
--
-- transfers/icon = {}: the icon, a Button; its children are its count (`Text`) and the list.
--
-- transfers/list = {}: the list, shown while the icon is hovered. Each child is one transfer's line:
-- its `Text` and the bar's track, whose child is the fill.

local MB = 1024 * 1024

--- Every transfer of more than one chunk, downloads first, each by path. A download made in
--- another VM counts only when its library is one this world asks (its own `core/library/fetch`
--- rows name it): every VM sees every library VM's rows, and other worlds' too.
local function transfers(uploads, downloads, asks)
    local out, asked = {}, {}
    for _, a in ipairs(asks:iter()) do asked[a:get("core/library/fetch").ref] = true end
    for _, r in ipairs(downloads:iter()) do
        local row = r:get("core/library/download")
        if not r:has("WorldMirror") or (row.ref ~= nil and asked[row.ref]) then
            out[#out + 1] = { dir = "down", path = tostring(row.path), got = row.got or 0, size = row.total or 0 }
        end
    end
    for _, r in ipairs(uploads:iter()) do
        local row = r:get("core/library/upload")
        if (row.total or 0) > 1 then
            out[#out + 1] = {
                dir = "up", path = tostring(row.path), size = row.bytes or 0,
                got = (row.bytes or 0) * math.min(1, (row.got or 0) / row.total),
                waiting = row.state ~= "sending",
            }
        end
    end
    table.sort(out, function(a, b)
        if a.dir ~= b.dir then return a.dir == "down" end
        return a.path < b.path
    end)
    return out
end

local function count(list)
    local up, down = 0, 0
    for _, t in ipairs(list) do
        if t.dir == "up" then up = up + 1 else down = down + 1 end
    end
    local parts = {}
    if down > 0 then parts[#parts + 1] = string.format("%d down", down) end
    if up > 0 then parts[#parts + 1] = string.format("%d up", up) end
    return table.concat(parts, "  ")
end

local function words(t)
    local amount = string.format("%.1f / %.1f MB", t.got / MB, t.size / MB)
    if t.waiting then amount = amount .. ", waiting for the world" end
    return string.format("%s  %s  %s", t.dir, t.path, amount)
end

local function share(t)
    if t.waiting or t.size <= 0 then return 0 end
    return math.min(100, t.got / t.size * 100)
end

--- One line under `list` for each transfer.
local function draw(commands, list, all)
    for _, t in ipairs(all) do
        local line = commands:spawn({
            Node = { flex_direction = "Column", row_gap = { Px = 3 } },
            ChildOf = list,
        }):id()
        commands:spawn({
            Text = { text = words(t) },
            TextFont = { font_size = 11 },
            ["ui/style"] = { text = t.waiting and "text_dim" or "text" },
            ChildOf = line,
        })
        local track = commands:spawn({
            Node = { width = { Percent = 100 }, height = { Px = 4 } },
            ["ui/style"] = { background = "border" },
            ChildOf = line,
        }):id()
        commands:spawn({
            Node = { width = { Percent = share(t) }, height = { Px = 4 } },
            ["ui/style"] = { background = "accent" },
            ChildOf = track,
        })
    end
end

local function hovered(icon)
    local i = icon:get("Interaction")
    return i == "Hovered" or i == "Pressed"
end

-- The icon follows the rows: here while a transfer is (and a carrier), gone with the last. Its count
-- follows them, and so does the list while the icon is hovered; the list shows on the hover's edge.
app:add_systems(Update, {
    Query[{ with = { "core/library/upload" }, without = { "WorldMirror" } }],
    Query[{ with = { "core/library/download" }, optional = { "WorldMirror" } }],
    Query[{ with = { "core/library/fetch" }, without = { "WorldMirror" } }],
    Query[{ with = { "transfers" } }],
    Query[{ with = { "transfers/icon" }, optional = { "Children", "Interaction" } }],
    Query[{ with = { "transfers/list", Mut["Node"] }, optional = { "Children" } }],
    Query[{ with = { Mut["Text"], "ChildOf" } }],
    Commands,
}, function(uploads, downloads, asks, carriers, icons, lists, texts, commands)
    local all = carriers:is_empty() and {} or transfers(uploads, downloads, asks)
    local shown = icons:iter()
    if #all == 0 then
        for _, icon in ipairs(shown) do commands:entity(icon:id()):despawn() end
        return
    end
    local icon = shown[1]
    if icon == nil then
        local id = commands:spawn({
            ["transfers/icon"] = {},
            Button = {},
            Node = {
                position_type = "Absolute",
                right = { Px = 16 },
                bottom = { Px = 16 },
                padding = { left = { Px = 10 }, right = { Px = 10 }, top = { Px = 6 }, bottom = { Px = 6 } },
                border = { left = { Px = 1 }, right = { Px = 1 }, top = { Px = 1 }, bottom = { Px = 1 } },
            },
            BorderRadius = {
                top_left = { Px = 6 }, top_right = { Px = 6 },
                bottom_left = { Px = 6 }, bottom_right = { Px = 6 },
            },
            -- above the notifications (600), which share the right edge
            GlobalZIndex = { value = 610 },
            ["ui/style"] = { background = "icon_bg", hover = "icon_hover", border = "border" },
        }):id()
        commands:spawn({
            Text = { text = count(all) },
            TextFont = { font_size = 12 },
            ["ui/style"] = { text = "text" },
            ChildOf = id,
        })
        commands:spawn({
            ["transfers/list"] = {},
            Node = {
                display = "None",
                position_type = "Absolute",
                right = { Px = 0 },
                bottom = { Percent = 100 },
                margin = { bottom = { Px = 6 } },
                width = { Px = 320 },
                flex_direction = "Column",
                row_gap = { Px = 6 },
                padding = { left = { Px = 10 }, right = { Px = 10 }, top = { Px = 8 }, bottom = { Px = 8 } },
                border = { left = { Px = 1 }, right = { Px = 1 }, top = { Px = 1 }, bottom = { Px = 1 } },
            },
            BorderRadius = {
                top_left = { Px = 6 }, top_right = { Px = 6 },
                bottom_left = { Px = 6 }, bottom_right = { Px = 6 },
            },
            ["ui/style"] = { background = "bg", border = "border" },
            ChildOf = id,
        })
        return
    end
    for _, t in ipairs(texts:iter_many_mut(icon:get("Children") or {})) do
        t:get_mut("Text"):set_if_neq(count(all))
    end
    for _, list in ipairs(lists:iter_many_mut(icon:get("Children") or {})) do
        for _, line in ipairs(list:get("Children") or {}) do commands:entity(line):despawn() end
        if hovered(icon) then
            list:get_mut("Node").display = "Flex"
            draw(commands, list:id(), all)
        else
            list:get_mut("Node").display = "None"
        end
    end
end):in_set("transfers")
    :run_if({
        Query[{
            ["or"] = {
                added = { "core/library/upload", "core/library/download", "core/library/fetch", "transfers" },
                changed = { "core/library/upload", "core/library/download" },
            },
        }],
        Query[{ ["or"] = { removed = { "core/library/upload", "core/library/download", "core/library/fetch" } } }],
        Query[{ changed = { "Interaction" }, with = { "transfers/icon" } }],
    }, function(rows, gone, hover)
        return not (rows:is_empty() and gone:is_empty() and hover:is_empty())
    end)

return {}
