-- The client half: the local player's ability keys, bound into `input/game` under the group
-- `abilities` (client data, never synced). Rebound when `input` arrives, and when the
-- abilities change; an ability that went is unbound.

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "abilities", "core/net/owner", "input" },
            changed = { "abilities", "core/net/owner" },
        },
        -- An ability going changes `abilities`, perhaps as `input` goes too: its bindings go with `input`.
        with = { "abilities", "core/net/owner", "input" },
        optional = { "input/game" },
    }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(players, own, commands)
    for _, e in ipairs(players:iter()) do
        if own:contains(e:get("core/net/owner")) then
            local bound = (e:get("input/game") or {}).abilities or {}
            local group = {}
            for name in pairs(bound) do group[name] = null end
            for name, a in pairs(e:get("abilities")) do
                if a.key then group[name] = { key = a.key } end
            end
            commands:entity(e:id()):patch({ ["input/game"] = { abilities = group } })
        end
    end
end):in_set("abilities/bind")

-- `abilities` was taken off an entity that stays: its keys are unbound, unless `input` went too, as
-- its bindings go with it and a patch landing after that would bring them back. A despawned player
-- is in the `removed` rows too.
app:add_systems(First, {
    Query[{
        ["or"] = { removed = { "abilities" } },
        with = { "core/net/owner" },
        optional = { "input" },
    }],
    Query[{ with = { "input/game" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(removed, bound, own, commands)
    for _, e in ipairs(removed:iter()) do
        if e:has("input") and bound:contains(e:id()) and own:contains(e:get("core/net/owner")) then
            commands:entity(e:id()):patch({ ["input/game"] = { abilities = null } })
        end
    end
end):in_set("abilities/unbind")
