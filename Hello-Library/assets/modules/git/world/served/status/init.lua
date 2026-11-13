-- git/world/served/status: the player's edits to this world's checkout, read from git and stated
-- as core's `core/library/edit`, one per changed file, which core uploads. Root runs git; this
-- world asks with a `vault/git/status` request and reads the answer. A sub-mod of git/world/served,
-- which adds and removes it.
--
-- It also tells core it is the provider of those facts, with `core/library/edit/provider { ref }`
-- on its carrier, so a file git does not list is not the player's edit: while the checkout is on
-- the commit the world states (`git/world/head.sha`), a file clean against it holds the world's own
-- version. On another commit it says nothing (core keeps its own guard), and while the checkout is
-- on another branch than the world's, or the player is signed out, it says `paused = true`:
-- nothing goes up and nothing lands.
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

--- The branch a scope names: its last `:` part (`github:owner/name:branch`).
local function scope_branch(scope)
    return tostring(scope or ""):match(":([^:]+)$")
end

--- What this mod tells core about the facts it states for the world `scope`: nil (nothing), or the
--- value of `core/library/edit/provider`.
local function provider_for(scope, branch, head, world_sha)
    local wanted = scope_branch(scope)
    if branch ~= nil and wanted ~= nil and branch ~= wanted then
        return { ref = scope, paused = true }
    end
    if head ~= nil and world_sha ~= nil and head == world_sha then
        return { ref = scope }
    end
    return nil
end

--- Puts `want` on the carrier as its provider marker, or takes it off, when it differs from `have`.
local function set_provider(commands, carrier, have, want)
    local same = (have == nil and want == nil) or (have ~= nil and want ~= nil and have.ref == want.ref
        and (have.paused == true) == (want.paused == true))
    if same then return end
    if want == nil then
        commands:entity(carrier):try_remove("core/library/edit/provider")
    else
        commands:entity(carrier):insert({ ["core/library/edit/provider"] = want })
    end
end

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
-- its `mtime` changed, so a second save of a file that is still dirty goes up too. A reply crosses
-- from root's VM, and a mirrored edge arrives as surely as a local one, so the reply's own edge is
-- all this runs on.
app:add_systems(Update, {
    Query[{ added = { "vault/git/status/reply" }, with = { "ChildOf" } }],
    Query[{
        with = { "git/world/served/status", Mut["git/world/served/status/scan"] },
        without = { "WorldMirror" },
        optional = { "Children" },
    }],
    Query[{ with = { Mut["core/library/edit"] } }],
    Query[{ with = { "core/world/status", "WorldShared" }, without = { "WorldMirror" } }],
    Query[{ with = { "git/world/head" } }],
    Query[{ with = { "git/world/served/status" }, optional = { "core/library/edit/provider" } }],
    Commands,
}, function(replies, carriers, edits, statuses, heads, markers, commands)
    local me = statuses:iter()[1]
    local scope = me and me:get("core/world/status").scope_key
    local head = heads:iter()[1]
    local world_sha = head and head:get("git/world/head").sha
    for _, row in ipairs(replies:iter()) do
        local carrier = carriers:get_mut(row:get("ChildOf"))
        if carrier then
            local reply = row:get("vault/git/status/reply")
            if reply.status == "ok" and scope ~= nil then
                local marked = markers:get(carrier:id())
                set_provider(commands, carrier:id(), marked and marked:get("core/library/edit/provider"),
                    provider_for(scope, reply.branch, reply.head, world_sha))
            end
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
                            fact.mtime = now.mtime
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
                            ["core/library/edit"] = { path = path, seq = 1, deleted = now.op == "delete", mtime = now.mtime },
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

-- An edit this world refused stays in the player's copy only, and nothing else says so. Core marks
-- the edit `core/library/edit/refused` for each refusal that is not stale; a stale one is merged
-- instead and marks nothing.
app:add_systems(Update, {
    Query[{ added = { "core/library/edit/refused" }, with = { "core/library/edit", "ChildOf" } }],
    Query[{ with = { "git/world/served/status" }, without = { "WorldMirror" } }],
    Commands,
}, function(refused, carriers, commands)
    for _, row in ipairs(refused:iter()) do
        if carriers:get(row:get("ChildOf")) then
            local path = row:get("core/library/edit").path
            print("[GIT/WORLD/SERVED/STATUS] this world refused your edit of " .. tostring(path))
            commands:spawn({
                ["git/merge/notice"] = {
                    title = "REFUSED",
                    text = "This world refused your edit of " .. tostring(path) .. ". It stays in your copy only.",
                },
                notification = { timeout = 20 },
                ["core/script/owner"] = false,
            })
        end
    end
end):in_set("git/world/served/status")
    :run_if({ Query[{ added = { "core/library/edit/refused" } }] }, function(refused)
        return not refused:is_empty()
    end)

-- Signed out, this mod asks nothing, and an edit could only be refused: the tree is paused (nothing
-- goes up, nothing lands) until a scan signed in says otherwise. Root's identity only: any world can
-- share a `core/player/identity` of its own.
app:add_systems(Update, {
    Query[{ changed = { "core/player/identity" }, optional = { "WorldMirror" } }],
    Query[{
        with = { "git/world/served/status" },
        without = { "WorldMirror" },
        optional = { "core/library/edit/provider" },
    }],
    Query[{ with = { "core/world/status", "WorldShared" }, without = { "WorldMirror" } }],
    Commands,
}, function(identities, carriers, statuses, commands)
    local signed_out = false
    for _, row in ipairs(identities:iter()) do
        local from = row:has("WorldMirror") and row:get("WorldMirror").world_id or world_id or 0
        if from == 0 then signed_out = row:get("core/player/identity").site_user_id == nil end
    end
    local me = statuses:iter()[1]
    local scope = me and me:get("core/world/status").scope_key
    if not signed_out or scope == nil then return end
    for _, carrier in ipairs(carriers:iter()) do
        local have = carrier:has("core/library/edit/provider") and carrier:get("core/library/edit/provider") or nil
        set_provider(commands, carrier:id(), have, { ref = scope, paused = true })
    end
end):in_set("git/world/served/status")
    :run_if({ Query[{ changed = { "core/player/identity" } }] }, function(changed)
        return not changed:is_empty()
    end)

-- git/world/served/status taken off an entity that stays: its edits and its open request go with
-- it, and its provider marker. A despawned carrier takes its children itself.
app:add_systems(Update, {
    Query[{
        removed = { "git/world/served/status" },
        optional = { "Children" },
    }],
    Query[{ any_of = { "core/library/edit", "vault/git/status" } }],
    Commands,
}, function(removed, children, commands)
    for _, e in ipairs(removed:iter()) do
        commands:entity(e:id()):try_remove("core/library/edit/provider")
        for _, child in ipairs(children:iter_many(e:get("Children") or {})) do
            commands:entity(child:id()):try_despawn()
        end
    end
end)

return {}
