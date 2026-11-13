-- edit/notice: what is happening to this player's edits, said on screen. Core states each upload in
-- flight as `core/library/upload { path, bytes, total, got, state }`, a child of its library; this
-- mod shows one card for each that is more than one chunk: "Waiting for the world to accept <path>…"
-- while the world's write policy decides, then "Sending <path>" with a bar of what the world holds.
-- Local UI: never synced. A world's client boot (or a mod it uses) adds `edit/notice` to an entity
-- of its own, and the cards go with it.
--
-- edit/notice = {}
--
-- edit/notice/card = { path = <the upload's path> }: the card, a notification. Its children are its
-- line (`Text`) and the bar's track, whose child is the fill, `edit/notice/bar = {}`.

local MB = 1024 * 1024

--- "x / y MB" for `got` of `total` chunks of a `bytes` long file.
local function amount(row)
    local held = (row.total or 0) > 0 and row.bytes * math.min(1, (row.got or 0) / row.total) or 0
    return string.format("%.1f / %.1f MB", held / MB, (row.bytes or 0) / MB)
end

local function line(row)
    if row.state == "sending" then
        return string.format("Sending %s — %s", tostring(row.path), amount(row))
    end
    return string.format("Waiting for the world to accept %s…", tostring(row.path))
end

local function filled(row)
    if row.state ~= "sending" or (row.total or 0) <= 0 then return 0 end
    return math.min(100, (row.got or 0) / row.total * 100)
end

-- Each upload of more than one chunk gets a card, and its line and bar follow the row. A one-chunk
-- upload is answered within a frame or two, so it shows nothing.
app:add_systems(Update, {
    Query[{
        ["or"] = { added = { "core/library/upload" }, changed = { "core/library/upload" } },
        without = { "WorldMirror" },
    }],
    Query[{ with = { "edit/notice/card" }, optional = { "Children", "notification", "notification/fade" } }],
    Query[{ with = { Mut["Text"], "ChildOf" } }],
    Query[{ with = { "Node", "Children" }, without = { "Text", "edit/notice/card" } }],
    Query[{ with = { "edit/notice/bar", Mut["Node"] } }],
    Commands,
}, function(rows, cards, texts, tracks, bars, commands)
    for _, r in ipairs(rows:iter()) do
        local row = r:get("core/library/upload")
        if (row.total or 0) > 1 then
            local card
            for _, c in ipairs(cards:iter()) do
                local n = c:get("notification")
                if c:get("edit/notice/card").path == row.path and not (n and n.dismiss) and not c:has("notification/fade") then
                    card = c
                    break
                end
            end
            if card == nil then
                local id = commands:spawn({
                    ["edit/notice/card"] = { path = row.path },
                    notification = { width = 320 },
                }):id()
                commands:spawn({
                    Text = { text = line(row) },
                    TextFont = { font_size = 11 },
                    ["ui/style"] = { text = "text" },
                    ChildOf = id,
                })
                local track = commands:spawn({
                    Node = { width = { Percent = 100 }, height = { Px = 4 } },
                    ["ui/style"] = { background = "border" },
                    ChildOf = id,
                }):id()
                commands:spawn({
                    ["edit/notice/bar"] = {},
                    Node = { width = { Percent = filled(row) }, height = { Px = 4 } },
                    ["ui/style"] = { background = "accent" },
                    ChildOf = track,
                })
            else
                for _, t in ipairs(texts:iter_many_mut(card:get("Children") or {})) do
                    t:get_mut("Text"):set_if_neq(line(row))
                end
                for _, track in ipairs(tracks:iter_many(card:get("Children") or {})) do
                    for _, b in ipairs(bars:iter_many_mut(track:get("Children") or {})) do
                        b:get_mut("Node").width = { Percent = filled(row) }
                    end
                end
            end
        end
    end
end):in_set("edit/notice")
    :run_if({
        Query[{ ["or"] = { added = { "core/library/upload" }, changed = { "core/library/upload" } } }],
    }, function(touched)
        return not touched:is_empty()
    end)

-- An upload answered or dropped: its card fades out.
app:add_systems(Update, {
    Query[{ with = { "core/library/upload" }, without = { "WorldMirror" } }],
    Query[{ with = { "edit/notice/card", Mut["notification"] } }],
}, function(rows, cards)
    local live = {}
    for _, r in ipairs(rows:iter()) do live[r:get("core/library/upload").path] = true end
    for _, c in ipairs(cards:iter_mut()) do
        if not live[c:get("edit/notice/card").path] and not c:get("notification").dismiss then
            c:get_mut("notification").dismiss = true
        end
    end
end):in_set("edit/notice")
    :run_if({ Query[{ ["or"] = { removed = { "core/library/upload" } } }] }, function(gone)
        return not gone:is_empty()
    end)

return {}
