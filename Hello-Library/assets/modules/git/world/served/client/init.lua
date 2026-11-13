-- git/world/served, the client's half: while this world's own content library is the player's
-- checkout, its carrier also carries its two sub-mods: git/world/served/status, which watches the
-- player's edits there, and git/world/served/merge, which merges the world's versions into them;
-- and edit/notice, which shows the uploads on screen.
-- Core sets the library's `edits` from the home fact, so it is true exactly while this world holds
-- the checkout. As it turns them on, it asks the player's root for the writer proof
-- (`vault/git/proof`), which the world's host checks before it takes a write.
--
-- git/world/served = {}

-- The world's host lets this player write once it finds the proof ref in the world's repository.
-- Root pushes it for the world it joined, naming nothing from here. The request owns the ref: root
-- deletes the ref when the request goes, so it stays open while the checkout is this world's, and
-- is replaced when root's join record changes (a new ticket names a new ref).
local function push(commands, carrier)
    commands:spawn({
        ["vault/git/proof"] = {},
        ["vault/git"] = {},
        Request = {},
        ChildOf = carrier:id(),
        ["core/script/owner"] = false,
    })
end

--- Whether root's statement `row` is root's own: any world can share a `core/process`, a
--- `core/player/identity` or a `core/world/join` of its own.
local function from_root(row)
    return (row:has("WorldMirror") and row:get("WorldMirror").world_id or world_id or 0) == 0
end

--- Whether a push would prove anything: the player is signed in, not in both-mode, where nothing is
--- uploaded, and root's join record for this world is bound to them. Root pushes the ref that
--- record's ticket names, and a world joined anonymously holds an anonymous ticket until root has
--- the Site sign a new one after the sign-in, so a push before then names a ticket the world's
--- host never sees again.
local function provable(identities, joins, processes)
    local user
    for _, row in ipairs(identities:iter()) do
        local id = row:get("core/player/identity").site_user_id
        if from_root(row) and id ~= nil then user = tostring(id) end
    end
    local bound = false
    for _, row in ipairs(joins:iter()) do
        if from_root(row) and user ~= nil and tostring(row:get("core/world/join").requester) == user then bound = true end
    end
    for _, row in ipairs(processes:iter()) do
        if from_root(row) and row:get("core/process").mode == "both" then return false end
    end
    return bound
end

--- Whether root says the player is signed out: its identity is here without a `site_user_id`, and
--- this is not both-mode, where nothing is sent anyway. No identity from root yet says nothing.
local function signed_out(identities, processes)
    local seen = false
    for _, row in ipairs(identities:iter()) do
        if from_root(row) then
            if row:get("core/player/identity").site_user_id ~= nil then return false end
            seen = true
        end
    end
    for _, row in ipairs(processes:iter()) do
        if from_root(row) and row:get("core/process").mode == "both" then return false end
    end
    return seen
end

app:add_systems(Update, {
    Query[{
        with = { "git/world/served" },
        optional = { "git/world/served/status", "git/world/served/merge", "Children" },
    }],
    Query[{ with = { "core/library" }, without = { "WorldMirror" } }],
    Query[{ with = { "core/world/status", "WorldShared" }, without = { "WorldMirror" } }],
    Query[{
        with = { "core/player/identity" },
        optional = { "WorldMirror" },
    }],
    Query[{
        with = { "core/process" },
        optional = { "WorldMirror" },
    }],
    Query[{
        with = { "core/world/join" },
        optional = { "WorldMirror" },
    }],
    Query[{ with = { "vault/git/proof", "Request" } }],
    Commands,
}, function(carriers, libraries, statuses, identities, processes, joins, open, commands)
    local me = statuses:iter()[1]
    local status = me and me:get("core/world/status")
    local scope = status and status.scope_key
    local holds = false
    for _, lib in ipairs(libraries:iter()) do
        local declared = lib:get("core/library")
        if scope ~= nil and declared.ref == scope and declared.edits == true then holds = true end
    end
    local proving = provable(identities, joins, processes)
    local local_only = signed_out(identities, processes)
    for _, e in ipairs(carriers:iter()) do
        local status_on, merge_on = e:has("git/world/served/status"), e:has("git/world/served/merge")
        if holds and not (status_on and merge_on) then
            commands:entity(e:id()):insert_if_new({
                ["git/world/served/status"] = {}, ["git/world/served/merge"] = {}, ["edit/notice"] = {},
            })
            if proving then push(commands, e) end
            print(string.format("[GIT/WORLD/SERVED] '%s' is your checkout: watching your edits", tostring(scope)))
            -- Signed out, git/world/served/status sends nothing, and a save would otherwise pass
            -- without a word.
            if local_only then
                print("[GIT/WORLD/SERVED] this world uses your checkout, but you are not signed in — "
                    .. "edits stay local until you connect your account")
                commands:spawn({
                    ["git/merge/notice"] = {
                        text = "This world uses your checkout, but you are not signed in — "
                            .. "edits stay local until you connect your account",
                    },
                    notification = { timeout = 20 },
                    ["core/script/owner"] = false,
                })
            end
        elseif not holds and (status_on or merge_on) then
            commands:entity(e:id()):try_remove("git/world/served/status", "git/world/served/merge", "edit/notice")
            for _, ask in ipairs(open:iter_many(e:get("Children") or {})) do
                commands:entity(ask:id()):try_despawn()
            end
            print(string.format("[GIT/WORLD/SERVED] '%s' is no longer your checkout: stopped watching", tostring(scope)))
        end
    end
end):in_set("git/world/served")
    :run_if({
        Query[{
            ["or"] = { changed = { "git/world/served", "core/library", "core/world/status" } },
            without = { "WorldMirror" },
        }],
    }, function(touched)
        return not touched:is_empty()
    end)

-- Signing in while the sub-mods are on asks too, once root's join record is bound to the player:
-- on the identity's edge when the record already is (a launch signed in), else on the record's
-- edge when root has the new ticket. Root's identity changes for other reasons while signed in (a
-- linked account), so on its edge alone a push already open is not asked again. Root's join record
-- changing replaces the open request: the old ref names the old ticket.
app:add_systems(Update, {
    Query[{
        ["or"] = { added = { "core/world/join" }, changed = { "core/player/identity", "core/world/join" } },
        optional = { "WorldMirror" },
    }],
    Query[{
        with = { "core/player/identity" },
        optional = { "WorldMirror" },
    }],
    Query[{
        with = { "core/world/join" },
        optional = { "WorldMirror" },
    }],
    Query[{
        with = { "core/process" },
        optional = { "WorldMirror" },
    }],
    Query[{
        with = { "git/world/served", "git/world/served/status", "git/world/served/merge" },
        optional = { "Children" },
    }],
    Query[{ with = { "vault/git/proof", "Request" } }],
    Commands,
}, function(touched, identities, joins, processes, carriers, open, commands)
    local by_root, joined = false, false
    for _, row in ipairs(touched:iter()) do
        if from_root(row) then
            by_root = true
            if row:has("core/world/join") then joined = true end
        end
    end
    if not by_root then return end
    local proving = provable(identities, joins, processes)
    for _, e in ipairs(carriers:iter()) do
        local asks = open:iter_many(e:get("Children") or {})
        if joined then
            for _, ask in ipairs(asks) do commands:entity(ask:id()):try_despawn() end
        end
        if proving and (joined or asks[1] == nil) then
            push(commands, e)
            print("[GIT/WORLD/SERVED] signed in: asking root for the writer proof")
        end
    end
end):in_set("git/world/served")
    :run_if({
        Query[{
            ["or"] = {
                added = { "core/world/join" },
                changed = { "core/player/identity", "core/world/join" },
            },
        }],
    }, function(touched)
        return not touched:is_empty()
    end)

-- git/world/served was taken off an entity that stays: the sub-mods it added go, and its proof
-- request. A despawned carrier is in the `removed` rows too, which `try_remove` passes by.
app:add_systems(Update, {
    Query[{ removed = { "git/world/served" } }],
    Query[{ with = { "vault/git/proof", "Request", "ChildOf" } }],
    Commands,
}, function(removed, open, commands)
    for _, e in ipairs(removed:iter()) do
        commands:entity(e:id()):try_remove("git/world/served/status", "git/world/served/merge", "edit/notice")
        for _, ask in ipairs(open:iter()) do
            if ask:get("ChildOf") == e:id() then commands:entity(ask:id()):try_despawn() end
        end
    end
end)

-- A reply crosses from root's VM, and a mirrored edge arrives as surely as a local one, so the
-- reply's own edge is all this runs on. The request stays: it owns the ref.
app:add_systems(Update, {
    Query[{
        added = { "vault/git/proof/reply" },
        with = { "ChildOf" },
        without = { "RequestFrom", "WorldMirror" },
    }],
    Query[{ with = { "git/world/served" } }],
}, function(replies, carriers)
    for _, row in ipairs(replies:iter()) do
        if carriers:contains(row:get("ChildOf")) then
            local reply = row:get("vault/git/proof/reply")
            print(string.format("[GIT/WORLD/SERVED] proof push: %s %s", tostring(reply.status), tostring(reply.message or "")))
        end
    end
end):in_set("git/world/served")

return {}
