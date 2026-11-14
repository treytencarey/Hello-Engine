-- git/ignore: whether a path of a world's tree is one git ignores, so core never serves, lists or
-- sends it. It answers core's `core/library/filter/ask` by asking root's git
-- (`vault/git/check_ignore`), which reads every rule itself: nested `.gitignore` files, `!`, the
-- global excludes, and paths that don't exist yet.
--
-- git/ignore = {}   on the carrier, beside the core/library/filter base it brings
--
-- An ask's paths go to root in requests of at most CHUNK paths, CHUNK_CHARS in all, each a child
-- of the ask, so they go with it. Once every request is answered, the ask is answered
-- `core/library/filter/ask/reply { out }`: the paths git ignores, or, when any request was
-- refused or failed, every path of the ask, so nothing goes on a question git didn't answer.

local CHUNK = 100
local CHUNK_CHARS = 12000

-- An ask under a carrier: its paths go to root. An ask can come before the carrier's base, or
-- before this mod has loaded, so the carrier's edges (this mod's own component re-fires once it
-- loads) catch up on its asks.
app:add_systems(Update, {
    Query[{ added = { "core/library/filter/ask" }, with = { "ChildOf" }, without = { "core/library/filter/ask/reply" } }],
    Query[{ with = { "git/ignore", "core/library/filter" }, without = { "WorldMirror" } }],
    Query[{ ["or"] = { added = { "git/ignore", "core/library/filter" } }, with = { "git/ignore", "core/library/filter" },
        without = { "WorldMirror" }, optional = { "Children" } }],
    Query[{ with = { "core/library/filter/ask", "ChildOf" }, without = { "core/library/filter/ask/reply" }, optional = { "Children" } }],
    Query[{ with = { "vault/git/check_ignore", "Request" } }],
    Commands,
}, function(fresh, carriers, arrived, pending, requests, commands)
    local asks, taken = {}, {}
    local function take(ask)
        if taken[ask:id()] then return end
        taken[ask:id()] = true
        asks[#asks + 1] = ask
    end
    for _, ask in ipairs(fresh:iter()) do take(ask) end
    for _, carrier in ipairs(arrived:iter()) do
        for _, ask in ipairs(pending:iter_many(carrier:get("Children") or {})) do
            if #requests:iter_many(ask:get("Children") or {}) == 0 then take(ask) end
        end
    end
    for _, ask in ipairs(asks) do
        if carriers:contains(ask:get("ChildOf")) then
            local chunk, chars = {}, 0
            local function send()
                if #chunk == 0 then return end
                commands:spawn({ ["vault/git/check_ignore"] = { paths = chunk }, ["vault/git"] = {}, Request = {},
                    ChildOf = ask:id(), ["core/net/sync"] = false, ["core/script/owner"] = false })
                chunk, chars = {}, 0
            end
            local paths = ask:get("core/library/filter/ask").paths or {}
            for _, p in ipairs(paths) do
                p = tostring(p)
                if #chunk >= CHUNK or chars + #p + 1 > CHUNK_CHARS then send() end
                chunk[#chunk + 1] = p
                chars = chars + #p + 1
            end
            send()
            if #paths == 0 then commands:entity(ask:id()):insert({ ["core/library/filter/ask/reply"] = { out = {} } }) end
        end
    end
end):in_set("git/ignore"):run_if({
    Query[{ ["or"] = { added = { "core/library/filter/ask", "core/library/filter", "git/ignore" } } }],
}, function(touched)
    return not touched:is_empty()
end)

-- Root's answers: once every request under an ask is in, the ask's.
app:add_systems(Update, {
    Query[{ added = { "vault/git/check_ignore/reply" }, with = { "ChildOf" } }],
    Query[{ with = { "core/library/filter/ask" }, without = { "core/library/filter/ask/reply" }, optional = { "Children" } }],
    Query[{ with = { "vault/git/check_ignore", "Request" }, optional = { "vault/git/check_ignore/reply" } }],
    Commands,
}, function(replies, asks, requests, commands)
    local seen = {}
    for _, row in ipairs(replies:iter()) do
        local ask = asks:get(row:get("ChildOf"))
        if ask and not seen[ask:id()] then
            seen[ask:id()] = true
            local out, done, failed = {}, true, nil
            for _, req in ipairs(requests:iter_many(ask:get("Children") or {})) do
                local reply = req:has("vault/git/check_ignore/reply") and req:get("vault/git/check_ignore/reply")
                if not reply then
                    done = false
                elseif reply.status ~= "ok" then
                    failed = reply.message or reply.status
                else
                    for _, p in ipairs(reply.ignored or {}) do out[#out + 1] = p end
                end
            end
            if done then
                if failed then
                    print("[GIT/IGNORE] root could not say what git ignores (" .. tostring(failed) .. "): every path of the ask is out")
                    out = {}
                    for _, p in ipairs(ask:get("core/library/filter/ask").paths or {}) do out[#out + 1] = p end
                end
                commands:entity(ask:id()):insert({ ["core/library/filter/ask/reply"] = { out = out } })
            end
        end
    end
end):in_set("git/ignore"):run_if({ Query[{ added = { "vault/git/check_ignore/reply" } }] }, function(replies)
    return not replies:is_empty()
end)

return { base = "core/library/filter" }
