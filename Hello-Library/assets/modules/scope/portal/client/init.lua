-- The client half of a portal: walking in asks root to flip this player into the target's world.
-- Into a portal that is not hosted, at once, and root starts the world if nobody runs it. Into a
-- hosted one, only once the server has handed the player over, which this client sees as its own
-- player stopping being its own (`core/net/local` removed): a flip at once would race the handover.
-- Root drops a second ask for a flip already under way. An ask is root's once made, so a reload
-- of this file does not take it back.

-- A player still cooling from its last crossing walks into nothing. The handover is the server's
-- to decide, and it skips a cooling player itself: its own timer, not this client's, says when.
app:add_systems(Update, {
    Query[{
        changed = { "collision_trigger" },
        with = { "scope/portal" },
        without = { "placement", "scope/portal/hosted" },
    }],
    Query[{
        with = { "player", "core/net/local" },
        without = { "scope/portal/cooling" },
    }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(portals, mine, rows, commands)
    local me = rows:iter()[1]
    local row = me and me:get("core/world/status")
    local scope = row and row.scope_key
    local watching = row ~= nil and row.observer == true
    for _, p in ipairs(portals:iter()) do
        local target = p:get("scope/portal").target
        local entered = p:get("collision_trigger").entered or {}
        if not watching and target ~= scope and #mine:iter_many(entered) > 0 then
            commands:spawn({
                ["core/world/flip"] = { scope = target },
                WorldShared = {},
                ["core/net/sync"] = false,
                ["core/script/owner"] = false,
            })
            print(string.format("[SCOPE/PORTAL] walked into %s: asking root to flip there", target))
        end
    end
end):in_set("scope/portal/client")

app:add_systems(Update, {
    Query[{
        removed = { "core/net/local" },
        with = { "player" },
    }],
    Query[{
        with = { "scope/portal", "scope/portal/hosted", "collision_trigger" },
        without = { "placement" },
    }],
    Commands,
}, function(left, portals, commands)
    for _, player in ipairs(left:iter()) do
        for _, p in ipairs(portals:iter()) do
            local inside = p:get("collision_trigger").inside or {}
            local here = false
            for _, id in ipairs(inside) do
                if id == player:id() then
                    here = true
                    break
                end
            end
            if here then
                local target = p:get("scope/portal").target
                commands:spawn({
                    ["core/world/flip"] = { scope = target },
                    WorldShared = {},
                    ["core/net/sync"] = false,
                    ["core/script/owner"] = false,
                })
                print(string.format("[SCOPE/PORTAL] handed over to %s: asking root to follow", target))
                break
            end
        end
    end
end):in_set("scope/portal/client")
