-- git/world/head, the client's half: how this player's checkout stands against the commit the
-- world states, asked of root, and said when they should pull. Only in a world whose tree the
-- player edits by hand: any other world is not theirs to be behind.
--
-- When the player's upstream holds commits the world's commit lacks (work pushed while the world
-- ran), this half asks the world to pull, with git/world/head/pull. The pull moves the world's
-- commit, which asks again.

local Time = require("bevy::time::Time")

-- One request per commit the world states. A request for a commit the world has left is closed,
-- which stops its git process at root.
app:add_systems(Update, {
    Query[{
        ["or"] = { added = { "git/world/head" }, changed = { "git/world/head" } },
        optional = { "Children" },
    }],
    Query[{ with = { "vault/git/head", "vault/git", "Request" } }],
    Commands,
}, function(heads, asks, commands)
    for _, head in ipairs(heads:iter()) do
        local sha = head:get("git/world/head").sha
        local asked = false
        for _, ask in ipairs(asks:iter_many(head:get("Children") or {})) do
            if ask:get("vault/git").sha == sha then
                asked = true
            else
                commands:entity(ask:id()):despawn()
            end
        end
        if sha ~= nil and not asked then
            commands:spawn({ ["vault/git/head"] = {}, ["vault/git"] = { sha = sha }, Request = {}, ChildOf = head:id() })
        end
    end
end):in_set("git/world/head/compare")
    -- A false condition keeps the edges, so a checkout that arrives after the world's commit
    -- still asks.
    :run_if({ Query[{ with = { "core/library" }, without = { "WorldMirror" } }] }, function(libraries)
        for _, lib in ipairs(libraries:iter()) do
            if lib:get("core/library").edits then return true end
        end
        return false
    end)

app:add_systems(Update, {
    Query[{ with = { "vault/git/head/reply", "ChildOf" } }],
    Query[{ with = { "git/world/head" } }],
    Commands,
}, function(replies, heads, commands)
    for _, row in ipairs(replies:iter()) do
        local head = heads:get(row:get("ChildOf"))
        if head then
            local reply = row:get("vault/git/head/reply")
            if reply.sha == head:get("git/world/head").sha then
                if reply.relation == "behind" then
                    commands:spawn({
                        ["git/merge/notice"] = {
                            title = "BEHIND",
                            text = string.format("Your checkout is %s commit%s behind this world: pull.",
                                tostring(reply.count or "some"), reply.count == 1 and "" or "s"),
                        },
                        notification = { timeout = 20 },
                        ["core/script/owner"] = false,
                    })
                elseif reply.relation == "unknown" then
                    commands:spawn({
                        ["git/merge/notice"] = {
                            title = "BEHIND",
                            text = "This world is on a commit you have not fetched: pull.",
                        },
                        notification = { timeout = 20 },
                        ["core/script/owner"] = false,
                    })
                end
                if reply.pushed ~= nil then
                    commands:spawn({ ["git/world/head/pull"] = { sha = reply.sha }, ["core/script/owner"] = false })
                    commands:spawn({
                        ["git/merge/notice"] = {
                            title = "PULLING",
                            text = string.format("This world is %d commit%s behind what you pushed: asked it to pull.",
                                reply.pushed, reply.pushed == 1 and "" or "s"),
                        },
                        notification = { timeout = 20 },
                        ["core/script/owner"] = false,
                    })
                end
                print(string.format("[GIT/WORLD/HEAD] your checkout against the world's %s: %s%s%s%s",
                    tostring(reply.sha):sub(1, 7), tostring(reply.relation),
                    reply.count ~= nil and (" (" .. tostring(reply.count) .. ")") or "",
                    reply.pushed ~= nil and ("; the world lacks " .. tostring(reply.pushed) .. " pushed, asked it to pull") or "",
                    reply.message ~= nil and (": " .. tostring(reply.message)) or ""))
            end
            commands:entity(row:id()):despawn()
        end
    end
end):in_set("git/world/head/compare")
    -- A reply crosses from root, and an edge that crosses from another VM can be missed: a reply
    -- still waiting is looked at again twice a second.
    :run_if({
        Res[Time],
        Query[{ added = { "vault/git/head/reply" } }],
        Query[{ with = { "vault/git/head/reply" } }],
    }, function(time, arrived, waiting)
        local t = time:elapsed_secs()
        return not arrived:is_empty()
            or (not waiting:is_empty() and math.floor(t * 2) ~= math.floor((t - time:delta_secs()) * 2))
    end)

return {}
