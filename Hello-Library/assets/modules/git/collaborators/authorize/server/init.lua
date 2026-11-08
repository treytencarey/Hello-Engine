-- git/collaborators/authorize, the server's half: the write policy of a world served from git. A
-- player may change this world's files once their root has pushed the ref their join's nonce names
-- to the world's repository, and this world's root finds it there. Core holds each write until this
-- answers it. The proof is kept on the client's `core/net/connection`, where core/player/attest
-- writes who it is, so it lasts as long as the connection, whichever player that client controls.
--
-- git/collaborators/authorize = {}
-- git/collaborators/authorize/proof = {
--     user = <the attested user the proof is for>,
--     nonce = <the attestation's nonce the check names>,
--     state = "checking" | "writer" | "absent" | "denied",
--     why = <root's message, when denied>,
--     asked_at = <this world's clock, in seconds, at the first ask for this nonce>,
-- }

local Time = require("bevy::time::Time")

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
-- once for its connection and waits. `absent` is not final: the player's push may still be landing, so
-- it is asked again at once soon after the first ask, and later the next write asks again.
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
    Query[{
        with = { "core/net/connection", "core/player/attest" },
        without = { "WorldMirror" },
        optional = { Mut["git/collaborators/authorize/proof"] },
    }],
    Commands,
}, function(time, replies, writes, connections, commands)
    local now = time:elapsed_secs()
    local settled = {}
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
                if reply.status == "proved" then
                    proof.state = "writer"
                elseif reply.status == "absent" and now - proof.asked_at < 10 then
                    -- The player's root pushes as the player's world turns its edits on, and status
                    -- uploads a dirty file as soon, so the first check can run before the push has
                    -- landed. A push takes a few seconds; 10 s covers it and stays well inside core's
                    -- 20 s hold on the write. Root's round trip spaces the asks, one open at a time.
                    ask(commands, connection, proof.nonce)
                elseif reply.status == "absent" then
                    proof.state = "absent"
                else
                    proof.state, proof.why = "denied", tostring(reply.message or reply.status)
                end
                settled[proof.nonce] = proof.state ~= "checking"
                print(string.format("[GIT/COLLABORATORS/AUTHORIZE] '%s': %s", tostring(proof.user),
                    proof.state == "checking" and "absent soon after the first ask, asking again" or proof.state))
            end
        end
    end

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
                    elseif asking[nonce] or (current and proof.state == "checking") then
                        waiting = true
                    elseif not current or (proof.state == "absent" and not settled[nonce]) then
                        asking[nonce], waiting = true, true
                        if current then
                            proof.state, proof.why = "checking", nil
                        elseif proof ~= nil then
                            proof.user, proof.nonce, proof.state, proof.why, proof.asked_at = user, nonce, "checking", nil, now
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
    -- reply's own edge is enough to settle what waits on it.
    :run_if({
        Query[{
            ["or"] = {
                added = { "core/asset/write", "vault/git/proof/reply" },
                removed = { "git/collaborators/authorize/proof" },
            },
        }],
    }, function(touched)
        return not touched:is_empty()
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

return {}
