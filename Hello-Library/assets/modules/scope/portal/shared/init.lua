-- A portal: a way into another world, named by its scope key. A hosted portal a player dropped
-- stands in its target too, leading back (the server half); any other is one-ended, the way back
-- being the other world's own portal. On both sides a dropped portal is a fixed ball of radius 1.2
-- that says who walks into it (`collision_trigger`); one still being placed is none of that.
--
-- scope/portal = {
--     target = <the scope key of the world it leads to>,
--     at = <on a door: the Name of the node in the target's map this door stands for there>,
-- }
--
-- scope/portal/hosted = {}: on a placed portal whose target runs in this process with its join's
-- peer link up, written by the server.
--
-- scope/portal/locked = {
--     reason = <why the target cannot be shown>,
-- }
--
-- scope/portal/cooling = {}: on a player handed in from another world, for 3 s, while it may not
-- cross again. It is a `cooldown` timer that crosses with the player from the portal it took.

local Collider = require("bevy_rapier3d::geometry::Collider")
local ReadRapierContext = require("bevy_rapier3d::plugin::ReadRapierContext")

-- The body comes when the portal is dropped (`placement` removed), or at its spawn when it is never
-- placed (a scene's door): one being placed follows its placer, and must hold no one. Only walking
-- in counts: the trigger starts out holding whoever already overlaps the ball (`inside`), so the
-- player a portal is dropped on, or a door spawns around, has not walked in until it walks out and
-- back in. Rapier's query sees only bodies, not fixed colliders, as a fixed trigger does. Before
-- `collision_trigger/init`, so the sensor parts it adds land with the body: a body without them is
-- a solid ball for a step. `insert_if_new`: a reload sees every portal as added again. A cancelled
-- placement despawns the portal, which has no row in `dropped`. A scene's node is placed by its
-- parents, so its place is its world place.
app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "scope/portal" },
            removed = { "placement" },
        },
    }],
    Query[{
        with = { "scope/portal" },
        without = { "placement" },
        optional = { "Transform", "GlobalTransform", "ChildOf" },
    }],
    ReadRapierContext,
    Commands,
}, function(touched, dropped, rapier, commands)
    local ids = {}
    for _, e in ipairs(touched:iter()) do
        ids[#ids + 1] = e:id()
    end
    for _, e in ipairs(dropped:iter_many(ids)) do
        local place = e:get("Transform")
        if e:has("ChildOf") and e:has("GlobalTransform") then
            place = e.GlobalTransform:compute_transform()
        end
        local inside = {}
        if place ~= nil then
            inside = rapier:intersect_shape(place.translation, place.rotation, Collider.ball(1.2),
                { flags = "EXCLUDE_FIXED" })
        end
        commands:entity(e:id()):insert_if_new({
            RigidBody3d = "Fixed",
            Collider3d = { ball = { radius = 1.2 } },
            collision_trigger = { entered = {}, exited = {}, inside = inside },
        })
    end
end):in_set("scope/portal/shared"):before("collision_trigger/init")

-- A body that reaches Rapier inside a placed portal (a player spawned in a door, one handed in
-- there) has not walked in either: it joins the trigger's `inside` before the trigger reads it.
-- Rapier's query answers it from the frame its collider has a handle.
app:add_systems(First, {
    Query[{
        added = { "RapierColliderHandle3d" },
        without = { "scope/portal" },
    }],
    Query[{
        with = { "scope/portal", "collision_trigger" },
        without = { "placement" },
        optional = { "Transform", "GlobalTransform", "ChildOf" },
    }],
    ReadRapierContext,
    Commands,
}, function(appeared, portals, rapier, commands)
    for _, p in ipairs(portals:iter()) do
        local place = p:get("Transform")
        if p:has("ChildOf") and p:has("GlobalTransform") then
            place = p.GlobalTransform:compute_transform()
        end
        local held = p:get("collision_trigger").inside or {}
        local overlapping = {}
        if place ~= nil then
            overlapping = rapier:intersect_shape(place.translation, place.rotation, Collider.ball(1.2),
                { flags = "EXCLUDE_FIXED" })
        end
        local joining = {}
        for _, id in ipairs(overlapping) do
            local known = not appeared:contains(id)
            for _, old in ipairs(held) do
                if old == id then known = true end
            end
            if not known then joining[#joining + 1] = id end
        end
        if #joining > 0 then
            commands:entity(p:id()):entry("collision_trigger"):and_modify(function(trigger)
                local inside = trigger.inside or {}
                for _, id in ipairs(joining) do
                    inside[#inside + 1] = id
                end
                trigger.inside = inside
            end)
        end
    end
end):in_set("scope/portal/shared"):before("collision_trigger")
    :run_if({
        Query[{
            added = { "RapierColliderHandle3d" },
            without = { "scope/portal" },
        }],
    }, function(appeared)
        return not appeared:is_empty()
    end)

-- `scope/portal` was taken off an entity that stays. A despawned entity has no row in `parts`.
app:add_systems(First, {
    Query[{ removed = { "scope/portal" } }],
    Query[{ any_of = { "RigidBody3d", "Collider3d", "collision_trigger" } }],
    Commands,
}, function(removed, parts, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(parts:iter_many(gone)) do
        commands:entity(e:id()):try_remove("RigidBody3d", "Collider3d", "collision_trigger")
    end
end):in_set("scope/portal/shared")
