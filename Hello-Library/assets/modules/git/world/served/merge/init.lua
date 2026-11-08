-- git/world/served/merge: the world's version of a file the player edited, merged into their
-- checkout. Core holds what could not land (`core/library/upstream.held[path]`), and this mod asks
-- root to merge it with `vault/git/merge`, `apply = true`. Root writes the result into the checkout,
-- and core's watcher picks it up. After a clean merge the path's `core/library/edit` names the held
-- version (`on`), so the save that follows expects it and lands. A conflict leaves git's markers in
-- the player's file, and a notice. A sub-mod of git/world/served, which adds and removes it.
--
-- git/world/served/merge = {}
--
-- git/world/served/merge/result = {
--     key = <the file, asset relative, as `held` names it>,
--     hash = <the held version being merged>,
--     asked_at = <seconds since the world started, when the request was sent>,
--     status = "clean" | "conflict" | "failed", absent while the request is open,
-- }
-- One per file, a child of the carrier, while that file is held at that version.

local Time = require("bevy::time::Time")

local function notice(commands, title, text)
    commands:spawn({
        ["git/merge/notice"] = { title = title, text = text },
        notification = { timeout = 20 },
        ["core/script/owner"] = false,
    })
end

-- What is held asks a merge, once per held version, and the file's record is spawned with the
-- request. A request or a record for a version no longer held goes, so a file held again at a new
-- version is merged again.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "git/world/served/merge" },
        without = { "WorldMirror" },
        optional = { "Children" },
    }],
    Query[{
        with = { "core/library", "core/library/upstream" },
        without = { "WorldMirror" },
    }],
    Query[{
        with = { "vault/git/merge", "vault/git" },
        without = { "RequestFrom" },
    }],
    Query[{ with = { "git/world/served/merge/result" } }],
    Commands,
}, function(time, carriers, libraries, asks, records, commands)
    local held = {}
    for _, lib in ipairs(libraries:iter()) do
        local up = lib:get("core/library/upstream")
        if lib:get("core/library").edits and type(up.held) == "table" then
            for path, hash in pairs(up.held) do
                if type(hash) == "number" then held[path] = hash end
            end
        end
    end
    for _, carrier in ipairs(carriers:iter()) do
        local children = carrier:get("Children") or {}
        local known = {}
        for _, row in ipairs(records:iter_many(children)) do
            local record = row:get("git/world/served/merge/result")
            if held[record.key] == record.hash and not known[record.key] then
                known[record.key] = true
            else
                commands:entity(row:id()):despawn()
            end
        end
        for _, ask in ipairs(asks:iter_many(children)) do
            local values = ask:get("vault/git")
            local path = tostring(values.path):match("^assets/(.+)$")
            if path == nil or held[path] ~= values.hash or not known[path] then
                commands:entity(ask:id()):try_despawn()
            end
        end
        for path, hash in pairs(held) do
            if not known[path] then
                commands:spawn({
                    ["vault/git/merge"] = {},
                    ["vault/git"] = { path = "assets/" .. path, hash = hash, apply = true },
                    Request = {},
                    ChildOf = carrier:id(),
                })
                commands:spawn({
                    ["git/world/served/merge/result"] = { key = path, hash = hash, asked_at = time:elapsed_secs() },
                    ChildOf = carrier:id(),
                })
            end
        end
    end
end):in_set("git/world/served/merge")
    :run_if({
        Query[{
            ["or"] = {
                added = { "git/world/served/merge", "core/library/upstream" },
                changed = { "core/library/upstream" },
            },
            without = { "WorldMirror" },
        }],
    }, function(touched)
        return not touched:is_empty()
    end)

-- Root's answer, or none in time: a world root did not start is never answered. Either way the
-- file's record says how its merge went, and the request is closed, which stops its git process.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "git/world/served/merge" },
        without = { "WorldMirror" },
        optional = { "Children" },
    }],
    Query[{
        with = { "vault/git/merge", "vault/git" },
        without = { "RequestFrom" },
        optional = { "vault/git/merge/reply" },
    }],
    Query[{ with = { Mut["git/world/served/merge/result"] } }],
    Commands,
}, function(time, carriers, asks, records, commands)
    local now = time:elapsed_secs()
    for _, carrier in ipairs(carriers:iter()) do
        local children = carrier:get("Children") or {}
        for _, ask in ipairs(asks:iter_many(children)) do
            local values = ask:get("vault/git")
            local path = tostring(values.path):match("^assets/(.+)$")
            local kept = nil
            for _, row in ipairs(records:iter_many_mut(children)) do
                local record = row:get("git/world/served/merge/result")
                if record.key == path and record.hash == values.hash then kept = row end
            end
            local record = kept and kept:get_mut("git/world/served/merge/result")
            local reply = ask:has("vault/git/merge/reply") and ask:get("vault/git/merge/reply") or nil
            if reply == nil and record ~= nil and now - record.asked_at >= 30 then
                reply = { status = "failed", message = "git did not answer" }
            end
            if record ~= nil and reply ~= nil then
                local status = reply.status
                if status == "refused" then status = "failed" end
                record.status = status
                if status == "clean" then
                    print(string.format("[GIT/WORLD/SERVED/MERGE] %s: %s", path, reply.take == "mine"
                        and "the world's version is what yours started from, sending yours"
                        or "merged the world's version into yours"))
                elseif status == "conflict" then
                    notice(commands, "CONFLICT", "Someone else changed " .. path
                        .. " too. Resolve the conflict markers in your copy and save.")
                    print("[GIT/WORLD/SERVED/MERGE] conflict in " .. path .. ": resolve the markers and save")
                else
                    notice(commands, "COULD NOT MERGE", path .. ": " .. tostring(reply.message))
                    print("[GIT/WORLD/SERVED/MERGE] could not merge " .. path .. ": " .. tostring(reply.message))
                end
                commands:entity(ask:id()):try_despawn()
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

-- A clean merge is on top of the held version: the path's edit says so, so its next send expects
-- that version instead of coming back stale. An edit stated after the answer gets it too.
app:add_systems(Update, {
    Query[{
        with = { "git/world/served/merge/result" },
        without = { "WorldMirror" },
    }],
    Query[{
        with = { Mut["core/library/edit"] },
        without = { "WorldMirror" },
    }],
}, function(records, edits)
    local clean = {}
    for _, row in ipairs(records:iter()) do
        local record = row:get("git/world/served/merge/result")
        if record.status == "clean" then clean[record.key] = record.hash end
    end
    for _, e in ipairs(edits:iter_mut()) do
        local edit = e:get("core/library/edit")
        local hash = clean[edit.path]
        if hash ~= nil and edit.on ~= hash then
            e:get_mut("core/library/edit").on = hash
        end
    end
end):in_set("git/world/served/merge")
    :run_if({
        Query[{
            ["or"] = {
                added = { "git/world/served/merge/result", "core/library/edit" },
                changed = { "git/world/served/merge/result" },
            },
            without = { "WorldMirror" },
        }],
    }, function(touched)
        return not touched:is_empty()
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
