-- git/merge: the world's version of a file the player edited, merged into their checkout. Core
-- holds what could not land (`core/library/upstream.held[path]`), and this mod asks root to merge
-- it with `vault/git/merge`, `apply = true`. Root writes the result into the checkout, and core's
-- watcher picks it up. After a clean merge the path's `core/library/edit` names the held version
-- (`on`), so the save that follows expects it and lands. A conflict leaves git's markers in the
-- player's file, and a notice.
--
-- git/merge = {}
--
-- git/merge/job = {
--     asked_at = <seconds since the world started, when the request was sent>,
-- }
-- On each request this mod sends root, a child of the carrier.
--
-- git/merge/result = {
--     key = <the file, asset relative, as `held` names it>,
--     hash = <the held version that was merged>,
--     status = "clean" | "conflict" | "failed",
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

-- What is held asks a merge, once per held version. A request or a record for a version no
-- longer held goes, so a file held again at a new version is merged again.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "git/merge" },
        without = { "WorldMirror" },
        optional = { "Children" },
    }],
    Query[{
        with = { "core/library", "core/library/upstream" },
        without = { "WorldMirror" },
    }],
    Query[{
        with = { "vault/git/merge", "vault/git", "git/merge/job" },
        without = { "RequestFrom" },
    }],
    Query[{ with = { "git/merge/result" } }],
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
        for _, ask in ipairs(asks:iter_many(children)) do
            local values = ask:get("vault/git")
            local path = tostring(values.path):match("^assets/(.+)$")
            if path ~= nil and held[path] == values.hash and not known[path] then
                known[path] = true
            else
                commands:entity(ask:id()):try_despawn()
            end
        end
        for _, row in ipairs(records:iter_many(children)) do
            local record = row:get("git/merge/result")
            if held[record.key] == record.hash then
                known[record.key] = true
            else
                commands:entity(row:id()):despawn()
            end
        end
        for path, hash in pairs(held) do
            if not known[path] then
                commands:spawn({
                    ["vault/git/merge"] = {},
                    ["vault/git"] = { path = "assets/" .. path, hash = hash, apply = true },
                    Request = {},
                    ["git/merge/job"] = { asked_at = time:elapsed_secs() },
                    ChildOf = carrier:id(),
                })
            end
        end
    end
end):in_set("git/merge")
    :run_if({
        Query[{
            ["or"] = {
                added = { "git/merge", "core/library/upstream" },
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
        with = { "git/merge" },
        without = { "WorldMirror" },
        optional = { "Children" },
    }],
    Query[{
        with = { "vault/git/merge", "vault/git", "git/merge/job" },
        without = { "RequestFrom" },
        optional = { "vault/git/merge/reply" },
    }],
    Query[{ with = { "git/merge/result" } }],
    Commands,
}, function(time, carriers, asks, records, commands)
    local now = time:elapsed_secs()
    for _, carrier in ipairs(carriers:iter()) do
        local children = carrier:get("Children") or {}
        for _, ask in ipairs(asks:iter_many(children)) do
            local values = ask:get("vault/git")
            local path = tostring(values.path):match("^assets/(.+)$")
            local job = ask:get("git/merge/job")
            local reply = ask:has("vault/git/merge/reply") and ask:get("vault/git/merge/reply") or nil
            if reply == nil and now - job.asked_at >= 30 then
                reply = { status = "failed", message = "git did not answer" }
            end
            if path ~= nil and reply ~= nil then
                local status = reply.status
                if status == "refused" then status = "failed" end
                local record = { key = path, hash = values.hash, status = status }
                local kept = nil
                for _, row in ipairs(records:iter_many(children)) do
                    if row:get("git/merge/result").key == path then kept = row end
                end
                if kept then
                    commands:entity(kept:id()):insert({ ["git/merge/result"] = record })
                else
                    commands:spawn({ ["git/merge/result"] = record, ChildOf = carrier:id() })
                end
                if status == "clean" then
                    print(string.format("[GIT/MERGE] %s: %s", path, reply.take == "mine"
                        and "the world's version is what yours started from, sending yours"
                        or "merged the world's version into yours"))
                elseif status == "conflict" then
                    notice(commands, "CONFLICT", "Someone else changed " .. path
                        .. " too. Resolve the conflict markers in your copy and save.")
                    print("[GIT/MERGE] conflict in " .. path .. ": resolve the markers and save")
                else
                    notice(commands, "COULD NOT MERGE", path .. ": " .. tostring(reply.message))
                    print("[GIT/MERGE] could not merge " .. path .. ": " .. tostring(reply.message))
                end
                commands:entity(ask:id()):try_despawn()
            end
        end
    end
end):in_set("git/merge")
    -- A reply crosses from root, and an edge that crosses from another VM can be missed: a
    -- request still open is looked at again twice a second, which also runs its timeout.
    :run_if({
        Res[Time],
        Query[{ added = { "vault/git/merge/reply" } }],
        Query[{
            with = { "git/merge/job" },
            without = { "RequestFrom" },
        }],
    }, function(time, arrived, open)
        local t = time:elapsed_secs()
        return not arrived:is_empty()
            or (not open:is_empty() and math.floor(t * 2) ~= math.floor((t - time:delta_secs()) * 2))
    end)

-- A clean merge is on top of the held version: the path's edit says so, so its next send expects
-- that version instead of coming back stale. An edit stated after the answer gets it too.
app:add_systems(Update, {
    Query[{
        with = { "git/merge/result" },
        without = { "WorldMirror" },
    }],
    Query[{
        with = { Mut["core/library/edit"] },
        without = { "WorldMirror" },
    }],
}, function(records, edits)
    local clean = {}
    for _, row in ipairs(records:iter()) do
        local record = row:get("git/merge/result")
        if record.status == "clean" then clean[record.key] = record.hash end
    end
    for _, e in ipairs(edits:iter_mut()) do
        local edit = e:get("core/library/edit")
        local hash = clean[edit.path]
        if hash ~= nil and edit.on ~= hash then
            e:get_mut("core/library/edit").on = hash
        end
    end
end):in_set("git/merge")
    :run_if({
        Query[{
            ["or"] = {
                added = { "git/merge/result", "core/library/edit" },
                changed = { "git/merge/result" },
            },
            without = { "WorldMirror" },
        }],
    }, function(touched)
        return not touched:is_empty()
    end)

return {}
