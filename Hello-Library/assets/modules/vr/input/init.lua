-- VR controllers as ordinary input: each control presses the key or mouse button it is mapped to,
-- through the messages `input` takes from anything that is not a device, so mods bind actions as
-- they always do and need not know a headset exists. A stick press carries its strength. Poses go
-- on the player, in world space.
--
-- vr/input = {
--     press = <how far a trigger or grip goes to press>,
--     release = <how far it comes back to let go>,
--     deadzone = <how far a stick goes to count>,
--     controls = {
--         <control> = { key = <KeyCode> } or { button = <MouseButton> }, with analog = true for a stick,
--     },
-- }
--
-- vr/input/held = { <control> = <1, or the analog strength> }
--
-- vr/input/pose = {
--     hmd_position = { x, y, z }, hmd_rotation = { x, y, z, w }, hmd_forward = { x, y, z },
--     left_position, left_rotation, left_forward,
--     right_position, right_rotation, right_forward,
-- }

local bevy = require("bevy::prelude")
local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")
local VrInputRaw = require("hello::vr_messages::VrInputRaw")
local VrPoseInput = require("hello::vr_messages::VrPoseInput")

local function send(keys, buttons, bound, state)
    if bound.key then
        keys:write({ key_code = bound.key, state = state })
    elseif bound.button then
        buttons:write({ button = bound.button, state = state })
    end
end

-- A message at a time, as a quick press and release can share a frame. Up and down on the right
-- stick scroll, as a wheel does: that is motion, not something held.
app:add_systems(First, {
    bevy.MessageReader[VrInputRaw],
    bevy.MessageWriter["input/synthetic_key"],
    bevy.MessageWriter["input/synthetic_mouse_button"],
    bevy.MessageWriter["input/synthetic_mouse_wheel"],
    bevy.MessageWriter["input/analog"],
    Query[{
        with = { "vr/input", "core/net/local" },
        optional = { "vr/input/held" },
    }],
    Commands,
}, function(raw, keys, buttons, wheel, analog, players, commands)
    local messages = raw:read()
    for _, e in ipairs(players:iter()) do
        local m = e:get("vr/input")
        local held = {}
        for name, value in pairs(e:get("vr/input/held") or {}) do
            held[name] = value
        end
        local changed = {}
        for _, r in ipairs(messages) do
            for name, level in pairs({
                a = r.a and 1 or 0,
                b = r.b and 1 or 0,
                x = r.x and 1 or 0,
                y = r.y and 1 or 0,
                right_trigger = r.right_trigger,
                left_trigger = r.left_trigger,
                right_grip = r.right_grip,
                left_grip = r.left_grip,
                left_stick_up = r.left_stick_y,
                left_stick_down = -r.left_stick_y,
                left_stick_left = -r.left_stick_x,
                left_stick_right = r.left_stick_x,
                right_stick_left = -r.right_stick_x,
                right_stick_right = r.right_stick_x,
            }) do
                local bound = m.controls[name]
                if bound then
                    local was = held[name]
                    local value
                    if bound.analog then
                        if level > m.deadzone then
                            value = math.min(1, (level - m.deadzone) / (1 - m.deadzone))
                        end
                    elseif level > (was and m.release or m.press) then
                        value = 1
                    end
                    if value and not was then
                        send(keys, buttons, bound, "Pressed")
                    elseif was and not value then
                        send(keys, buttons, bound, "Released")
                    end
                    if value and value ~= was and bound.analog and bound.key then
                        analog:write({ key_code = bound.key, value = value })
                    end
                    if value ~= was then
                        held[name] = value
                        changed[name] = value or null
                    end
                end
            end
            if math.abs(r.right_stick_y) > m.deadzone then
                wheel:write({ x = 0, y = r.right_stick_y })
            end
        end
        if next(changed) then
            commands:entity(e:id()):patch({ ["vr/input/held"] = changed })
        end
    end
end):in_set("vr/input/raw"):before("input/held")

-- A pose comes in tracking space, and `VmXrRig` says where this player's tracking space is.
app:add_systems(First, {
    bevy.MessageReader[VrPoseInput],
    Query[{
        with = { "vr/input", "core/net/local" },
        optional = { "VmXrRig" },
    }],
    Commands,
}, function(poses, players, commands)
    local messages = poses:read()
    local p = messages[#messages]
    if p ~= nil then
        for _, e in ipairs(players:iter()) do
            local rig = e:get("VmXrRig") or { translation = { x = 0, y = 0, z = 0 }, yaw = 0 }
            local turn = Quat.from_rotation_y(rig.yaw)
            commands:entity(e:id()):insert({
                ["vr/input/pose"] = {
                    hmd_position = Vec3.add(rig.translation, Quat.mul_vec3(turn, p.hmd_position)),
                    hmd_rotation = Quat.mul_quat(turn, p.hmd_rotation),
                    hmd_forward = Quat.mul_vec3(turn, p.hmd_forward),
                    left_position = Vec3.add(rig.translation, Quat.mul_vec3(turn, p.left_position)),
                    left_rotation = Quat.mul_quat(turn, p.left_rotation),
                    left_forward = Quat.mul_vec3(turn, p.left_forward),
                    right_position = Vec3.add(rig.translation, Quat.mul_vec3(turn, p.right_position)),
                    right_rotation = Quat.mul_quat(turn, p.right_rotation),
                    right_forward = Quat.mul_vec3(turn, p.right_forward),
                },
            })
        end
    end
end):in_set("vr/input/pose")

-- A control held when the mod goes would hold its key for good, and `vr/input/held` is gone by
-- now, so every mapped key is let go.
app:add_systems(First, {
    Query[{
        ["or"] = { removed = { "vr/input" } },
        optional = { "vr/input" },
    }],
    bevy.MessageWriter["input/synthetic_key"],
    bevy.MessageWriter["input/synthetic_mouse_button"],
}, function(removed, keys, buttons)
    for _, e in ipairs(removed:iter()) do
        for _, bound in pairs(e:get("vr/input").controls) do
            send(keys, buttons, bound, "Released")
        end
    end
end):in_set("vr/input/removed"):before("input/held")

return {
    defaults = {
        ["vr/input"] = {
            press = 0.6,
            release = 0.4,
            deadzone = 0.15,
            controls = {
                a = { key = "Space" },
                b = { key = "Escape" },
                x = { key = "Tab" },
                y = { key = "KeyR" },
                right_trigger = { button = "Left" },
                left_trigger = { button = "Right" },
                right_grip = { key = "KeyG" },
                left_grip = { key = "KeyH" },
                left_stick_up = { key = "KeyW", analog = true },
                left_stick_down = { key = "KeyS", analog = true },
                left_stick_left = { key = "KeyA", analog = true },
                left_stick_right = { key = "KeyD", analog = true },
                right_stick_left = { key = "ArrowLeft", analog = true },
                right_stick_right = { key = "ArrowRight", analog = true },
            },
        },
    },
}
