-- The client half of a player: the local player starts in game input with its sidebar, and
-- its own body turns dynamic, because this client drives its Transform, once this client's copy
-- of the map is ready under it. The body arrives from the server with its collider and only
-- changes type here: a body added after its collider never attaches. The net client marks its
-- own player `core/net/local` frames after the player arrives, so both edges count.

-- The first point of that name whose scene has its colliders, or nil: ready as the spawner decides
-- on the server, and a point no scene holds is ready at once.
local function ready_point(points, roots, name)
    for _, point in ipairs(points:iter()) do
        local named = point:get("Name")
        if named.name == name then
            local root = roots:iter_many(roots:iter_ancestors(point:id()))[1]
            local status = root and root:get("collider/status")
            if root == nil or (status ~= nil and status.state == "done") then
                return point
            end
        end
    end
end

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "player", "core/net/local" },
        },
        with = { "player", "core/net/local" },
    }],
    Commands,
}, function(owned, commands)
    for _, e in ipairs(owned:iter()) do
        commands:entity(e:id()):insert_if_new({
            input = {},
            ["input/mode"] = { mode = "input/game" },
            sidebar = {},
            ["sidebar/profiler"] = {},
            ["sidebar/profile"] = {},
            ["sidebar/invites"] = {},
            ["sidebar/menu"] = {},
            ["git/collaborators"] = {},
            ["player/respawn"] = {},
        })
    end
end):in_set("player/local")

-- Held again, kinematic, while the scene holding its claimed point rebuilds its colliders (a
-- re-export): its ground is gone until they are done.
app:add_systems(First, {
    Query[{ with = { "player", "core/net/local", Mut["RigidBody3d"] } }],
    Query[{ with = { "player/spawner/point", "Name" } }],
    Query[{
        with = { "SceneRoot" },
        optional = { "collider/status" },
    }],
}, function(owned, points, roots)
    for _, e in ipairs(owned:iter_mut()) do
        local player = e:get("player")
        if player.spawn_point ~= nil and ready_point(points, roots, player.spawn_point) == nil then
            e:get_mut("RigidBody3d"):set_if_neq("KinematicPositionBased")
        end
    end
end):in_set("player/local"):run_if({
    Query[{
        ["or"] = {
            changed = { "collider/status" },
            removed = { "collider/status" },
        },
    }],
}, function(statuses)
    return not statuses:is_empty()
end)

-- Its own body turns dynamic once it may fall: at once with no claim (a player handed over before a
-- point was ready here), else once its claimed point is ready on this client, whose copy of the map
-- can land seconds after the player; a body freed first falls through it. Again whenever the
-- server's kind is written over it: a new owner is sent its values a second time when the player
-- spawns, and that can land after the edges above (measured: a player walked in through a portal
-- stood frozen). Beside it, a gravity scale of 1: rapier applies `GravityScale3d` only when it
-- changes and ignores its removal, so a body whose scale something took off keeps the last one it
-- had (measured: 0 left it climbing at 6 m/s). In Update, after `collider` writes its status, so a
-- mod that puts a held player back on its point, ordered between the two, decides from the same
-- status and still finds it held.
app:add_systems(Update, {
    Query[{
        with = { "player", "core/net/local", Mut["RigidBody3d"] },
        optional = { "GravityScale3d" },
    }],
    Query[{ with = { "player/spawner/point", "Name" } }],
    Query[{
        with = { "SceneRoot" },
        optional = { "collider/status" },
    }],
    Commands,
}, function(owned, points, roots, commands)
    for _, e in ipairs(owned:iter_mut()) do
        local player = e:get("player")
        if player.spawn_point == nil or ready_point(points, roots, player.spawn_point) ~= nil then
            e:get_mut("RigidBody3d"):set_if_neq("Dynamic")
        end
        if not e:has("GravityScale3d") then
            commands:entity(e:id()):insert({ GravityScale3d = { value = 1 } })
        end
    end
end):in_set("player/local"):after("collider/status"):run_if({
    Query[{
        ["or"] = {
            added = { "player", "core/net/local" },
        },
        with = { "player", "core/net/local" },
    }],
    Query[{ changed = { "collider/status" } }],
    Query[{ added = { "player/spawner/point" } }],
    Query[{
        changed = { "RigidBody3d" },
        with = { "player", "core/net/local" },
    }],
    Query[{
        changed = { "player" },
        with = { "core/net/local" },
    }],
}, function(arrived, statuses, points, rewritten, claimed)
    return not (arrived:is_empty() and statuses:is_empty() and points:is_empty() and rewritten:is_empty()
        and claimed:is_empty())
end)

-- Its body's gravity scale taken off: 1 goes back, which rapier applies as a change. The edge also
-- comes for a player that despawned or stopped being this client's, which has no row in `owned`,
-- and neither has one whose scale is back already.
app:add_systems(First, {
    Query[{ removed = { "GravityScale3d" } }],
    Query[{
        with = { "player", "core/net/local" },
        without = { "GravityScale3d" },
    }],
    Commands,
}, function(unscaled, owned, commands)
    local ids = {}
    for _, e in ipairs(unscaled:iter()) do
        ids[#ids + 1] = e:id()
    end
    for _, e in ipairs(owned:iter_many(ids)) do
        commands:entity(e:id()):insert({ GravityScale3d = { value = 1 } })
    end
end):in_set("player/local")

-- The player stopped being this client's and stays: another world's server took it, and it is
-- now moved by what this world's server sends. Its body goes back to the server's kind, at rest.
app:add_systems(First, {
    Query[{
        removed = { "core/net/local" },
        with = { "player" },
        optional = { "RigidBody3d", "Velocity3d" },
    }],
    Commands,
}, function(released, commands)
    for _, e in ipairs(released:iter()) do
        if e:has("RigidBody3d") then
            commands:entity(e:id()):insert({ RigidBody3d = "KinematicPositionBased" })
        end
        if e:has("Velocity3d") then
            commands:entity(e:id()):insert({
                Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
            })
        end
    end
end):in_set("player/local")

-- `player` was taken off an entity that stays: take off what this half added. A despawned
-- entity has no row in `parts`.
app:add_systems(First, {
    Query[{ removed = { "player" } }],
    Query[{
        any_of = {
            "input", "sidebar", "sidebar/profiler", "sidebar/profile", "sidebar/invites", "sidebar/menu",
            "git/collaborators", "player/respawn", "GravityScale3d",
        },
    }],
    Commands,
}, function(removed, parts, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(parts:iter_many(gone)) do
        commands:entity(e:id()):remove("input", "input/mode", "sidebar", "sidebar/profiler", "sidebar/profile",
            "sidebar/invites", "sidebar/menu", "git/collaborators", "player/respawn", "GravityScale3d")
    end
end):in_set("player/removed")
