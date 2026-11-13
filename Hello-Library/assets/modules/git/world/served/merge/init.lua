-- git/world/served/merge: git's three-way text merge, as core's resolver for a file both the player
-- and the world changed. Core asks with `core/library/merge { path, mine, theirs }` (theirs being the
-- world's version, kept in the held store) when the tree's provider says it merges; this mod asks
-- root to merge it into the player's checkout with `vault/git/merge`, `apply = "clean"`, so root
-- writes only a merge with no conflict. It answers `core/library/merge/reply { status }`: "merged"
-- when root wrote it, "no" otherwise, and core then keeps the newer copy. No markers are ever
-- written. A sub-mod of git/world/served, which adds and removes it.
--
-- git/world/served/merge = {}
--
-- git/world/served/merge/result = {
--     key = <the file, asset relative>,
--     hash = <the world's version being merged>,
--     asked_at = <seconds since the world started, when root was asked>,
--     status = "clean" | "conflict" | "failed", absent while root's request is open,
-- }
-- One per file asked, a child of the carrier, while core's request for it is open.

local Time = require("bevy::time::Time")

--- Core's request for `record`'s file and version, among `asks`.
local function core_ask(asks, record)
    for _, a in ipairs(asks:iter()) do
        local m = a:get("core/library/merge")
        if m.path == record.key and m.theirs == record.hash then return a end
    end
end

-- Each new request of core's asks root once, with a record for it.
app:add_systems(Update, {
    Res[Time],
    Query[{ added = { "core/library/merge" }, without = { "WorldMirror", "core/library/merge/reply" } }],
    Query[{ with = { "git/world/served/merge" }, without = { "WorldMirror" } }],
    Commands,
}, function(time, asked, carriers, commands)
    local carrier = carriers:iter()[1]
    if carrier == nil then return end
    for _, a in ipairs(asked:iter()) do
        local m = a:get("core/library/merge")
        commands:spawn({
            ["vault/git/merge"] = {},
            ["vault/git"] = { path = "assets/" .. m.path, hash = m.theirs, apply = "clean" },
            Request = {},
            ChildOf = carrier:id(),
        })
        commands:spawn({
            ["git/world/served/merge/result"] = { key = m.path, hash = m.theirs, asked_at = time:elapsed_secs() },
            ChildOf = carrier:id(),
        })
    end
end):in_set("git/world/served/merge")
    :run_if({ Query[{ added = { "core/library/merge" } }] }, function(asked)
        return not asked:is_empty()
    end)

-- Root's answer, or none in 30 s (a world root did not start is never answered): the record says how
-- it went, root's request closes, and core's request gets its reply.
app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "git/world/served/merge" }, without = { "WorldMirror" }, optional = { "Children" } }],
    Query[{ with = { "vault/git/merge", "vault/git" }, without = { "RequestFrom" }, optional = { "vault/git/merge/reply" } }],
    Query[{ with = { Mut["git/world/served/merge/result"] } }],
    Query[{ with = { "core/library/merge" }, without = { "WorldMirror", "core/library/merge/reply" } }],
    Commands,
}, function(time, carriers, requests, records, asks, commands)
    local now = time:elapsed_secs()
    for _, carrier in ipairs(carriers:iter()) do
        local children = carrier:get("Children") or {}
        for _, request in ipairs(requests:iter_many(children)) do
            local values = request:get("vault/git")
            local path = tostring(values.path):match("^assets/(.+)$")
            for _, row in ipairs(records:iter_many_mut(children)) do
                local record = row:get("git/world/served/merge/result")
                if record.key == path and record.hash == values.hash and record.status == nil then
                    local reply = request:has("vault/git/merge/reply") and request:get("vault/git/merge/reply") or nil
                    if reply == nil and now - record.asked_at >= 30 then
                        reply = { status = "failed", message = "git did not answer" }
                    end
                    if reply ~= nil then
                        local status = reply.status == "refused" and "failed" or reply.status
                        row:get_mut("git/world/served/merge/result").status = status
                        local ask = core_ask(asks, record)
                        if ask then
                            commands:entity(ask:id()):insert({ ["core/library/merge/reply"] = {
                                status = status == "clean" and "merged" or "no",
                            } })
                        end
                        print(string.format("[GIT/WORLD/SERVED/MERGE] %s: %s", path, status == "clean"
                            and "merged the world's version and yours" or ("no merge: " .. tostring(reply.message or status))))
                        commands:entity(request:id()):try_despawn()
                    end
                end
            end
        end
    end
end):in_set("git/world/served/merge")
    -- A reply crosses from root's VM, and a mirrored edge arrives as surely as a local one, so this
    -- runs on the reply's edge, and otherwise only when a record still waiting reaches its 30 s.
    :run_if({
        Res[Time],
        Query[{ added = { "vault/git/merge/reply" } }],
        Query[{ with = { "git/world/served/merge/result" } }],
    }, function(time, arrived, records)
        if not arrived:is_empty() then return true end
        local now = time:elapsed_secs()
        for _, row in ipairs(records:iter()) do
            local record = row:get("git/world/served/merge/result")
            if record.status == nil and now - record.asked_at >= 30 then return true end
        end
        return false
    end)

-- Core's request gone: its record goes, and root's request if it is still open.
app:add_systems(Update, {
    Query[{ with = { "git/world/served/merge" }, without = { "WorldMirror" }, optional = { "Children" } }],
    Query[{ with = { "git/world/served/merge/result" } }],
    Query[{ with = { "vault/git/merge", "vault/git" }, without = { "RequestFrom" } }],
    Query[{ with = { "core/library/merge" }, without = { "WorldMirror" } }],
    Commands,
}, function(carriers, records, requests, asks, commands)
    for _, carrier in ipairs(carriers:iter()) do
        local children = carrier:get("Children") or {}
        for _, row in ipairs(records:iter_many(children)) do
            local record = row:get("git/world/served/merge/result")
            if core_ask(asks, record) == nil then
                commands:entity(row:id()):try_despawn()
                for _, request in ipairs(requests:iter_many(children)) do
                    local values = request:get("vault/git")
                    if values.path == "assets/" .. record.key and values.hash == record.hash then
                        commands:entity(request:id()):try_despawn()
                    end
                end
            end
        end
    end
end):in_set("git/world/served/merge")
    :run_if({ Query[{ ["or"] = { removed = { "core/library/merge" } } }] }, function(gone)
        return not gone:is_empty()
    end)

-- git/world/served/merge taken off an entity that stays: its open requests go, which stops their
-- git processes. Its records are its sub-components, which the registry takes with it.
app:add_systems(Update, {
    Query[{
        removed = { "git/world/served/merge" },
        optional = { "Children" },
    }],
    Query[{
        with = { "vault/git/merge", "vault/git" },
        without = { "RequestFrom" },
    }],
    Commands,
}, function(removed, asks, commands)
    for _, e in ipairs(removed:iter()) do
        for _, ask in ipairs(asks:iter_many(e:get("Children") or {})) do
            commands:entity(ask:id()):try_despawn()
        end
    end
end)

return {}
