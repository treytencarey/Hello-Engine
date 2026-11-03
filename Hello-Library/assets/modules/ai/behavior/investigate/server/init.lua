-- Walks to where something was heard and looks around. It keeps an option linked to the agent and
-- scores it from `ai/agent/memory`'s `sound`: a sound is picked by how fresh and how near it is, and
-- kept unless another is clearly better. Once it has looked, or found no way there, that sound and
-- older ones are done with, and the score falls.
--
-- ai/behavior/investigate = {
--     speed = <metres per second>,
--     base_score = <its score for a sound as it goes stale>,
--     fresh_weight = <what freshness adds to the score>,
--     fresh_for = <seconds a sound is worth walking to>,
--     distance_weight = <how much a metre of distance counts against freshness>,
--     switch_margin = <how much better another sound must be>,
--     look_time = <seconds it looks around when it gets there>,
-- }
--
-- ai/behavior/investigate/option: marks its option entity
-- ai/behavior/investigate/state = {
--     at = { x, y, z }: the sound it is going to,
--     heard_at = <when that was heard>,
--     done_at = <when the newest sound it is done with was heard>,
--     look_until = <when it stops looking>,
--     path_before = <the `ai/nav/path` it had when it asked>,
-- }: on the option entity

local Vec3 = require("bevy::math::Vec3")
local Time = require("bevy::time::Time")

local function flat_distance(a, b)
    return Vec3.length({ x = a.x - b.x, y = 0, z = a.z - b.z })
end

-- Its option exists once the agent does, whichever comes first. What it knows lives on the option,
-- so the option outlives the mod's reloads; its link takes it with the agent.
app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "ai/behavior/investigate", "ai/agent" },
        },
        with = { "ai/behavior/investigate", "ai/agent" },
        optional = { "ai/agent/options" },
    }],
    Query[{ with = { "ai/behavior/investigate/option" } }],
    Commands,
}, function(agents, options, commands)
    for _, a in ipairs(agents:iter()) do
        if options:iter_many(a:get("ai/agent/options") or {})[1] == nil then
            commands:spawn({
                ["ai/agent/option"] = { entity = a:id(), score = 0 },
                ["ai/behavior/investigate/option"] = {},
                Name = { name = "investigate" },
                ["core/script/owner"] = false,
            })
        end
    end
end):in_set("ai/behavior/investigate/option")

app:add_systems(Update, {
    Res[Time],
    Query[{
        changed = { "ai/agent/tick" },
        with = { "ai/behavior/investigate", "ai/agent/memory", "ai/agent/options", "Transform" },
    }],
    Query[{
        with = { "ai/behavior/investigate/option", Mut["ai/agent/option"] },
        optional = { "ai/behavior/investigate/state" },
    }],
    Commands,
}, function(time, agents, options, commands)
    local now = time:elapsed_secs()
    for _, a in ipairs(agents:iter()) do
        local c = a:get("ai/behavior/investigate")
        local o = options:iter_many_mut(a:get("ai/agent/options"))[1]
        if o ~= nil then
            local state = o:get("ai/behavior/investigate/state") or {}
            local at = a:get("Transform").translation

            local best, best_value, kept, kept_value
            for _, entry in ipairs(a:get("ai/agent/memory").sound) do
                local age = now - entry.heard_at
                if age < c.fresh_for and (state.done_at == nil or entry.heard_at > state.done_at) then
                    local value = 1 - age / c.fresh_for - flat_distance(entry.at, at) * c.distance_weight
                    if best == nil or value > best_value then
                        best, best_value = entry, value
                    end
                    if entry.heard_at == state.heard_at then
                        kept, kept_value = entry, value
                    end
                end
            end
            local pick = best
            if kept ~= nil and best_value <= kept_value + c.switch_margin then
                pick = kept
            end

            local score = 0
            if pick ~= nil then
                score = c.base_score + c.fresh_weight * (1 - (now - pick.heard_at) / c.fresh_for)
            end
            if score ~= o:get("ai/agent/option").score then
                o:patch({ ["ai/agent/option"] = { score = score } })
            end

            if pick == nil and state.at ~= nil then
                commands:entity(o:id()):patch({
                    ["ai/behavior/investigate/state"] = { at = null, heard_at = null, look_until = null, path_before = null },
                })
            elseif pick ~= nil and pick.heard_at ~= state.heard_at then
                commands:entity(o:id()):patch({
                    ["ai/behavior/investigate/state"] = { at = pick.at, heard_at = pick.heard_at, look_until = null, path_before = null },
                })
            end
        end
    end
end):in_set("ai/behavior/investigate/score")

-- Chosen, at each thought: ask for the way to the sound, look around once there, and be done with it
-- then, or when there is no way there. What `ai/steering` says counts only for a path answered since
-- it asked, as a stale "arrived" is about the last place it went.
app:add_systems(Update, {
    Res[Time],
    Query[{
        changed = { "ai/agent/tick" },
        with = { "ai/behavior/investigate", "ai/nav/request", "ai/agent/options" },
        optional = { "ai/steering", "ai/steering/state", "ai/nav/path" },
    }],
    Query[{
        with = { "ai/agent/chosen", "ai/behavior/investigate/option", "ai/behavior/investigate/state" },
    }],
    Commands,
}, function(time, agents, chosen, commands)
    local now = time:elapsed_secs()
    for _, a in ipairs(agents:iter()) do
        local o = chosen:iter_many(a:get("ai/agent/options"))[1]
        local state = o and o:get("ai/behavior/investigate/state")
        if state ~= nil and state.at ~= nil then
            local c = a:get("ai/behavior/investigate")
            local entity = commands:entity(a:id())
            local asked = a:get("ai/nav/request").investigate
            local path = a:get("ai/nav/path")
            local steer = a:get("ai/steering/state")
            local solved = path and path.solved_id

            if a:has("ai/steering") and a:get("ai/steering").speed ~= c.speed then
                entity:patch({ ["ai/steering"] = { speed = c.speed } })
            end

            if asked == nil or asked.to.x ~= state.at.x or asked.to.z ~= state.at.z then
                entity:patch({ ["ai/nav/request"] = { investigate = { to = state.at } } })
                commands:entity(o:id()):patch({
                    ["ai/behavior/investigate/state"] = { path_before = solved or 0, look_until = null },
                })
            elseif solved ~= nil and solved ~= state.path_before and steer ~= nil and steer.for_solved == solved then
                local done = path.status == "unreachable" or steer.status == "blocked"
                if steer.status == "arrived" and state.look_until == nil then
                    commands:entity(o:id()):patch({ ["ai/behavior/investigate/state"] = { look_until = now + c.look_time } })
                elseif steer.status == "arrived" and now >= state.look_until then
                    done = true
                end
                if done then
                    commands:entity(o:id()):patch({
                        ["ai/behavior/investigate/state"] = {
                            done_at = state.heard_at,
                            at = null,
                            heard_at = null,
                            look_until = null,
                            path_before = null,
                        },
                    })
                end
            end
        end
    end
end):in_set("ai/behavior/investigate/act")

-- No longer chosen: it stops asking.
app:add_systems(Update, {
    Query[{
        removed = { "ai/agent/chosen" },
        with = { "ai/behavior/investigate/option", "ai/agent/option" },
    }],
    Query[{ with = { "ai/behavior/investigate", "ai/nav/request" } }],
    Commands,
}, function(unchosen, agents, commands)
    for _, o in ipairs(unchosen:iter()) do
        local a = agents:get(o:get("ai/agent/option").entity)
        if a ~= nil and a:get("ai/nav/request").investigate ~= nil then
            commands:entity(a:id()):patch({ ["ai/nav/request"] = { investigate = null } })
        end
    end
end):in_set("ai/behavior/investigate/exit")

-- `ai/behavior/investigate` was taken off an agent that stays: its option and its asking go.
app:add_systems(First, {
    Query[{
        removed = { "ai/behavior/investigate" },
        optional = { "ai/agent/options", "ai/nav", "ai/nav/request" },
    }],
    Query[{ with = { "ai/behavior/investigate/option" } }],
    Commands,
}, function(removed, options, commands)
    for _, a in ipairs(removed:iter()) do
        for _, o in ipairs(options:iter_many(a:get("ai/agent/options") or {})) do
            commands:entity(o:id()):try_despawn()
        end
        -- Only while `ai/nav` stays: going with it, its request is about to be taken off, and a
        -- patch landing after that would bring it back.
        local request = a:get("ai/nav/request")
        if a:has("ai/nav") and request ~= nil and request.investigate ~= nil then
            commands:entity(a:id()):patch({ ["ai/nav/request"] = { investigate = null } })
        end
    end
end):in_set("ai/behavior/investigate/removed")

return {
    defaults = {
        ["ai/behavior/investigate"] = {
            speed = 3.4,
            base_score = 0.35,
            fresh_weight = 0.45,
            fresh_for = 20,
            distance_weight = 0.02,
            switch_margin = 0.25,
            look_time = 2.5,
        },
    },
}
