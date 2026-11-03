-- What an agent notices, written into its `ai/agent/memory`. It decides nothing. Vision looks at
-- each thought, for `ai/perception/target`s in range, inside the cone and not behind anything, and
-- drops what it has not seen for too long. Hearing happens as each `ai/noisemaker/sound` does, and
-- drops what is too old then.
--
-- ai/perception = {
--     vision_range = <metres>,
--     vision_fov_deg = <degrees of the whole cone>,
--     awareness_range = <metres within which the cone does not matter>,
--     eye_height = <metres from its origin up to its eyes>,
--     target_height = <metres from a target's origin up to where it looks>,
--     target_margin = <metres short of a target its look stops, so only something between counts>,
--     forget_seen_after = <seconds>,
--     hearing_range = <metres, for the loudest sound>,
--     forget_sound_after = <seconds>,
-- }
--
-- ai/perception/target: on what agents look for, added by whoever wants it seen

local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")
local Time = require("bevy::time::Time")
local On = require("bevy::ecs::prelude::On")
local ReadRapierContext = require("bevy_rapier3d::plugin::ReadRapierContext")

-- A patch merges a shorter list over a longer one, leaving the tail: the tail is taken out by name.
local function replacing(list, before)
    local value = {}
    for i, entry in ipairs(list) do
        value[i] = entry
    end
    for i = #list + 1, #before do
        value[i] = null
    end
    return value
end

app:add_systems(Update, {
    Res[Time],
    Query[{
        changed = { "ai/agent/tick" },
        with = { "ai/perception", "ai/agent/memory", "Transform" },
    }],
    Query[{
        with = { "ai/perception/target", "Transform" },
        without = { "WorldMirror" },
    }],
    ReadRapierContext,
    Commands,
}, function(time, agents, targets, rapier, commands)
    local now = time:elapsed_secs()
    for _, a in ipairs(agents:iter()) do
        local p = a:get("ai/perception")
        local before = a:get("ai/agent/memory").seen
        local transform = a:get("Transform")
        local at = transform.translation
        local forward = Quat.mul_vec3(transform.rotation, { x = 0, y = 0, z = 1 })

        local seen = {}
        for _, t in ipairs(targets:iter()) do
            if t:id() ~= a:id() then
                local to = t:get("Transform").translation
                local flat = { x = to.x - at.x, y = 0, z = to.z - at.z }
                local distance = Vec3.length(flat)
                local in_view = distance <= p.vision_range and (distance <= p.awareness_range
                    or Vec3.dot(forward, Vec3.normalize_or_zero(flat)) >= math.cos(math.rad(p.vision_fov_deg * 0.5)))
                if in_view then
                    local eye = { x = at.x, y = at.y + p.eye_height, z = at.z }
                    local line = { x = to.x - eye.x, y = to.y + p.target_height - eye.y, z = to.z - eye.z }
                    local reach = Vec3.length(line) - p.target_margin
                    if rapier:cast_ray(eye, Vec3.normalize_or_zero(line), reach, true, { exclude_rigid_body = a:id() }) == nil then
                        seen[#seen + 1] = { entity = t:id(), at = { x = to.x, y = to.y, z = to.z }, seen_at = now }
                    end
                end
            end
        end

        -- What it saw before and does not see now stays, until it is too old or its entity goes.
        for _, old in ipairs(before) do
            local again = false
            for _, new in ipairs(seen) do
                again = again or new.entity == old.entity
            end
            if not again and old.entity ~= nil and now - old.seen_at <= p.forget_seen_after then
                seen[#seen + 1] = old
            end
        end

        if #seen > 0 or #before > 0 then
            commands:entity(a:id()):patch({ ["ai/agent/memory"] = { seen = replacing(seen, before) } })
        end
    end
end):in_set("ai/perception/see")

-- Written through the row, so the next sound of the frame reads this one.
app:add_observer(On["ai/noisemaker/sound"], {
    Res[Time],
    Query[{ with = { "ai/perception", Mut["ai/agent/memory"], "Transform" } }],
}, function(event, time, agents)
    local now = time:elapsed_secs()
    for _, a in ipairs(agents:iter_mut()) do
        local p = a:get("ai/perception")
        local at = a:get("Transform").translation
        local distance = Vec3.length({ x = event.x - at.x, y = 0, z = event.z - at.z })
        local before = a:get("ai/agent/memory").sound
        local sound = {}
        for _, old in ipairs(before) do
            if now - old.heard_at <= p.forget_sound_after then
                sound[#sound + 1] = old
            end
        end
        if distance <= p.hearing_range * event.loudness then
            sound[#sound + 1] = { at = { x = event.x, y = event.y, z = event.z }, heard_at = now }
        end
        if #sound > 0 or #before > 0 then
            a:patch({ ["ai/agent/memory"] = { sound = replacing(sound, before) } })
        end
    end
end)

return {
    defaults = {
        ["ai/perception"] = {
            vision_range = 18,
            vision_fov_deg = 100,
            awareness_range = 3,
            eye_height = 1,
            target_height = 0.3,
            target_margin = 0.7,
            forget_seen_after = 20,
            hearing_range = 25,
            forget_sound_after = 20,
        },
    },
}
