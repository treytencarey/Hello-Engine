-- The server half: what an ability does happens on the server (its sub-mods), so the server
-- reads each ability's press, and declares that action's sync on the player (client
-- authority, the owner only). An ability that went loses its entry.

app:add_systems(First, {
    Query[{
        ["or"] = { added = { "abilities" }, changed = { "abilities" } },
        optional = { "core/net/sync" },
    }],
    Commands,
}, function(players, commands)
    for _, e in ipairs(players:iter()) do
        local sync = e:get("core/net/sync")
        local entries = {}
        if sync then
            for name in pairs(sync) do
                if name:sub(1, #"input/game/abilities/") == "input/game/abilities/" then entries[name] = null end
            end
        end
        for name in pairs(e:get("abilities")) do
            entries["input/game/abilities/" .. name] = { authority = "client", target = "owner" }
        end
        commands:entity(e:id()):patch({ ["core/net/sync"] = entries })
    end
end):in_set("abilities/sync")

-- `abilities` was taken off an entity that stays: take off the action syncs this half added.
-- A despawned player is in the `removed` rows too.
app:add_systems(First, {
    Query[{
        ["or"] = { removed = { "abilities" } },
        optional = { "abilities" },
    }],
    Query[{ with = { "core/net/sync" } }],
    Commands,
}, function(removed, synced, commands)
    for _, e in ipairs(removed:iter()) do
        local entries = {}
        for name in pairs(e:get("abilities") or {}) do
            entries["input/game/abilities/" .. name] = null
        end
        if next(entries) and synced:contains(e:id()) then
            commands:entity(e:id()):patch({ ["core/net/sync"] = entries })
        end
    end
end):in_set("abilities/unsync")

-- A peer mirror's press comes from its source's server, which sends what changes and never a
-- removal, so the press would stay and the next one would be no new press here. Once this world
-- has read it (the abilities ran on it in `Update`), it is taken off. An empty `added` list would
-- match every Lua component.
app:add_systems(PostUpdate, {
    Query[{
        with = { "abilities", "core/net/peer/mirror" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(mirrors, commands)
    local names = {}
    for _, e in ipairs(mirrors:iter()) do
        for name in pairs(e:get("abilities")) do
            names[#names + 1] = "input/game/abilities/" .. name
        end
    end
    if #names == 0 then return end
    for _, e in ipairs(mirrors:with_columns({ ["or"] = { added = names } }):iter()) do
        for name in pairs(e:get("abilities")) do
            if e:is_added("input/game/abilities/" .. name) then
                commands:entity(e:id()):try_remove("input/game/abilities/" .. name)
            end
        end
    end
end):in_set("abilities/server")
