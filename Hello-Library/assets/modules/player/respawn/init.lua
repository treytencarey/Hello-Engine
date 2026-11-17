-- Respawn, an item in the sidebar's menu: a click stands the local player back on the spawn point it
-- claims, at rest, looking the way the point faces. The owning client drives its player's
-- Transform, so this runs on the client, with that side's copy of the map's points.
--
-- player/respawn = {}
--
-- player/respawn/item = {}

local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")

-- The item goes in the menu's list for a local player with respawn: on a new list (the menu opened,
-- or reloaded), and on the carrier itself (added, or this mod reloaded).
app:add_systems(Update, {
    Query[{ with = { "player/respawn", "core/net/local" } }],
    Query[{
        with = { "sidebar/menu/list" },
        optional = { "Children" },
    }],
    Query[{ with = { "player/respawn/item" } }],
    Commands,
}, function(carriers, lists, items, commands)
    if not carriers:is_empty() then
        for _, list in ipairs(lists:iter()) do
            local children = list:get("Children") or {}
            if items:iter_many(children)[1] == nil then
                local item = commands:spawn({
                    ["sidebar/menu/item"] = { title = "Respawn", order = 1 },
                    ["player/respawn/item"] = {},
                    ChildOf = list:id(),
                })
                -- A point sits on the floor, so the body stands on it by the height of its centre
                -- above its feet: the capsule's half height and radius, at the player's scale.
                -- `Collider3d` reads back in rapier's own form: the shape as written is `unscaled`,
                -- and a segment's ends are lists. The body's rotation is locked: the camera's yaw is
                -- what turns a player.
                item:observe(On[Pointer[Click]], {
                    Query[{
                        with = { "player/respawn", "player", "core/net/local", "Collider3d", Mut["Transform"] },
                        optional = { Mut["Velocity3d"], Mut["camera"] },
                    }],
                    Query[{ with = { "player/spawner/point", "Name", "GlobalTransform" } }],
                }, function(_, players, points)
                    for _, p in ipairs(players:iter_mut()) do
                        local claim = p:get("player").spawn_point
                        local collider = p:get("Collider3d")
                        local capsule = collider.unscaled.Capsule
                        for _, point in ipairs(points:iter()) do
                            local name = point:get("Name")
                            if capsule ~= nil and name.name == claim then
                                local body = p:get_mut("Transform")
                                local segment = capsule.segment
                                local height = ((segment.b[2] - segment.a[2]) / 2 + capsule.radius) * body.scale.y
                                local place = point.GlobalTransform:compute_transform()
                                body.translation = Vec3.add(place.translation,
                                    Quat.mul_vec3(place.rotation, { x = 0, y = height, z = 0 }))
                                if p:has("Velocity3d") then
                                    local v = p:get_mut("Velocity3d")
                                    v.linvel = { x = 0, y = 0, z = 0 }
                                    v.angvel = { x = 0, y = 0, z = 0 }
                                end
                                if p:has("camera") then
                                    p:get_mut("camera").yaw = Quat.to_euler(place.rotation, "YXZ")[1]
                                end
                                break
                            end
                        end
                    end
                end)
            end
        end
    end
end):in_set("player/respawn"):run_if({
    Query[{ added = { "sidebar/menu/list" } }],
    Query[{
        ["or"] = {
            added = { "player/respawn", "core/net/local" },
        },
        with = { "player/respawn", "core/net/local" },
    }],
}, function(new_lists, new_carriers)
    return not new_lists:is_empty() or not new_carriers:is_empty()
end)
