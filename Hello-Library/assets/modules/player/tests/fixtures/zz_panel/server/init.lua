-- A mod with the file browser's shape: it adds sync entries when it arrives and takes them off on
-- its `removed` edge, in `First`, where the registry writes the same component on the same edge.
app:add_systems(First, {
    Query[{ added = { "player/tests/fixtures/zz_panel" }, optional = { "core/net/sync" } }],
    Commands,
}, function(carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        commands:entity(e:id()):patch({
            ["core/net/sync"] = {
                ["zz/panel/request"] = { authority = "client", target = "owner" },
                ["zz/panel/answer"] = { authority = "server", target = "owner" },
            },
        })
    end
end):in_set("zz/panel/init")

app:add_systems(First, {
    Query[{ removed = { "player/tests/fixtures/zz_panel" } }],
    Query[{ with = { "core/net/sync" } }],
    Commands,
}, function(removed, synced, commands)
    for _, e in ipairs(removed:iter()) do
        if synced:contains(e:id()) then
            commands:entity(e:id()):patch({
                ["core/net/sync"] = {
                    ["zz/panel/request"] = null,
                    ["zz/panel/answer"] = null,
                },
            })
        end
    end
end):in_set("zz/panel/removed")

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
