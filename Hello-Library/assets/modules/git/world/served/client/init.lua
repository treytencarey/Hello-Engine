-- git/world/served, the client's half: while this world's own content library is the player's
-- checkout, its carrier also carries its two sub-mods: git/world/served/status, which watches the
-- player's edits there, and git/world/served/merge, which merges the world's versions into them.
-- Core sets the library's `edits` from the home fact, so it is true exactly while this world holds
-- the checkout. As it turns them on, it asks the player's root for the writer proof
-- (`vault/git/proof`), which the world's host checks before it takes a write.
--
-- git/world/served = {}

-- The world's host lets this player write once it finds the proof ref in the world's repository.
-- Root pushes it for the world it joined, naming nothing from here.
local function push(commands, carrier)
    commands:spawn({
        ["vault/git/proof"] = {},
        ["vault/git"] = {},
        Request = {},
        ChildOf = carrier:id(),
        ["core/script/owner"] = false,
    })
end

app:add_systems(Update, {
    Query[{
        with = { "git/world/served" },
        optional = { "git/world/served/status", "git/world/served/merge" },
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
    Commands,
}, function(carriers, libraries, statuses, identities, processes, commands)
    local me = statuses:iter()[1]
    local status = me and me:get("core/world/status")
    local scope = status and status.scope_key
    local holds = false
    for _, lib in ipairs(libraries:iter()) do
        local declared = lib:get("core/library")
        if scope ~= nil and declared.ref == scope and declared.edits == true then holds = true end
    end
    -- The proof is asked as git/world/served/status asks: only while the player is signed in, as an
    -- anonymous player can't write, and not in both-mode, where nothing is uploaded. Only root's
    -- statements count: any world can share a `core/process` or a `core/player/identity` of its own.
    local signed_in, both = false, false
    for _, row in ipairs(identities:iter()) do
        local from = row:has("WorldMirror") and row:get("WorldMirror").world_id or world_id or 0
        if from == 0 and row:get("core/player/identity").site_user_id ~= nil then signed_in = true end
    end
    for _, row in ipairs(processes:iter()) do
        local from = row:has("WorldMirror") and row:get("WorldMirror").world_id or world_id or 0
        if from == 0 and row:get("core/process").mode == "both" then both = true end
    end
    for _, e in ipairs(carriers:iter()) do
        local status_on, merge_on = e:has("git/world/served/status"), e:has("git/world/served/merge")
        if holds and not (status_on and merge_on) then
            commands:entity(e:id()):insert_if_new({ ["git/world/served/status"] = {}, ["git/world/served/merge"] = {} })
            if signed_in and not both then push(commands, e) end
            print(string.format("[GIT/WORLD/SERVED] '%s' is your checkout: watching your edits", tostring(scope)))
        elseif not holds and (status_on or merge_on) then
            commands:entity(e:id()):try_remove("git/world/served/status", "git/world/served/merge")
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

-- Signing in while the sub-mods are on asks too. Root's identity changes for other reasons while
-- signed in (a linked account), so a push already open is not asked again.
app:add_systems(Update, {
    Query[{
        changed = { "core/player/identity" },
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
}, function(identities, processes, carriers, open, commands)
    local signed_in, both = false, false
    for _, row in ipairs(identities:iter()) do
        local from = row:has("WorldMirror") and row:get("WorldMirror").world_id or world_id or 0
        if from == 0 and row:get("core/player/identity").site_user_id ~= nil then signed_in = true end
    end
    for _, row in ipairs(processes:iter()) do
        local from = row:has("WorldMirror") and row:get("WorldMirror").world_id or world_id or 0
        if from == 0 and row:get("core/process").mode == "both" then both = true end
    end
    for _, e in ipairs(carriers:iter()) do
        if signed_in and not both and open:iter_many(e:get("Children") or {})[1] == nil then
            push(commands, e)
            print("[GIT/WORLD/SERVED] signed in: asking root for the writer proof")
        end
    end
end):in_set("git/world/served")

-- git/world/served was taken off an entity that stays: the sub-mods it added go. A despawned
-- carrier is in the `removed` rows too, which `try_remove` passes by.
app:add_systems(Update, {
    Query[{ removed = { "git/world/served" } }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        commands:entity(e:id()):try_remove("git/world/served/status", "git/world/served/merge")
    end
end)

-- A reply crosses from root's VM, and a mirrored edge arrives as surely as a local one, so the
-- reply's own edge is all this runs on.
app:add_systems(Update, {
    Query[{
        added = { "vault/git/proof/reply" },
        with = { "ChildOf" },
        without = { "RequestFrom", "WorldMirror" },
    }],
    Query[{ with = { "git/world/served" } }],
    Commands,
}, function(replies, carriers, commands)
    for _, row in ipairs(replies:iter()) do
        if carriers:contains(row:get("ChildOf")) then
            local reply = row:get("vault/git/proof/reply")
            print(string.format("[GIT/WORLD/SERVED] proof push: %s %s", tostring(reply.status), tostring(reply.message or "")))
            commands:entity(row:id()):despawn()
        end
    end
end):in_set("git/world/served")

return {}
