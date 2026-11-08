-- git/world/served/status: the player's edits to this world's checkout, read from git and stated
-- as core's `core/library/edit`, one per changed file, which core uploads. Root runs git; this
-- world asks with a `vault/git/status` request and reads the answer. A sub-mod of git/world/served,
-- which adds and removes it.
--
-- git/world/served/status = {}
-- git/world/served/status/scan = {
--     asked_at = <this world's clock, in seconds, when the last request was asked>,
--     head = <the checkout's commit at the last scan>,
--     ops = {
--         [<path, asset relative>] = {
--             op = "write" | "create" | "delete",
--             mtime = <when the file was last written, as root read it; absent for a delete>,
--         },
--     },
-- }

local Time = require("bevy::time::Time")

-- A save in the player's editor changes nothing a query can see, so this asks on a timer, every
-- 2 s, and only while a carrier exists. One request is open at a time. Root answers only a world it
-- started, so a request unanswered after 10 s is closed and asked again.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "git/world/served/status" },
        without = { "WorldMirror" },
        optional = { Mut["git/world/served/status/scan"], "Children" },
    }],
    Query[{ with = { "vault/git/status", "Request" } }],
    Commands,
}, function(time, carriers, asks, commands)
    local now = time:elapsed_secs()
    for _, carrier in ipairs(carriers:iter_mut()) do
        local scan = carrier:get_mut("git/world/served/status/scan")
        local open = asks:iter_many(carrier:get("Children") or {})[1]
        if open == nil and (scan == nil or now - scan.asked_at >= 2) then
            if scan == nil then
                commands:entity(carrier:id()):insert({
                    ["git/world/served/status/scan"] = { asked_at = now, ops = {} },
                })
            else
                scan.asked_at = now
            end
            commands:spawn({ ["vault/git/status"] = {}, ["vault/git"] = {}, Request = {}, ChildOf = carrier:id() })
        elseif open ~= nil and (scan == nil or now - scan.asked_at > 10) then
            commands:entity(open:id()):despawn()
            print("[GIT/WORLD/SERVED/STATUS] root did not answer a status request in 10 s: asking again")
        end
    end
end):in_set("git/world/served/status")
    :run_if({
        Query[{
            with = { "git/world/served/status" },
            without = { "WorldMirror" },
        }],
    }, function(carriers)
        return not carriers:is_empty()
    end)
    -- In both-mode this process serves the world from the same checkout, so there is nothing to
    -- send. Only root's statement counts: any world can share a `core/process` of its own.
    :run_if({
        Query[{
            with = { "core/process" },
            optional = { "WorldMirror" },
        }],
    }, function(processes)
        for _, row in ipairs(processes:iter()) do
            local from = row:has("WorldMirror") and row:get("WorldMirror").world_id or world_id or 0
            if from == 0 and row:get("core/process").mode == "both" then return false end
        end
        return true
    end)
    -- Signed out, an edit can only be refused upstream, so nothing is asked until the player signs
    -- in. Root's identity carries `site_user_id` while they are.
    :run_if({
        Query[{
            with = { "core/player/identity" },
            optional = { "WorldMirror" },
        }],
    }, function(identities)
        for _, row in ipairs(identities:iter()) do
            local from = row:has("WorldMirror") and row:get("WorldMirror").world_id or world_id or 0
            if from == 0 and row:get("core/player/identity").site_user_id ~= nil then return true end
        end
        return false
    end)

-- Each scan restates the edits wholesale. A path git still reports moves its `seq` when its op or
-- its `mtime` changed, so a second save of a file that is still dirty goes up too.
app:add_systems(Update, {
    Query[{ with = { "vault/git/status/reply", "ChildOf" } }],
    Query[{
        with = { "git/world/served/status", Mut["git/world/served/status/scan"] },
        without = { "WorldMirror" },
        optional = { "Children" },
    }],
    Query[{ with = { Mut["core/library/edit"] } }],
    Commands,
}, function(replies, carriers, edits, commands)
    for _, row in ipairs(replies:iter()) do
        local carrier = carriers:get_mut(row:get("ChildOf"))
        if carrier then
            local reply = row:get("vault/git/status/reply")
            if reply.status == "ok" then
                local scan = carrier:get_mut("git/world/served/status/scan")
                local before = scan.ops or {}
                -- Git refuses to switch branches over a dirty file whose content differs, so a path
                -- that leaves the list while HEAD moved was committed or is the other branch's: no edit.
                local moved = scan.head ~= nil and reply.head ~= nil and scan.head ~= reply.head
                local ops = {}
                for _, entry in ipairs(reply.entries or {}) do
                    ops[(entry.path:gsub("^assets/", ""))] = { op = entry.op, mtime = entry.mtime }
                end
                local stated = {}
                for _, edit in ipairs(edits:iter_many_mut(carrier:get("Children") or {})) do
                    local fact = edit:get_mut("core/library/edit")
                    local path = fact.path
                    local now, was = ops[path], before[path]
                    if stated[path] then
                        commands:entity(edit:id()):despawn()
                    elseif now ~= nil then
                        stated[path] = true
                        if was == nil or was.op ~= now.op or was.mtime ~= now.mtime then
                            fact.seq = (fact.seq or 0) + 1
                            fact.deleted = now.op == "delete"
                            print("[GIT/WORLD/SERVED/STATUS] " .. tostring(now.op) .. ": " .. path)
                        end
                    elseif was ~= nil and not moved then
                        -- A revert leaves git's list and is still the person's change: the committed
                        -- version goes up once more, and the next scan drops it. A file git listed as
                        -- new is gone again.
                        stated[path] = true
                        fact.seq = (fact.seq or 0) + 1
                        fact.deleted = was.op == "create"
                        print("[GIT/WORLD/SERVED/STATUS] back to the committed version: " .. path)
                    else
                        commands:entity(edit:id()):despawn()
                        if moved then
                            print("[GIT/WORLD/SERVED/STATUS] no longer dirty after HEAD moved (not an edit): " .. path)
                        end
                    end
                end
                for path, now in pairs(ops) do
                    if not stated[path] then
                        -- Kept through a reload of this mod, so the edit's `seq` runs on; it goes
                        -- with the carrier.
                        commands:spawn({
                            ["core/library/edit"] = { path = path, seq = 1, deleted = now.op == "delete" },
                            ["core/net/sync"] = false,
                            ["core/script/owner"] = false,
                            ChildOf = carrier:id(),
                        })
                        print("[GIT/WORLD/SERVED/STATUS] " .. tostring(now.op) .. ": " .. path)
                    end
                end
                if moved then
                    print(string.format("[GIT/WORLD/SERVED/STATUS] HEAD moved %s -> %s: files it changed are not edits",
                        scan.head:sub(1, 7), reply.head:sub(1, 7)))
                end
                scan.head = reply.head or scan.head
                scan.ops = ops
            else
                print(string.format("[GIT/WORLD/SERVED/STATUS] root answered %s: %s", tostring(reply.status),
                    tostring(reply.message)))
            end
            commands:entity(row:id()):despawn()
        end
    end
end):in_set("git/world/served/status")
    -- A reply crosses from root, and an edge that crosses from another VM can be missed: a reply
    -- still waiting is looked at again twice a second.
    :run_if({
        Res[Time],
        Query[{ added = { "vault/git/status/reply" } }],
        Query[{ with = { "vault/git/status/reply" } }],
    }, function(time, arrived, waiting)
        local t = time:elapsed_secs()
        return not arrived:is_empty()
            or (not waiting:is_empty() and math.floor(t * 2) ~= math.floor((t - time:delta_secs()) * 2))
    end)

-- git/world/served/status taken off an entity that stays: its edits and its open request go with
-- it. A despawned carrier takes its children itself.
app:add_systems(Update, {
    Query[{
        removed = { "git/world/served/status" },
        optional = { "Children" },
    }],
    Query[{ any_of = { "core/library/edit", "vault/git/status" } }],
    Commands,
}, function(removed, children, commands)
    for _, e in ipairs(removed:iter()) do
        for _, child in ipairs(children:iter_many(e:get("Children") or {})) do
            commands:entity(child:id()):try_despawn()
        end
    end
end)

return {}
