-- The client half: a pose reaching this world means a headset is tracking here, so this client's
-- player is in VR. A host with VR on and tracking off has no poses, and stays on the desktop.

local bevy = require("bevy::prelude")
local Time = require("bevy::time::Time")
local VrPoseInput = require("hello::vr_messages::VrPoseInput")

-- Polls: poses stopping is the absence of a message. `vr/active` waits for its sync, which comes
-- from the server after `vr` does: one added before that would never be sent. `vr/tracking` is
-- apart from it as it changes with every pose, and never crosses.
app:add_systems(First, {
    Res[Time],
    bevy.MessageReader[VrPoseInput],
    Query[{
        with = { "vr", "core/net/local", "core/net/sync" },
        optional = { "vr/active", "vr/tracking" },
    }],
    Commands,
}, function(time, poses, players, commands)
    local now = time:elapsed_secs()
    local tracking = #poses:read() > 0
    for _, e in ipairs(players:iter()) do
        local player = commands:entity(e:id())
        if tracking then
            player:insert({ ["vr/tracking"] = { at = now } })
            if not e:has("vr/active") and e:get("core/net/sync")["vr/active"] ~= nil then
                player:insert({ ["vr/active"] = {} })
            end
        elseif e:has("vr/active") and now - e:get("vr/tracking").at > e:get("vr").timeout then
            player:remove("vr/active")
        end
    end
end):in_set("vr/detect")
