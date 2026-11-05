-- Wanders around where the agent first patrolled from, pausing between legs. Its option's score is
-- flat, low and never 0, so it is what an agent falls back on when nothing else is worth doing.
--
-- ai/behavior/patrol = {
--     speed = <metres per second>,
--     base_score = <its score>,
--     radius = <metres from home it wanders>,
--     near_share = <the share of the radius a leg ends no nearer than>,
--     pause_min = <seconds it stands, at least>,
--     pause_max = <seconds it stands, at most>,
-- }
--
-- ai/behavior/patrol/option: marks its option entity
-- ai/behavior/patrol/state = {
--     home = { x, y, z },
--     resume_at = <when it walks on, while it stands>,
--     path_before = <the `ai/nav/path` it had when it asked>,
-- }: on the option entity

local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")
local Time = require("bevy::time::Time")

-- Its option exists once the agent does, whichever comes first. What it knows lives on the option,
-- so the option outlives the mod's reloads; its link takes it with the agent.
app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "ai/behavior/patrol", "ai/agent" },
        },
        with = { "ai/behavior/patrol", "ai/agent" },
        optional = { "ai/agent/options" },
    }],
    Query[{ with = { "ai/behavior/patrol/option" } }],
    Commands,
}, function(agents, options, commands)
    for _, a in ipairs(agents:iter()) do
        if options:iter_many(a:get("ai/agent/options") or {})[1] == nil then
            commands:spawn({
                ["ai/agent/option"] = { entity = a:id(), score = a:get("ai/behavior/patrol").base_score },
                ["ai/behavior/patrol/option"] = {},
                Name = "patrol",
                -- It ends with its agent (`linked_spawn`), or at this mod's own `removed` edge.
                ["core/script/owner"] = false,
            })
        end
    end
end):in_set("ai/behavior/patrol/option")

-- Its score follows the field.
app:add_systems(Update, {
    Query[{
        changed = { "ai/behavior/patrol" },
        with = { "ai/agent/options" },
    }],
    Query[{ with = { "ai/behavior/patrol/option", Mut["ai/agent/option"] } }],
}, function(agents, options)
    for _, a in ipairs(agents:iter()) do
        local base_score = a:get("ai/behavior/patrol").base_score
        for _, o in ipairs(options:iter_many_mut(a:get("ai/agent/options"))) do
            if o:get("ai/agent/option").score ~= base_score then
                o:patch({ ["ai/agent/option"] = { score = base_score } })
            end
        end
    end
end):in_set("ai/behavior/patrol/score")

-- Chosen, at each thought: walk a leg, stand a while, walk another. A leg with no way there is simply
-- picked again. What `ai/steering` says counts only for a path answered since it asked, as a stale
-- "arrived" is about the last place it went.
app:add_systems(Update, {
    Res[Time],
    Query[{
        changed = { "ai/agent/tick" },
        with = { "ai/behavior/patrol", "ai/nav/request", "ai/agent/options", "Transform" },
        optional = { "ai/steering", "ai/steering/state", "ai/nav/path" },
    }],
    Query[{
        with = { "ai/agent/chosen", "ai/behavior/patrol/option" },
        optional = { "ai/behavior/patrol/state" },
    }],
    Commands,
}, function(time, agents, chosen, commands)
    local now = time:elapsed_secs()
    for _, a in ipairs(agents:iter()) do
        local o = chosen:iter_many(a:get("ai/agent/options"))[1]
        if o ~= nil then
            local c = a:get("ai/behavior/patrol")
            local state = o:get("ai/behavior/patrol/state") or {}
            local at = a:get("Transform").translation
            local home = state.home or { x = at.x, y = at.y, z = at.z }
            local asked = a:get("ai/nav/request").patrol
            local path = a:get("ai/nav/path")
            local steer = a:get("ai/steering/state")
            local solved = path and path.solved_id
            local answered = asked ~= nil and solved ~= nil and solved ~= state.path_before and steer ~= nil and steer.for_solved == solved

            local leg = asked == nil
            if answered and (path.status == "unreachable" or steer.status == "blocked") then
                leg = true
            elseif answered and steer.status == "arrived" then
                if state.resume_at == nil then
                    commands:entity(o:id()):patch({
                        ["ai/behavior/patrol/state"] = { resume_at = now + c.pause_min + math.random() * (c.pause_max - c.pause_min) },
                    })
                elseif now >= state.resume_at then
                    leg = true
                end
            end

            if a:has("ai/steering") and a:get("ai/steering").speed ~= c.speed then
                commands:entity(a:id()):patch({ ["ai/steering"] = { speed = c.speed } })
            end

            if leg then
                local reach = c.radius * (c.near_share + (1 - c.near_share) * math.random())
                local to = Vec3.add(home, Quat.mul_vec3(Quat.from_rotation_y(math.random() * 2 * math.pi), { x = reach, y = 0, z = 0 }))
                commands:entity(a:id()):patch({ ["ai/nav/request"] = { patrol = { to = to } } })
                commands:entity(o:id()):patch({
                    ["ai/behavior/patrol/state"] = { home = home, path_before = solved or 0, resume_at = null },
                })
            end
        end
    end
end):in_set("ai/behavior/patrol/act")

-- No longer chosen: it stops asking.
app:add_systems(Update, {
    Query[{
        removed = { "ai/agent/chosen" },
        with = { "ai/behavior/patrol/option", "ai/agent/option" },
    }],
    -- Only while `ai/nav` stays: going with it, its request is about to be taken off.
    Query[{ with = { "ai/behavior/patrol", "ai/nav", "ai/nav/request" } }],
    Commands,
}, function(unchosen, agents, commands)
    for _, o in ipairs(unchosen:iter()) do
        local a = agents:get(o:get("ai/agent/option").entity)
        if a ~= nil and a:get("ai/nav/request").patrol ~= nil then
            commands:entity(a:id()):patch({ ["ai/nav/request"] = { patrol = null } })
        end
    end
end):in_set("ai/behavior/patrol/exit")

-- `ai/behavior/patrol` was taken off an agent that stays: its option and its asking go.
app:add_systems(First, {
    Query[{
        removed = { "ai/behavior/patrol" },
        optional = { "ai/agent/options", "ai/nav", "ai/nav/request" },
    }],
    Query[{ with = { "ai/behavior/patrol/option" } }],
    Commands,
}, function(removed, options, commands)
    for _, a in ipairs(removed:iter()) do
        for _, o in ipairs(options:iter_many(a:get("ai/agent/options") or {})) do
            commands:entity(o:id()):try_despawn()
        end
        -- Only while `ai/nav` stays: going with it, its request is about to be taken off, and a
        -- patch landing after that would bring it back.
        local request = a:get("ai/nav/request")
        if a:has("ai/nav") and request ~= nil and request.patrol ~= nil then
            commands:entity(a:id()):patch({ ["ai/nav/request"] = { patrol = null } })
        end
    end
end):in_set("ai/behavior/patrol/removed")

return {
    defaults = {
        ["ai/behavior/patrol"] = {
            speed = 1.8,
            base_score = 0.2,
            radius = 14,
            near_share = 0.35,
            pause_min = 1.5,
            pause_max = 4,
        },
    },
}
