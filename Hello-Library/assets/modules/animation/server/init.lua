-- The server half: the server states a character's model, and every client draws it. What it
-- plays crosses from the side that moves it: `animation/playing` is listed in the character's sync
-- with its Transform's authority.

-- `animation` arriving on a character this world replicates: its `animation/playing` crosses as its
-- Transform does.
app:add_systems(First, {
    Query[{ added = { "animation" }, with = { "core/net/sync" }, without = { "WorldMirror", "core/net/peer/mirror" } }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        local sync = e:get("core/net/sync")
        if type(sync) == "table" and sync["animation/playing"] == nil then
            local transform = sync.Transform
            local authority = type(transform) == "table" and transform.authority or "server"
            commands:entity(e:id()):entry("core/net/sync"):and_modify(function(s)
                s["animation/playing"] = { authority = authority }
            end)
        end
    end
end):in_set("animation/sync")

-- `animation` taken off a character that stays: its entry goes.
app:add_systems(First, {
    Query[{ removed = { "animation" }, optional = { "core/net/sync" } }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        local entity = commands:get_entity(e:id())
        if entity ~= nil and type(e:get("core/net/sync")) == "table" then
            entity:entry("core/net/sync"):and_modify(function(s)
                s["animation/playing"] = nil
            end)
        end
    end
end):in_set("animation/sync")

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
