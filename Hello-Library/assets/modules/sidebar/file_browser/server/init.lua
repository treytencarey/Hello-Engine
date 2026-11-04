-- The server half of the file browser: answers the player who asks about this world's files, and
-- does nothing else. Any player can ask, so it changes no file, never lists or opens a private name,
-- and never says where the world's folder is: paths are relative to `core/world/files.root`, which
-- stays here. Reading a folder is not available yet (`listing.lua`): a path that passes answers so.
-- It keeps nothing about a player but the answers the player has not taken yet, so a reload loses
-- nothing.
--
-- sidebar/file_browser/request = {
--     <key> = {
--         op = "list",
--         path = <folder, relative to the world's files; "" for the top>,
--         offset = <entries to skip>,
--         limit = <entries wanted>,
--     },
-- }
--
-- sidebar/file_browser/answer = {
--     <key> = {
--         op = "list",
--         path = <the folder asked for>,
--         offset = <entries skipped>,
--         files = { { name = <text>, path = <relative>, is_directory = <boolean>, size = <bytes> } },
--         has_more = <whether entries follow this page>,
--         total_count = <entries a client may see in the folder>,
--     },
--     <key of a path that passes, while a folder cannot be read> = { op = "list", path, offset, error = "not available" },
--     <key of an ask refused> = { error = "refused" },
-- }

local Listing = require("modules/sidebar/file_browser/server/listing.lua")

app:add_systems(First, {
    Query[{
        added = { "sidebar/file_browser" },
        optional = { "core/net/sync" },
    }],
    Commands,
}, function(carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        local sync = e:get("core/net/sync")
        if type(sync) == "table" and sync["sidebar/file_browser/request"] == nil then
            commands:entity(e:id()):patch({
                ["core/net/sync"] = {
                    ["sidebar/file_browser/request"] = { authority = "client", target = "owner" },
                    ["sidebar/file_browser/answer"] = { authority = "server", target = "owner" },
                },
            })
        end
    end
end):in_set("sidebar/file_browser/init")

-- The component was taken off an entity that stays: the sync this half added goes too. A despawned
-- player is in the `removed` rows as well. In `Update`: the registry writes this entity's sync on the
-- same edge in `First`, and a write beside it there did not land.
app:add_systems(Update, {
    Query[{ removed = { "sidebar/file_browser" } }],
    Query[{ with = { "core/net/sync" } }],
    Commands,
}, function(removed, synced, commands)
    for _, e in ipairs(removed:iter()) do
        if synced:contains(e:id()) then
            commands:entity(e:id()):patch({
                ["core/net/sync"] = {
                    ["sidebar/file_browser/request"] = null,
                    ["sidebar/file_browser/answer"] = null,
                },
            })
        end
    end
end):in_set("sidebar/file_browser/removed")

-- The owner took its whole request away: no answer stands.
app:add_systems(Update, {
    Query[{
        removed = { "sidebar/file_browser/request" },
        with = { "sidebar/file_browser", Mut["sidebar/file_browser/answer"] },
    }],
}, function(left)
    for _, e in ipairs(left:iter_mut()) do
        e:set({ ["sidebar/file_browser/answer"] = {} })
    end
end):in_set("sidebar/file_browser/forget")

-- Each ask is answered under its key, and the answer stands until the owner takes the key out of its
-- request, so two asks in quick succession both land. The value is the client's word: anything in it
-- may be any shape. A request holding more asks than the bound is refused whole, and its size is
-- found without walking past the bound: the client writes this table, and each ask costs a listing.
-- The answer is replaced whole: a key taken out goes, and a list that shrank shrinks.
app:add_systems(Update, {
    Query[{ with = { "core/world/files" } }],
    Query[{
        changed = { "sidebar/file_browser/request" },
        with = { "sidebar/file_browser" },
        optional = { "sidebar/file_browser/answer" },
    }],
    Commands,
}, function(worlds, asking, commands)
    for _, e in ipairs(asking:iter()) do
        local config = e:get("sidebar/file_browser")
        local request = e:get("sidebar/file_browser/request")
        local standing = e:get("sidebar/file_browser/answer") or {}
        local asks = type(request) == "table" and request or {}
        local count = 0
        for _ in pairs(asks) do
            count = count + 1
            if count > config.max_requests then
                asks = {}
                break
            end
        end
        local answers, wrote = {}, false
        for key, asked in pairs(asks) do
            if type(key) == "string" and #key <= config.max_path + 32 then
                local kept = standing[key]
                local is_table = type(asked) == "table"
                if kept ~= nil and is_table and kept.path == asked.path and kept.offset == (asked.offset or 0) then
                    answers[key] = kept
                else
                    wrote = true
                    local path = is_table and asked.path
                    local offset = is_table and (asked.offset or 0)
                    local limit = is_table and (asked.limit or config.max_limit)
                    local plain = is_table and asked.op == "list"
                        and type(path) == "string" and #path <= config.max_path
                        and type(offset) == "number" and offset >= 0
                        and type(limit) == "number" and limit >= 1
                    if plain and path:find("\\", 1, true) then plain = false end
                    if plain and path:find(":", 1, true) then plain = false end
                    if plain and path:find("%c") then plain = false end
                    if plain and path ~= "" then
                        -- An absolute path, `a//b` and `a/` each hold an empty name, which is private.
                        for name in (path .. "/"):gmatch("([^/]*)/") do
                            if Listing.is_private(name) then plain = false end
                        end
                    end
                    if not plain then
                        answers[key] = { error = "refused" }
                    else
                        offset = math.floor(offset)
                        limit = math.min(math.floor(limit), config.max_limit)
                        local entries, why = Listing.read(worlds:iter()[1]:get("core/world/files").root, path)
                        if entries == nil then
                            answers[key] = { op = "list", path = path, offset = offset, error = why }
                        else
                            answers[key] = Listing.page(Listing.sorted(Listing.visible(entries)), path, offset, limit)
                        end
                    end
                end
            end
        end
        for key in pairs(standing) do
            if answers[key] == nil then wrote = true end
        end
        if wrote or not e:has("sidebar/file_browser/answer") then
            commands:entity(e:id()):try_insert({ ["sidebar/file_browser/answer"] = answers })
        end
    end
end):in_set("sidebar/file_browser/serve"):after("sidebar/file_browser/forget")

return {
    ["core/net/sync"] = {
        authority = "server",
        target = "owner",
    },
}
