-- The server half: the owner removing `placement` confirms it, and the server takes the placed
-- entity's Transform back. The edge also comes for one cancelled, which has despawned.
--
-- placement = {}

app:add_systems(First, {
    Query[{
        removed = { "placement" },
        with = { "core/net/sync" },
    }],
    Commands,
}, function(taken, commands)
    for _, e in ipairs(taken:iter()) do
        local placed = commands:get_entity(e:id())
        if placed ~= nil then
            placed:entry("core/net/sync"):and_modify(function(sync)
                sync.Transform = { authority = "server" }
            end)
        end
    end
end):in_set("placement/taken")
