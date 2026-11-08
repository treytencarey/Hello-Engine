-- checkout/github: a branch of a GitHub repository brought onto disk, for the Gateway world to host.
-- Root clones it and chooses its folder; this world runs no git and holds no key.
--
-- checkout/github = {
--     repo = <owner/name>,
--     ref = <a branch>,
--     path = <a folder the asker would like; ignored, as root chooses the folder>,
-- }
-- checkout/answer = {
--     status = "ready" | "failed",
--     path = <the checkout as an asset root, when ready>,
--     reason = <why, when failed: root's reason, or why root refused>,
--     detail = <the deploy key's public half, with "needs-deploy-key">,
-- }

local Time = require("bevy::time::Time")

app:add_systems(Update, {
    Query[{
        added = { "checkout/github" },
        without = { "checkout/answer", "WorldMirror" },
    }],
    Commands,
}, function(requests, commands)
    for _, request in ipairs(requests:iter()) do
        local want = request:get("checkout/github")
        commands:spawn({
            ["vault/git/checkout"] = {},
            ["vault/git"] = { repo = want.repo, ref = want.ref },
            Request = {},
            ChildOf = request:id(),
        })
    end
end):in_set("checkout/github")

app:add_systems(Update, {
    Query[{
        with = { "vault/git/checkout/reply", "ChildOf" },
        without = { "RequestFrom", "WorldMirror" },
    }],
    Query[{
        with = { "checkout/github" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(replies, requests, commands)
    for _, row in ipairs(replies:iter()) do
        local request = requests:get(row:get("ChildOf"))
        if request then
            local reply = row:get("vault/git/checkout/reply")
            local want = request:get("checkout/github")
            if reply.status == "ready" then
                commands:entity(request:id()):insert({ ["checkout/answer"] = { status = "ready", path = reply.path } })
            else
                commands:entity(request:id()):insert({
                    ["checkout/answer"] = { status = "failed", reason = reply.reason, detail = reply.key },
                })
            end
            print(string.format("[CHECKOUT/GITHUB] %s:%s %s %s", tostring(want.repo), tostring(want.ref),
                tostring(reply.status), tostring(reply.reason or reply.path)))
            commands:entity(row:id()):despawn()
        end
    end
end):in_set("checkout/github")
    -- A reply crosses from root, and an edge that crosses from another VM can be missed: a reply
    -- still waiting is looked at again twice a second.
    :run_if({
        Res[Time],
        Query[{ added = { "vault/git/checkout/reply" } }],
        Query[{ with = { "vault/git/checkout/reply" } }],
    }, function(time, arrived, waiting)
        local t = time:elapsed_secs()
        return not arrived:is_empty()
            or (not waiting:is_empty() and math.floor(t * 2) ~= math.floor((t - time:delta_secs()) * 2))
    end)

app:add_systems(Update, {
    Query[{
        removed = { "checkout/github" },
        without = { "WorldMirror" },
        optional = { "Children" },
    }],
    Query[{ with = { "vault/git/checkout", "Request" } }],
    Commands,
}, function(gone, asks, commands)
    for _, request in ipairs(gone:iter()) do
        for _, ask in ipairs(asks:iter_many(request:get("Children") or {})) do
            commands:entity(ask:id()):despawn()
        end
        commands:entity(request:id()):try_remove("checkout/answer")
    end
end):in_set("checkout/github")

return {}
