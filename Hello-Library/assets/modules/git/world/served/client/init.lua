-- git/world/served, the client's half: while this world's own content library is the player's
-- checkout, its carrier also carries git/status, which watches the player's edits there. Core sets
-- the library's `edits` from the home fact, so it is true exactly while this world holds the
-- checkout.
--
-- git/world/served = {}

app:add_systems(Update, {
    Query[{ with = { "git/world/served" }, optional = { "git/status" } }],
    Query[{ with = { "core/library" }, without = { "WorldMirror" } }],
    Query[{ with = { "core/world/status", "WorldShared" }, without = { "WorldMirror" } }],
    Commands,
}, function(carriers, libraries, statuses, commands)
    local me = statuses:iter()[1]
    local status = me and me:get("core/world/status")
    local scope = status and status.scope_key
    local holds = false
    for _, lib in ipairs(libraries:iter()) do
        local declared = lib:get("core/library")
        if scope ~= nil and declared.ref == scope and declared.edits == true then holds = true end
    end
    for _, e in ipairs(carriers:iter()) do
        if holds and not e:has("git/status") then
            commands:entity(e:id()):insert({ ["git/status"] = {}, ["git/merge"] = {} })
            print(string.format("[GIT/WORLD/SERVED] '%s' is your checkout: watching your edits", tostring(scope)))
        elseif not holds and e:has("git/status") then
            commands:entity(e:id()):remove("git/status")
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

-- git/world/served was taken off an entity that stays: the git/status it added goes. A despawned
-- carrier is in the `removed` rows too, which `try_remove` passes by.
app:add_systems(Update, {
    Query[{ removed = { "git/world/served" } }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        commands:entity(e:id()):try_remove("git/status")
    end
end):in_set("git/world/served/removed")

return {}
