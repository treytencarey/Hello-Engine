-- The stand-in, on a client world: while root shows a predicted crossing into this world, the
-- player walks on here as a local stand-in before the server's switch makes the world theirs. The
-- predicted ask carries this mod's component, so the mod loads wherever root's ask is mirrored;
-- it has only a client half, so it runs only in client worlds.
--
-- player/spawner/standin = {}: on root's predicted ask, and on the stand-in made from it

local Mat4 = require("bevy::math::Mat4")
local Quat = require("bevy::math::Quat")
local TransformSystems = require("bevy::transform::TransformSystems")

-- Only root's ask counts, a mirror from VM 0: any world could share one naming this world.
-- Through a door the stand-in stands where the player stood relative to the door, at the node the
-- door's `at` names here, turned likewise; through any other portal, where it stood. Its camera is
-- the player's whole camera (the look), its yaw turned by its facing; a copy, as the table `get`
-- answers is the ask's own value. The node is found by `Name` alone, and never per frame: the
-- stand-in is made at once, with one pass over every `Name`, and while it has no body yet (the map
-- still landing) only the `Name`s added since are checked; root rewrites the ask every frame while
-- it waits, so the ask's own edges cannot say when to pass. Never synced, and not this world's
-- player: the world net's observer gate keeps it from making the world `owned`. Not reaped with
-- this mod: it goes with its ask.
app:add_systems(PostUpdate, {
    Query[{ with = { "core/world/flip", "player/spawner/standin", "WorldMirror" } }],
    Query[{
        with = { "player/spawner/standin" },
        without = { "core/world/flip" },
    }],
    Query[{ added = { "Name" } }],
    Query[{ with = { "Name" } }],
    Query[{ with = { "GlobalTransform" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(asks, standins, landed, names, nodes, rows, commands)
    local me = rows:iter()[1]
    local scope = me and me:get("core/world/status").scope_key
    local shown
    for _, a in ipairs(asks:iter()) do
        local flip = a:get("core/world/flip")
        if a:get("WorldMirror").world_id == 0 and flip.scope == scope and flip.status == "predicted" then
            shown = flip.predicted
        end
    end
    local standin = standins:iter()[1]
    local id = standin and standin:id()
    local place
    if shown ~= nil and shown.at == nil then
        place = {
            translation = { x = 0, y = 0, z = 0 },
            rotation = { x = 0, y = 0, z = 0, w = 1 },
            scale = { x = 1, y = 1, z = 1 },
        }
    elseif shown ~= nil then
        local found
        for _, n in ipairs(id == nil and names:iter() or landed:iter()) do
            if found == nil and n:get("Name").name == shown.at then found = n:id() end
        end
        local node = found and nodes:iter_many({ found })[1]
        place = node and node.GlobalTransform:compute_transform()
    end
    if shown ~= nil and id == nil then
        id = commands:spawn({
            ["player/spawner/standin"] = {},
            ["core/net/sync"] = false,
            ["core/script/owner"] = false,
        }):id()
    end
    if place ~= nil and shown.place ~= nil then
        local from = shown.place
        local stood = Mat4.to_scale_rotation_translation(Mat4.mul(
            Mat4.from_scale_rotation_translation(place.scale, place.rotation, place.translation),
            Mat4.from_scale_rotation_translation(from.scale, from.rotation, from.translation)))
        local camera = {}
        for field, value in pairs(shown.look or {}) do
            camera[field] = value
        end
        camera.yaw = (camera.yaw or 0) + Quat.to_euler(stood.rotation, "YXZ")[1]
        camera.pitch = camera.pitch or 0
        commands:entity(id):insert({
            player = {},
            Transform = { translation = stood.translation, rotation = stood.rotation, scale = stood.scale },
            RigidBody3d = "Dynamic",
            Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
            LockedAxes3d = "ROTATION_LOCKED",
            Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
            movement = {},
            ["camera/third_person"] = {},
            camera = camera,
            ["core/net/local"] = true,
        })
        print(string.format("[PLAYER/SPAWNER/STANDIN] predicted crossing: the player stands in at %s",
            shown.at and ("'" .. shown.at .. "'") or "where it stood"))
    end
end):in_set("player/spawner/spawn"):after(TransformSystems.Propagate):run_if({
    Query[{ with = { "core/world/flip", "player/spawner/standin", "WorldMirror" } }],
    Query[{
        with = { "player/spawner/standin", "player" },
        without = { "core/world/flip" },
    }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
}, function(asks, standing, rows)
    local me = rows:iter()[1]
    local scope = me and me:get("core/world/status").scope_key
    local shown = false
    for _, a in ipairs(asks:iter()) do
        local flip = a:get("core/world/flip")
        if a:get("WorldMirror").world_id == 0 and flip.scope == scope and flip.status == "predicted" then
            shown = true
        end
    end
    return shown and standing:is_empty()
end)

-- A stand-in goes once no ask of root's naming this world still shows or promotes a prediction: it
-- failed (it timed out, its world vanished, its promotion timed out) or root dropped it. A
-- confirmed one keeps it until the real player takes its place. A done ask is root's pin for the
-- world and stays, so it does not count.
app:add_systems(PostUpdate, {
    Query[{ with = { "core/world/flip", "player/spawner/standin", "WorldMirror" } }],
    Query[{
        with = { "player/spawner/standin" },
        without = { "core/world/flip" },
    }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(asks, standins, rows, commands)
    local me = rows:iter()[1]
    local scope = me and me:get("core/world/status").scope_key
    local live = false
    for _, a in ipairs(asks:iter()) do
        local flip = a:get("core/world/flip")
        if a:get("WorldMirror").world_id == 0 and flip.scope == scope
            and (flip.status == "predicted" or flip.status == "promoting") then
            live = true
        end
    end
    for _, s in ipairs(live and {} or standins:iter()) do
        commands:entity(s:id()):despawn()
        print("[PLAYER/SPAWNER/STANDIN] the predicted crossing ended unconfirmed: the stand-in goes")
    end
end):in_set("player/spawner/left"):run_if({
    Query[{
        ["or"] = {
            changed = { "core/world/flip" },
            removed = { "core/world/flip" },
        },
    }],
    Query[{
        with = { "player/spawner/standin" },
        without = { "core/world/flip" },
    }],
}, function(touched, standins)
    return not (touched:is_empty() or standins:is_empty())
end)

-- The real player, arriving, takes the stand-in's place and look, which its client then sends as
-- its own (both are the owner's), and the stand-in goes. With no stand-in it stands where its
-- server put it.
app:add_systems(Update, {
    Query[{
        added = { "core/net/local" },
        with = { "player" },
        without = { "player/spawner/standin" },
    }],
    Query[{
        with = { "player/spawner/standin" },
        without = { "core/world/flip" },
        optional = { "Transform", "camera" },
    }],
    Commands,
}, function(arrived, standins, commands)
    for _, p in ipairs(arrived:iter()) do
        for _, s in ipairs(standins:iter()) do
            if s:has("Transform") and s:has("camera") then
                commands:entity(p:id()):insert({ Transform = s:get("Transform"), camera = s:get("camera") })
            end
            commands:entity(s:id()):try_despawn()
        end
    end
end):in_set("player/spawner/spawn")
