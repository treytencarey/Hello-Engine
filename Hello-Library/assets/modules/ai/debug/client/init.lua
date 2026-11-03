-- Draws what the server published in `ai/debug`: its ranges, the cone it looks in, the path it has
-- left, and posts where it remembers seeing and hearing things. Gizmos are drawn each frame, so there
-- is nothing to clean up. Its label names the chosen option.
--
-- ai/debug/label = { entity = <its agent> }: on a UI text
-- ai/debug/labels: an agent's label, kept by the engine

local Quat = require("bevy::math::Quat")
local Gizmos = require("bevy::gizmos::gizmos::Gizmos")

local function color(red, green, blue, alpha)
    return { Srgba = { red = red, green = green, blue = blue, alpha = alpha } }
end

local VISION = color(0.2, 0.8, 1, 0.55)
local AWARENESS = color(1, 0.55, 0.1, 0.65)
local HEARING = color(0.55, 0.35, 0.95, 0.35)
local CONE = color(0.2, 0.8, 1, 0.85)
local PATH = color(0.3, 1, 0.4, 1)
local WAYPOINT = color(0.1, 0.7, 0.25, 1)
local SEEN = color(1, 0.2, 0.2, 1)
local SOUND = color(0.75, 0.55, 1, 1)

local LIFT = 0.05

local function ring(gizmos, at, radius, tint)
    if radius == nil or radius <= 0 then
        return
    end
    local before
    for i = 0, 28 do
        local a = i / 28 * 2 * math.pi
        local point = { x = at.x + math.cos(a) * radius, y = at.y + LIFT, z = at.z + math.sin(a) * radius }
        if before ~= nil then
            gizmos:line(before, point, tint)
        end
        before = point
    end
end

local function post(gizmos, at, tint)
    gizmos:line(at, { x = at.x, y = at.y + 1.8, z = at.z }, tint)
    gizmos:line({ x = at.x - 0.4, y = at.y, z = at.z }, { x = at.x + 0.4, y = at.y, z = at.z }, tint)
    gizmos:line({ x = at.x, y = at.y, z = at.z - 0.4 }, { x = at.x, y = at.y, z = at.z + 0.4 }, tint)
end

app:add_systems(Update, {
    Gizmos,
    Query[{ with = { "ai/debug", "Transform" } }],
}, function(gizmos, agents)
    for _, e in ipairs(agents:iter()) do
        local d = e:get("ai/debug")
        local transform = e:get("Transform")
        local at = transform.translation

        ring(gizmos, at, d.hearing_range, HEARING)
        ring(gizmos, at, d.vision_range, VISION)
        ring(gizmos, at, d.awareness_range, AWARENESS)

        if d.vision_range ~= nil and d.vision_fov_deg ~= nil then
            local forward = Quat.mul_vec3(transform.rotation, { x = 0, y = 0, z = 1 })
            for _, side in ipairs({ -1, 1 }) do
                local edge = Quat.mul_vec3(Quat.from_rotation_y(side * math.rad(d.vision_fov_deg * 0.5)), forward)
                gizmos:line({ x = at.x, y = at.y + LIFT, z = at.z },
                    { x = at.x + edge.x * d.vision_range, y = at.y + LIFT, z = at.z + edge.z * d.vision_range }, CONE)
            end
        end

        local before = { x = at.x, y = at.y + LIFT, z = at.z }
        for i = 1, d.path_count or 0 do
            local p = { x = d.path[i].x, y = d.path[i].y + LIFT, z = d.path[i].z }
            gizmos:line(before, p, PATH)
            gizmos:line({ x = p.x - 0.25, y = p.y, z = p.z }, { x = p.x + 0.25, y = p.y, z = p.z }, WAYPOINT)
            gizmos:line({ x = p.x, y = p.y, z = p.z - 0.25 }, { x = p.x, y = p.y, z = p.z + 0.25 }, WAYPOINT)
            before = p
        end

        for i = 1, d.seen_count or 0 do
            post(gizmos, d.seen[i], SEEN)
        end
        for i = 1, d.sound_count or 0 do
            post(gizmos, d.sound[i], SOUND)
        end
    end
end):in_set("ai/debug/draw")

-- One label down the side of the window for each agent, with what it is doing. Each says which agent
-- it is by the entity's own print.
app:add_systems(Update, {
    Query[{
        changed = { "ai/debug" },
        optional = { "ai/debug/labels" },
    }],
    Query[{ with = { "ai/debug/label" } }],
    Commands,
}, function(agents, labels, commands)
    for _, e in ipairs(agents:iter()) do
        local chosen = e:get("ai/debug").chosen
        local text = tostring(e:id()) .. ": " .. ((chosen == nil or chosen == "") and "nothing" or chosen)
        local label = labels:iter_many(e:get("ai/debug/labels") or {})[1]
        if label ~= nil then
            commands:entity(label:id()):patch({ Text = { text = text } })
        else
            commands:spawn({
                ["ai/debug/label"] = { entity = e:id() },
                Text = { text = text },
                TextFont = { font_size = 14 },
                Node = {
                    position_type = "Absolute",
                    left = { Px = 12 },
                    top = { Px = 12 + 18 * #labels:iter() },
                },
                ["core/net/sync"] = false,
            })
        end
    end
end):in_set("ai/debug/label")

-- `ai/debug` was taken off an agent that stays: its label goes.
app:add_systems(First, {
    Query[{
        removed = { "ai/debug" },
        with = { "ai/debug/labels" },
    }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        for _, label in ipairs(e:get("ai/debug/labels")) do
            commands:entity(label):try_despawn()
        end
    end
end):in_set("ai/debug/removed")

return {
    relationships = {
        ["ai/debug/label"] = { target = "ai/debug/labels", linked_spawn = true },
    },
}
