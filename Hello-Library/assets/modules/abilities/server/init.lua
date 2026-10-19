-- The server half: what an ability does happens on the server (its sub-mods), so the server
-- reads each ability's press, and declares that action's sync on the player (client
-- authority, the owner only). An ability that went loses its entry.

register_system("First", function(world)
    for _, e in ipairs(world:query({
        ["or"] = { added = { "abilities" }, changed = { "abilities" } },
        optional = { "core/net/sync" },
    })) do
        local sync = e:get("core/net/sync")
        local entries = {}
        if type(sync) == "table" then
            for name in pairs(sync) do
                if name:sub(1, #"input/game/abilities/") == "input/game/abilities/" then entries[name] = null end
            end
        end
        for name in pairs(e:get("abilities")) do
            entries["input/game/abilities/" .. name] = { authority = "client", target = "owner" }
        end
        e:patch({ ["core/net/sync"] = entries })
    end
end, { label = "AbilitiesSync" })

-- `abilities` was taken off an entity that stays: take off the action syncs this half added.
register_system("First", function(world)
    for _, e in ipairs(world:query({
        ["or"] = { removed = { "abilities" } },
        optional = { "abilities" },
    })) do
        local entries = {}
        for name in pairs(e:get("abilities") or {}) do
            entries["input/game/abilities/" .. name] = null
        end
        if next(entries) and world:get_entity(e:id()) then e:patch({ ["core/net/sync"] = entries }) end
    end
end, { label = "AbilitiesUnsync" })
