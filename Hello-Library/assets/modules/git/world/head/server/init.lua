-- git/world/head, the server's half: the world states the commit its tree is on, to its players,
-- and answers a player's ask to pull. Root reads the commit and pulls; this world holds no git.
--
-- git/world/head = {
--     sha = <the commit this world's tree is on>,
-- }
--
-- git/world/head/dirty = { [<path, asset relative>] = "write" | "create" | "delete" }: the tree's
-- live edits, the files that differ from its commit, on each writer's own player entity and synced to
-- that player only, while their proof is "writer" (git/collaborators/authorize). Anonymous and
-- unauthorized players get none of it. It names `server/` halves too: a writer may change them.

--- `a` and `b` hold the same paths and ops.
local function same(a, b)
    a, b = a or {}, b or {}
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- Root answers a status request with the checkout's commit (`head`) and its live edits. Asked when
-- the head arrives, when the served tree changes (its `core/library/files` rows, which the asset
-- server restates on every applied edit and watched change), and when a proof changes, so a new
-- writer is told and one no longer a writer stops being told. One request is open at a time: a
-- booting tree restates its files many frames running, and replacing the open request each time
-- would never let root answer one. The head's own arrival replaces an open request.
app:add_systems(Update, {
    Query[{
        with = { "git/world/head" },
        without = { "WorldMirror" },
        optional = { "Children" },
    }],
    Query[{ added = { "git/world/head" }, without = { "WorldMirror" } }],
    Query[{ with = { "vault/git/status", "Request" } }],
    Commands,
}, function(heads, arrived, asks, commands)
    local new = {}
    for _, h in ipairs(arrived:iter()) do new[h:id()] = true end
    for _, head in ipairs(heads:iter()) do
        local open = asks:iter_many(head:get("Children") or {})
        if new[head:id()] then
            for _, ask in ipairs(open) do commands:entity(ask:id()):despawn() end
        end
        if new[head:id()] or open[1] == nil then
            commands:spawn({ ["vault/git/status"] = {}, ["vault/git"] = {}, Request = {}, ChildOf = head:id() })
        end
    end
end):in_set("git/world/head/state")
    :run_if({
        Query[{
            ["or"] = {
                added = { "git/world/head" },
                changed = { "core/library/files", "git/collaborators/authorize/proof" },
                removed = { "git/collaborators/authorize/proof" },
            },
            without = { "WorldMirror" },
        }],
    }, function(touched)
        return not touched:is_empty()
    end)

-- A status reply names the checkout's commit as `head`; a pull reply names the commit the pull
-- left the checkout on as `sha`. A reply crosses from root's VM, and a mirrored edge arrives as
-- surely as a local one, so the reply's own edge is all this runs on.
app:add_systems(Update, {
    Query[{ added = { "vault/git/status/reply" }, with = { "ChildOf" } }],
    Query[{ added = { "vault/git/pull/reply" }, with = { "ChildOf" } }],
    Query[{
        with = { Mut["git/world/head"] },
        without = { "WorldMirror" },
    }],
    Query[{
        with = { "core/net/connection" },
        without = { "WorldMirror" },
        optional = { "git/collaborators/authorize/proof" },
    }],
    Query[{
        with = { "player", "core/net/sync" },
        without = { "WorldMirror" },
        optional = { "git/world/head/dirty" },
    }],
    Commands,
}, function(statuses, pulls, heads, connections, players, commands)
    local replies = {}
    for _, r in ipairs(statuses:iter()) do
        replies[#replies + 1] = { row = r, reply = r:get("vault/git/status/reply") }
    end
    for _, r in ipairs(pulls:iter()) do
        replies[#replies + 1] = { row = r, reply = r:get("vault/git/pull/reply") }
    end
    for _, answer in ipairs(replies) do
        local head = heads:get_mut(answer.row:get("ChildOf"))
        if head then
            local reply = answer.reply
            local sha = reply.head or reply.sha
            local stated = head:get_mut("git/world/head")
            if reply.status == "ok" and reply.entries ~= nil then
                local dirty = {}
                for _, entry in ipairs(reply.entries) do
                    dirty[(tostring(entry.path):gsub("^assets/", ""))] = entry.op
                end
                -- Writers only, by their connection's proof.
                local writers = {}
                for _, c in ipairs(connections:iter()) do
                    local proof = c:has("git/collaborators/authorize/proof") and c:get("git/collaborators/authorize/proof")
                    if proof and proof.state == "writer" then writers[c:get("core/net/connection").client_id] = true end
                end
                for _, p in ipairs(players:iter()) do
                    local writer = writers[p:get("player").client_id]
                    local have = p:has("git/world/head/dirty") and p:get("git/world/head/dirty") or nil
                    if writer and (have == nil or not same(have, dirty)) then
                        commands:entity(p:id()):insert({ ["git/world/head/dirty"] = dirty })
                        if have == nil and type(p:get("core/net/sync")) == "table" then
                            commands:entity(p:id()):entry("core/net/sync"):and_modify(function(sync)
                                sync["git/world/head/dirty"] = { authority = "server", target = "owner" }
                            end)
                        end
                    elseif not writer and have ~= nil then
                        commands:entity(p:id()):remove("git/world/head/dirty")
                        if type(p:get("core/net/sync")) == "table" then
                            commands:entity(p:id()):entry("core/net/sync"):and_modify(function(sync)
                                sync["git/world/head/dirty"] = nil
                            end)
                        end
                    end
                end
            end
            if reply.status == "ok" or reply.status == "updated" or reply.status == "current" then
                if sha ~= nil and stated.sha ~= sha then
                    stated.sha = sha
                    print(string.format("[GIT/WORLD/HEAD] this world is on %s", sha:sub(1, 7)))
                end
            else
                print(string.format("[GIT/WORLD/HEAD] root answered %s: %s", tostring(reply.status),
                    tostring(reply.message)))
            end
            commands:entity(answer.row:id()):despawn()
        end
    end
end):in_set("git/world/head/state")

-- A player whose upstream holds commits this world lacks asks it to pull. Nothing in the ask is
-- trusted but its existence: root pulls this world's own branch into its own tree, as a restart
-- would. `sha` only drops an ask about a commit this world has since left.
app:add_systems(Update, {
    Query[{ added = { "core/net/predict" } }],
    Query[{
        with = { "git/world/head" },
        without = { "WorldMirror" },
        optional = { "Children" },
    }],
    Query[{ with = { "vault/git/pull", "Request" } }],
    Commands,
}, function(asks, heads, pulling, commands)
    for _, ask in ipairs(asks:iter()) do
        local predict = ask:get("core/net/predict")
        local asked = predict.requested and predict.requested["git/world/head/pull"]
        if asked then
            commands:entity(ask:id()):despawn()
            local head = heads:iter()[1]
            local now = head and head:get("git/world/head").sha
            if now == nil or asked.sha ~= now then
                print(string.format("[GIT/WORLD/HEAD] client %s asked about %s; this world is on %s: ignored",
                    tostring(predict.client_id), tostring(asked.sha):sub(1, 7), tostring(now):sub(1, 7)))
            elseif pulling:iter_many(head:get("Children") or {})[1] then
                print(string.format("[GIT/WORLD/HEAD] client %s asked for a pull; one is under way",
                    tostring(predict.client_id)))
            else
                commands:spawn({
                    ["vault/git/pull"] = {}, ["vault/git"] = { sha = now }, Request = {}, ChildOf = head:id(),
                })
                print(string.format("[GIT/WORLD/HEAD] client %s pushed past %s: asked root to pull",
                    tostring(predict.client_id), now:sub(1, 7)))
            end
        end
    end
end):in_set("git/world/head/pulling")

-- The head gone: no player is told its live edits any more. The dirty lists this mod put on players
-- go, and their sync entries. (A player despawning takes its own.)
app:add_systems(Update, {
    Query[{ removed = { "git/world/head" } }],
    Query[{ with = { "player", "core/net/sync" }, without = { "WorldMirror" }, optional = { "git/world/head/dirty" } }],
    Commands,
}, function(removed, players, commands)
    if removed:is_empty() then return end
    -- The registry may have taken the lists off already, as the mod's last carrier left: the sync
    -- entries are this mod's to take too.
    for _, p in ipairs(players:iter()) do
        if p:has("git/world/head/dirty") then commands:entity(p:id()):remove("git/world/head/dirty") end
        local sync = p:get("core/net/sync")
        if type(sync) == "table" and sync["git/world/head/dirty"] ~= nil then
            commands:entity(p:id()):entry("core/net/sync"):and_modify(function(sync)
                sync["git/world/head/dirty"] = nil
            end)
        end
    end
end):in_set("git/world/head/state")

return { ["core/net/sync"] = { authority = "server" } }
