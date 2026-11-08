-- git/world/head, the server's half: the world states the commit its tree is on, to its players,
-- and answers a player's ask to pull. Root reads the commit and pulls; this world holds no git.
--
-- git/world/head = {
--     sha = <the commit this world's tree is on>,
-- }

local Time = require("bevy::time::Time")

-- Root answers a status request with the checkout's commit (`head`).
app:add_systems(Update, {
    Query[{
        added = { "git/world/head" },
        without = { "WorldMirror" },
        optional = { "Children" },
    }],
    Query[{ with = { "vault/git/status", "Request" } }],
    Commands,
}, function(heads, asks, commands)
    for _, head in ipairs(heads:iter()) do
        for _, ask in ipairs(asks:iter_many(head:get("Children") or {})) do
            commands:entity(ask:id()):despawn()
        end
        commands:spawn({ ["vault/git/status"] = {}, ["vault/git"] = {}, Request = {}, ChildOf = head:id() })
    end
end):in_set("git/world/head/state")

-- A status reply names the checkout's commit as `head`; a pull reply names the commit the pull
-- left the checkout on as `sha`.
app:add_systems(Update, {
    Query[{ with = { "vault/git/status/reply", "ChildOf" } }],
    Query[{ with = { "vault/git/pull/reply", "ChildOf" } }],
    Query[{
        with = { Mut["git/world/head"] },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(statuses, pulls, heads, commands)
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
    -- A reply crosses from root, and an edge that crosses from another VM can be missed: a reply
    -- still waiting is looked at again twice a second.
    :run_if({
        Res[Time],
        Query[{ ["or"] = { added = { "vault/git/status/reply", "vault/git/pull/reply" } } }],
        Query[{ any_of = { "vault/git/status/reply", "vault/git/pull/reply" } }],
    }, function(time, arrived, waiting)
        local t = time:elapsed_secs()
        return not arrived:is_empty()
            or (not waiting:is_empty() and math.floor(t * 2) ~= math.floor((t - time:delta_secs()) * 2))
    end)

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

return { ["core/net/sync"] = { authority = "server" } }
