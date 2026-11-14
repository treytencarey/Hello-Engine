-- edit/notice: what happened to this player's edits, said on screen. Core records each copy it
-- replaced as `core/library/replaced { path, by, kept?, both? }`, a child of its library; this mod
-- shows a card for each. Local UI: never synced. A world's client boot (or a mod it uses) adds
-- `edit/notice` to an entity of its own. Uploads in flight are `transfers`'s.
--
-- edit/notice = {}

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
