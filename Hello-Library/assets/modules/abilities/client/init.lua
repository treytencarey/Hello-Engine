-- The client half: the local player's ability keys, bound into `input/game` under the group
-- `abilities` (client data, never synced). Rebound when `input` arrives, and when the
-- abilities change; an ability that went is unbound.

register_system("First", function(world)
    for _, e in ipairs(world:query({
        ["or"] = {
            added = { "abilities", "core/net/local", "input" },
            changed = { "abilities" },
        },
        with = { "abilities", "core/net/local" },
        optional = { "input/game" },
    })) do
        local bound = (e:get("input/game") or {}).abilities or {}
        local group = {}
        for name in pairs(bound) do group[name] = null end
        for name, a in pairs(e:get("abilities")) do
            if a.key then group[name] = { key = a.key } end
        end
        e:patch({ ["input/game"] = { abilities = group } })
    end
end, { label = "AbilitiesBind" })

-- `abilities` was taken off an entity that stays: its keys are unbound.
register_system("First", function(world)
    for _, e in ipairs(world:query({
        ["or"] = { removed = { "abilities" } },
        with = { "core/net/local" },
    })) do
        e:patch({ ["input/game"] = { abilities = null } })
    end
end, { label = "AbilitiesUnbind" })
