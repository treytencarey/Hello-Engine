-- git/collaborators/authorize, the server's half: the write policy of a world served from git. A
-- player may change this world's files once their root has pushed the ref their join's nonce names
-- to the world's repository, and this world's root finds it there. Core holds each write until this
-- answers it. The proof is kept on the client's `core/net/connection`, where core/player/attest
-- writes who it is, so it lasts as long as the connection, whichever player that client controls.
--
-- git/collaborators/authorize = {
--     proof_wait = <seconds after the first ask that "absent" may still turn into "writer"; 90>,
-- }
-- git/collaborators/authorize/proof = {
--     user = <the attested user the proof is for>,
--     nonce = <the attestation's nonce the check names>,
--     state = "checking" | "writer" | "absent" | "denied",
--     why = <root's message, when denied>,
--     asked_at = <this world's clock, in seconds, at the first ask for this nonce>,
--     next_at = <when root is asked again, while "absent" may still turn into "writer">,
-- }
--
-- "absent" is not a verdict while the player's push may still be landing: core holds a write while
-- its policy decides (up to its ceiling), so the write waits and root is asked again, each wait as
-- long as the time since the first ask (about 1, 2, 4, 8, 16, 32 s), until `proof_wait` after
-- the first ask (90 s: a push measured live took about 30 s while a large upload shared the uplink). Then "absent" is final for that nonce, and a write still waiting is denied. A later
-- write asks again from its own arrival. "denied" or "failed" from root is final at once.

local Time = require("bevy::time::Time")

--- The world's `proof_wait`, from the carrier of this mod.
local function proof_wait(carriers)
    local carrier = carriers:iter()[1]
    return carrier and carrier:get("git/collaborators/authorize").proof_wait or 90
end

local function ask(commands, connection, nonce)
    commands:spawn({
        ["vault/git/proof"] = {},
        ["vault/git"] = { nonce = nonce },
        Request = {},
        ChildOf = connection:id(),
        ["core/script/owner"] = false,
    })
end

app:add_systems(First, {
    Query[{
        added = { "git/collaborators/authorize" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(carriers, commands)
    for _, carrier in ipairs(carriers:iter()) do
        commands:entity(carrier:id()):insert_if_new({ ["core/asset/authorizer"] = {} })
    end
end):in_set("git/collaborators/authorize")

app:add_systems(First, {
    Query[{ removed = { "git/collaborators/authorize" } }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        commands:entity(e:id()):try_remove("core/asset/authorizer")
    end
end)

-- Root's answer settles the proof and every write held for it; a write with no proof yet asks root
-- once for its connection and waits. A write waits while any connection of its author may still
-- prove them a writer, and is denied once none can.
app:add_systems(First, {
    Res[Time],
    Query[{
        with = { "vault/git/proof/reply", "vault/git", "ChildOf" },
        without = { "RequestFrom", "WorldMirror" },
    }],
    Query[{
        with = { "core/asset/write" },
        without = { "core/asset/write/reply", "RequestFrom", "WorldMirror" },
    }],
    Query[{ added = { "core/asset/write" }, without = { "RequestFrom", "WorldMirror" } }],
    Query[{
        with = { "core/net/connection", "core/player/attest" },
        without = { "WorldMirror" },
        optional = { Mut["git/collaborators/authorize/proof"] },
    }],
    Query[{ with = { "git/collaborators/authorize" }, without = { "WorldMirror" } }],
    Commands,
}, function(time, replies, writes, arrived, connections, carriers, commands)
    local now = time:elapsed_secs()
    local wait = proof_wait(carriers)
    for _, row in ipairs(replies:iter()) do
        local connection = connections:get_mut(row:get("ChildOf"))
        if connection then
            commands:entity(row:id()):despawn()
            local attest = connection:get("core/player/attest")
            local proof = connection:get_mut("git/collaborators/authorize/proof")
            local asked = row:get("vault/git")
            local reply = row:get("vault/git/proof/reply")
            if proof ~= nil and proof.state == "checking" and asked.nonce == proof.nonce
                and attest.nonce == proof.nonce then
                local said
                if reply.status == "proved" then
                    proof.state, said = "writer", "writer"
                elseif reply.status == "absent" and now - proof.asked_at < wait then
                    -- The push may still be landing: asked again after as long as it has been.
                    proof.state = "absent"
                    proof.next_at = math.min(proof.asked_at + wait, now + math.max(1, now - proof.asked_at))
                    said = string.format("absent, asking again in %.0f s", proof.next_at - now)
                elseif reply.status == "absent" then
                    proof.state, proof.next_at, said = "absent", nil, "absent"
                else
                    proof.state, proof.why = "denied", tostring(reply.message or reply.status)
                    said = "denied"
                end
                print(string.format("[GIT/COLLABORATORS/AUTHORIZE] '%s': %s", tostring(proof.user), said))
            end
        end
    end

    local new = {}
    for _, w in ipairs(arrived:iter()) do new[w:id()] = true end
    local asking = {}
    for _, w in ipairs(writes:iter()) do
        local write = w:get("core/asset/write")
        local user = write.author and write.author.user
        local verdict, why, waiting = nil, "not attested here", false
        if user == nil then
            verdict, why = "deny", "anonymous"
        else
            for _, connection in ipairs(connections:iter_mut()) do
                local attest = connection:get("core/player/attest")
                local nonce = attest.nonce
                if attest.state == "attested" and attest.user == user and nonce ~= nil then
                    local proof = connection:get_mut("git/collaborators/authorize/proof")
                    local current = proof ~= nil and proof.nonce == nonce and proof.user == user
                    if current and proof.state == "writer" then
                        verdict = "allow"
                        break
                    elseif asking[nonce] or (current and (proof.state == "checking"
                        or (proof.state == "absent" and proof.next_at ~= nil))) then
                        waiting = true
                    elseif not current or (proof.state == "absent" and new[w:id()]) then
                        asking[nonce], waiting = true, true
                        if current then
                            proof.state, proof.why, proof.asked_at, proof.next_at = "checking", nil, now, nil
                        elseif proof ~= nil then
                            proof.user, proof.nonce, proof.state, proof.why, proof.asked_at, proof.next_at =
                                user, nonce, "checking", nil, now, nil
                        else
                            commands:entity(connection:id()):insert({
                                ["git/collaborators/authorize/proof"] = {
                                    user = user, nonce = nonce, state = "checking", asked_at = now,
                                },
                            })
                        end
                        ask(commands, connection, nonce)
                        print(string.format("[GIT/COLLABORATORS/AUTHORIZE] '%s' wrote %s: asking root for the proof",
                            user, tostring(write.path)))
                    else
                        why = proof.why or proof.state
                    end
                end
            end
            if verdict == nil and not waiting then verdict = "deny" end
        end
        if verdict ~= nil then
            commands:entity(w:id()):insert({ ["core/asset/write/reply"] = { verdict = verdict, why = why } })
            if verdict == "deny" then
                print(string.format("[GIT/COLLABORATORS/AUTHORIZE] %s %s by '%s' refused: %s",
                    tostring(write.op), tostring(write.path), tostring(user or "anonymous"), why))
            end
        end
    end
end):in_set("git/collaborators/authorize"):after("core/asset/server_ops"):before("core/asset/server_verdict")
    -- A reply crosses from root's VM, and a mirrored edge arrives as surely as a local one, so the
    -- reply's own edge is enough to settle what waits on it. A proof's change (its wait running
    -- out, final) settles them too.
    :run_if({
        Query[{
            ["or"] = {
                added = { "core/asset/write", "vault/git/proof/reply" },
                changed = { "git/collaborators/authorize/proof" },
                removed = { "git/collaborators/authorize/proof" },
            },
        }],
    }, function(touched)
        return not touched:is_empty()
    end)

-- Timed work: a proof still "absent" inside its wait is asked of root again when its time comes,
-- and one whose wait has run out becomes final, which settles the writes waiting on it. Runs only
-- while one is due.
app:add_systems(First, {
    Res[Time],
    Query[{
        with = { "core/net/connection", "core/player/attest", Mut["git/collaborators/authorize/proof"] },
        without = { "WorldMirror" },
    }],
    Query[{ with = { "git/collaborators/authorize" }, without = { "WorldMirror" } }],
    Commands,
}, function(time, connections, carriers, commands)
    local now = time:elapsed_secs()
    local wait = proof_wait(carriers)
    for _, connection in ipairs(connections:iter_mut()) do
        local proof = connection:get_mut("git/collaborators/authorize/proof")
        if proof.state == "absent" and proof.next_at ~= nil and now >= proof.next_at
            and connection:get("core/player/attest").nonce == proof.nonce then
            if now - proof.asked_at >= wait then
                proof.next_at = nil
            else
                proof.state, proof.next_at = "checking", nil
                ask(commands, connection, proof.nonce)
            end
        end
    end
end):in_set("git/collaborators/authorize")
    :run_if({
        Res[Time],
        Query[{ with = { "git/collaborators/authorize/proof" }, without = { "WorldMirror" } }],
    }, function(time, proofs)
        local now = time:elapsed_secs()
        for _, row in ipairs(proofs:iter()) do
            local proof = row:get("git/collaborators/authorize/proof")
            if proof.state == "absent" and proof.next_at ~= nil and now >= proof.next_at then return true end
        end
        return false
    end)

-- A new attestation on a connection is a new join: the proof named the old nonce, so it goes, and its check with it.
app:add_systems(Update, {
    Query[{
        changed = { "core/player/attest" },
        with = { "core/net/connection", "git/collaborators/authorize/proof" },
        without = { "WorldMirror" },
        optional = { "Children" },
    }],
    Query[{ with = { "vault/git/proof", "Request" } }],
    Commands,
}, function(connections, checks, commands)
    for _, connection in ipairs(connections:iter()) do
        local attest = connection:get("core/player/attest")
        local proof = connection:get("git/collaborators/authorize/proof")
        if attest.state ~= "attested" or attest.nonce ~= proof.nonce or attest.user ~= proof.user then
            commands:entity(connection:id()):try_remove("git/collaborators/authorize/proof")
            for _, check in ipairs(checks:iter_many(connection:get("Children") or {})) do
                commands:entity(check:id()):despawn()
            end
        end
    end
end):in_set("git/collaborators/authorize"):after("core/player/attest")

return {
    defaults = {
        ["git/collaborators/authorize"] = { proof_wait = 90 },
    },
}
