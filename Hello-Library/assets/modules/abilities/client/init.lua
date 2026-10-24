-- The client half: the local player's ability keys, bound into `input/game` under the group
-- `abilities` (client data, never synced). Rebound when `input` arrives, and when the
-- abilities change; an ability that went is unbound.

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "abilities", "core/net/local", "input" },
            changed = { "abilities" },
        },
        with = { "abilities", "core/net/local" },
        optional = { "input/game" },
    }],
    Commands,
}, function(players, commands)
    for _, e in ipairs(players:iter()) do
        local bound = (e:get("input/game") or {}).abilities or {}
        local group = {}
        for name in pairs(bound) do group[name] = null end
        for name, a in pairs(e:get("abilities")) do
            if a.key then group[name] = { key = a.key } end
        end
        commands:entity(e:id()):patch({ ["input/game"] = { abilities = group } })
    end
end):in_set("abilities/bind")

-- `abilities` was taken off an entity that stays: its keys are unbound. A despawned player is
-- in the `removed` rows too.
app:add_systems(First, {
    Query[{
        ["or"] = { removed = { "abilities" } },
        with = { "core/net/local" },
    }],
    Query[{ with = { "input/game" } }],
    Commands,
}, function(removed, bound, commands)
    for _, e in ipairs(removed:iter()) do
        if bound:contains(e:id()) then
            commands:entity(e:id()):patch({ ["input/game"] = { abilities = null } })
        end
    end
end):in_set("abilities/unbind")
