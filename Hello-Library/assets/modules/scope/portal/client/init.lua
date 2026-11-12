-- The client half of a portal. Walking in predicts the crossing: one ask to root, which shows the
-- target at once while the player stays this world's. Only this world's server decides the
-- crossing, and its switch on this client's player is followed with a plain ask, which confirms
-- the prediction. Root drops a second ask for a flip already under way. An ask is root's once made,
-- so a reload of this file does not take it back.

local Quat = require("bevy::math::Quat")

-- The predicted ask carries where the player stands and looks, for the target's client world to
-- stand it in: through a door (`at`, on a named node) relative to the door, as the target places
-- it at the node `at` names there; through any other portal as it stands here. The look is the
-- whole camera, which a crossing keeps, with its yaw made relative to the body: only the yaw turns
-- with a turned place. Plain tables: the ask crosses VMs, which refuse a value with a metatable. A
-- player still cooling from its last crossing walks into nothing; the server skips it too, on its
-- own timer.
app:add_systems(Update, {
    Query[{
        changed = { "collision_trigger" },
        with = { "scope/portal" },
        without = { "placement" },
        optional = { "Name", "GlobalTransform" },
    }],
    Query[{
        with = { "player", "core/net/local", "GlobalTransform" },
        without = { "scope/portal/cooling" },
        optional = { "camera" },
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
        local portal = p:get("scope/portal")
        local entered = p:get("collision_trigger").entered or {}
        local door = portal.at ~= nil and p:has("Name") and p:has("GlobalTransform")
        if not watching and portal.target ~= scope then
            for _, player in ipairs(mine:iter_many(entered)) do
                local body = player.GlobalTransform:compute_transform()
                local t = body
                if door then t = player.GlobalTransform:reparented_to(p:id()) end
                local camera = player:has("camera") and player:get("camera") or {}
                local look = {}
                for field, value in pairs(camera) do
                    look[field] = value
                end
                look.yaw = (camera.yaw or 0) - Quat.to_euler(body.rotation, "YXZ")[1]
                look.pitch = camera.pitch or 0
                commands:spawn({
                    ["core/world/flip"] = {
                        scope = portal.target,
                        predicted = {
                            at = door and portal.at or nil,
                            place = {
                                translation = { x = t.translation.x, y = t.translation.y, z = t.translation.z },
                                rotation = { x = t.rotation.x, y = t.rotation.y, z = t.rotation.z, w = t.rotation.w },
                                scale = { x = t.scale.x, y = t.scale.y, z = t.scale.z },
                            },
                            look = look,
                        },
                    },
                    ["player/spawner/standin"] = {},
                    WorldShared = {},
                    ["core/net/sync"] = false,
                    ["core/script/owner"] = false,
                })
                print(string.format("[SCOPE/PORTAL] walked into %s: predicting the crossing%s", portal.target,
                    door and (" through door '" .. p:get("Name").name .. "'") or ""))
            end
        end
    end
end):in_set("scope/portal/client")

-- The server's switch reaches only its player's owner, and is followed when it landed on a player
-- that is this client's (`core/net/local`), or stopped being so with it: the server sends the
-- switch a frame before it demotes the player, but both can reach this client in one frame. On
-- `changed` too: its removal after the handover is sent to nobody, so the copy here keeps the last
-- switch, and the next crossing writes over it. That kept copy is why the player must be this
-- client's: a reload of this file sees every switch as changed, and a player handed over long
-- before is no longer this client's, its removal edge long gone. Back in place, core takes the old
-- switch off the player.
-- In `First` before the net client, a frame after it wrote the switch: a removal reaches a Lua
-- system only from the frame after, so this is the one run that sees the switch's edge and the
-- demotion's together.
app:add_systems(First, {
    Query[{
        changed = { "core/net/peer/switch" },
        with = { "player" },
        optional = { "core/net/local" },
    }],
    Query[{
        removed = { "core/net/local" },
        with = { "player" },
    }],
    Commands,
}, function(switched, demoted, commands)
    local just = demoted:iter()
    for _, player in ipairs(switched:iter()) do
        local ours = player:has("core/net/local")
        for _, d in ipairs(just) do
            if d:id() == player:id() then ours = true end
        end
        if ours then
            local target = player:get("core/net/peer/switch").target_scope
            commands:spawn({
                ["core/world/flip"] = { scope = target },
                WorldShared = {},
                ["core/net/sync"] = false,
                ["core/script/owner"] = false,
            })
            print(string.format("[SCOPE/PORTAL] the server hands the player to %s: asking root to follow", target))
        end
    end
end):in_set("scope/portal/client"):before("core/net/client_inbound")
