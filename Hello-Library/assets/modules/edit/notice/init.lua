-- edit/notice: what is happening to this player's edits, said on screen. Core states each upload in
-- flight as `core/library/upload { path, bytes, total, got, state }`, a child of its library; this
-- mod shows one card for each that is more than one chunk: "Waiting for the world to accept <path>…"
-- once the world's write policy has been deciding for 10 s, and "Sending <path>" with a bar of what
-- the world holds as soon as it streams. Local UI: never synced. A world's client boot (or a mod it
-- uses) adds `edit/notice` to an entity of its own, and the cards go with it.
--
-- edit/notice = {}
--
-- edit/notice/card = { path = <the upload's path> }: the card. While it waits to be shown it carries
-- the `cooldown` timer `edit/notice/wait`; shown, it is a notification, and its children are its line
-- (`Text`) and the bar's track, whose child is the fill, `edit/notice/bar = {}`.

local MB = 1024 * 1024
local WAIT = 10

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

--- Makes card `id` a notification showing `row`.
local function show(commands, id, row)
    commands:entity(id):insert({ notification = { width = 320 } })
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
end

-- Each upload of more than one chunk gets a card. A card for an upload still waiting is shown once
-- its timer ends; one streaming is shown at once, and its line and bar follow the row. A one-chunk
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
                local id = commands:spawn({ ["edit/notice/card"] = { path = row.path } }):id()
                if row.state == "sending" then
                    show(commands, id, row)
                else
                    commands:entity(id):insert({ cooldown = { ["edit/notice/wait"] = { remaining = WAIT } } })
                end
            elseif not card:has("notification") then
                if row.state == "sending" then show(commands, card:id(), row) end
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

-- A card's wait is over: shown, if its upload is still waiting and the card is not shown yet.
app:add_systems(Update, {
    Query[{ removed = { "edit/notice/wait" }, with = { "edit/notice/card" }, optional = { "notification" } }],
    Query[{ with = { "core/library/upload" }, without = { "WorldMirror" } }],
    Commands,
}, function(waited, rows, commands)
    for _, c in ipairs(waited:iter()) do
        if not c:has("notification") then
            for _, r in ipairs(rows:iter()) do
                local row = r:get("core/library/upload")
                if row.path == c:get("edit/notice/card").path then
                    show(commands, c:id(), row)
                    break
                end
            end
        end
    end
end):in_set("edit/notice")

-- An upload answered or dropped: its card fades out, or goes if it was never shown.
app:add_systems(Update, {
    Query[{ with = { "core/library/upload" }, without = { "WorldMirror" } }],
    Query[{ with = { "edit/notice/card" }, optional = { Mut["notification"] } }],
    Commands,
}, function(rows, cards, commands)
    local live = {}
    for _, r in ipairs(rows:iter()) do live[r:get("core/library/upload").path] = true end
    for _, c in ipairs(cards:iter_mut()) do
        if not live[c:get("edit/notice/card").path] then
            if not c:has("notification") then
                commands:entity(c:id()):despawn()
            elseif not c:get("notification").dismiss then
                c:get_mut("notification").dismiss = true
            end
        end
    end
end):in_set("edit/notice")
    :run_if({ Query[{ ["or"] = { removed = { "core/library/upload" } } }] }, function(gone)
        return not gone:is_empty()
    end)

--- The title and line for a replacement core recorded (`core/library/replaced`), or nil for one
--- that says nothing worth a card.
local function replaced_words(r)
    local kept = r.kept ~= nil and string.format(" in .hello/held/%s", tostring(r.kept)) or ""
    if r.both and r.by == "me" and r.kept == nil then
        return "MERGED", string.format("%s changed here and in the world; the changes were merged.", tostring(r.path))
    elseif r.both and r.by == "me" then
        return "BOTH CHANGED", string.format("%s changed here and in the world. Your newer copy is kept; the world's is%s.",
            tostring(r.path), kept)
    elseif r.both then
        return "BOTH CHANGED", string.format("%s changed here and in the world. The world's newer copy is kept; yours is%s.",
            tostring(r.path), kept)
    elseif r.by == "world" then
        return "REPLACED", string.format("The world's newer %s replaced your copy.%s", tostring(r.path),
            r.kept ~= nil and (" Yours is" .. kept .. ".") or "")
    end
    return "WENT UP", string.format("Your newer %s went up.", tostring(r.path))
end

-- Each replacement core records gets a card that goes after 20 s, and outlives this mod meanwhile.
app:add_systems(Update, {
    Query[{ added = { "core/library/replaced" }, without = { "WorldMirror" } }],
    Query[{ with = { "edit/notice" } }],
    Commands,
}, function(rows, carriers, commands)
    if carriers:is_empty() then return end
    for _, r in ipairs(rows:iter()) do
        local title, text = replaced_words(r:get("core/library/replaced"))
        local id = commands:spawn({ notification = { timeout = 20, width = 320 }, ["core/script/owner"] = false }):id()
        commands:spawn({ Text = { text = title }, TextFont = { font_size = 9 }, ["ui/style"] = { text = "accent" }, ChildOf = id })
        commands:spawn({ Text = { text = text }, TextFont = { font_size = 11 }, ["ui/style"] = { text = "text" }, ChildOf = id })
    end
end):in_set("edit/notice")
    :run_if({ Query[{ added = { "core/library/replaced" } }] }, function(added)
        return not added:is_empty()
    end)

return {}
