-- The client half: what only this client's own player needs while it is in VR. Its controllers
-- are read here and nowhere else, so they are never synced.

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "vr/active", "player/vr", "core/net/local" },
        },
        with = { "vr/active", "player/vr", "core/net/local" },
    }],
    Commands,
}, function(entered, commands)
    for _, e in ipairs(entered:iter()) do
        commands:entity(e:id()):insert_if_new({
            ["vr/input"] = {},
            ["vr/pointer"] = {},
            ["vr/grabbable"] = {},
            ["vr/ui_panels"] = {},
        })
    end
end):in_set("player/vr/local")

-- Out of VR, or `player/vr` went: its last carrier unloads this half before `vr/active` follows
-- it. A despawned entity has no row in `parts`.
app:add_systems(First, {
    Query[{
        ["or"] = {
            removed = { "vr/active", "player/vr" },
        },
    }],
    Query[{ with = { "vr/input" } }],
    Commands,
}, function(left, parts, commands)
    local gone = {}
    for _, e in ipairs(left:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(parts:iter_many(gone)) do
        commands:entity(e:id()):remove("vr/input", "vr/pointer", "vr/grabbable", "vr/ui_panels")
    end
end):in_set("player/vr/local_removed")
