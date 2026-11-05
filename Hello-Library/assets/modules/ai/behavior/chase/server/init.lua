-- Runs at what the agent has seen. It keeps an option linked to the agent and scores it from
-- `ai/agent/memory`'s `seen`: a target is picked by how fresh and how near it is, and kept unless
-- another is clearly better. There is no "lost it": what it saw grows stale, the score falls, and
-- the agent's other options take over. While its option is chosen it asks `ai/nav` for the way.
--
-- ai/behavior/chase = {
--     speed = <metres per second>,
--     base_score = <its score for something seen just now is this plus fresh_weight>,
--     fresh_weight = <what freshness adds to the score>,
--     fresh_for = <seconds a sighting is worth chasing>,
--     distance_weight = <how much a metre of distance counts against freshness>,
--     switch_margin = <how much better another target must be>,
--     repath_distance = <metres a target must move before it asks again>,
--     give_up_for = <seconds it scores nothing after finding no way>,
-- }
--
-- ai/behavior/chase/option: marks its option entity
-- ai/behavior/chase/state = { target = <entity>, at = { x, y, z }, gave_up_until }: on the option entity

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
            added = { "ai/behavior/chase", "ai/agent" },
        },
        with = { "ai/behavior/chase", "ai/agent" },
        optional = { "ai/agent/options" },
    }],
    Query[{ with = { "ai/behavior/chase/option" } }],
    Commands,
}, function(agents, options, commands)
    for _, a in ipairs(agents:iter()) do
        if options:iter_many(a:get("ai/agent/options") or {})[1] == nil then
            commands:spawn({
                ["ai/agent/option"] = { entity = a:id(), score = 0 },
                ["ai/behavior/chase/option"] = {},
                Name = "chase",
                ["core/script/owner"] = false,
            })
        end
    end
end):in_set("ai/behavior/chase/option")

app:add_systems(Update, {
    Res[Time],
    Query[{
        changed = { "ai/agent/tick" },
        with = { "ai/behavior/chase", "ai/agent/memory", "ai/agent/options", "Transform" },
    }],
    Query[{
        with = { "ai/behavior/chase/option", Mut["ai/agent/option"] },
        optional = { "ai/behavior/chase/state" },
    }],
    Commands,
}, function(time, agents, options, commands)
    local now = time:elapsed_secs()
    for _, a in ipairs(agents:iter()) do
        local c = a:get("ai/behavior/chase")
        local o = options:iter_many_mut(a:get("ai/agent/options"))[1]
        if o ~= nil then
            local state = o:get("ai/behavior/chase/state") or {}
            local at = a:get("Transform").translation

            local best, best_value, kept, kept_value
            if state.gave_up_until == nil or now >= state.gave_up_until then
                for _, entry in ipairs(a:get("ai/agent/memory").seen) do
                    local age = now - entry.seen_at
                    if age < c.fresh_for then
                        local value = 1 - age / c.fresh_for - flat_distance(entry.at, at) * c.distance_weight
                        if best == nil or value > best_value then
                            best, best_value = entry, value
                        end
                        if entry.entity == state.target then
                            kept, kept_value = entry, value
                        end
                    end
                end
            end
            local pick = best
            if kept ~= nil and best_value <= kept_value + c.switch_margin then
                pick = kept
            end

            local score = 0
            if pick ~= nil then
                score = c.base_score + c.fresh_weight * (1 - (now - pick.seen_at) / c.fresh_for)
            end
            if score ~= o:get("ai/agent/option").score then
                o:patch({ ["ai/agent/option"] = { score = score } })
            end

            local same = pick ~= nil and state.target == pick.entity and state.at ~= nil
                and state.at.x == pick.at.x and state.at.y == pick.at.y and state.at.z == pick.at.z
            if not same and (pick ~= nil or state.target ~= nil) then
                commands:entity(o:id()):patch({
                    ["ai/behavior/chase/state"] = {
                        target = pick and pick.entity or null,
                        at = pick and pick.at or null,
                    },
                })
            end
        end
    end
end):in_set("ai/behavior/chase/score")

-- Chosen, it goes where its target was last seen, asking again once that has moved far enough. Having
-- caught up is no reason to ask: `ai/steering` has stood it still.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            added = { "ai/agent/chosen" },
            changed = { "ai/behavior/chase/state" },
        },
        with = { "ai/agent/chosen", "ai/behavior/chase/option", "ai/behavior/chase/state", "ai/agent/option" },
    }],
    Query[{
        with = { "ai/behavior/chase", "ai/nav/request" },
        optional = { "ai/steering" },
    }],
    Commands,
}, function(chosen, agents, commands)
    for _, o in ipairs(chosen:iter()) do
        local a = agents:get(o:get("ai/agent/option").entity)
        local to = o:get("ai/behavior/chase/state").at
        if a ~= nil and to ~= nil then
            local c = a:get("ai/behavior/chase")
            local asked = a:get("ai/nav/request").chase
            if asked == nil or flat_distance(asked.to, to) > c.repath_distance then
                commands:entity(a:id()):patch({ ["ai/nav/request"] = { chase = { to = to } } })
            end
            if a:has("ai/steering") and a:get("ai/steering").speed ~= c.speed then
                commands:entity(a:id()):patch({ ["ai/steering"] = { speed = c.speed } })
            end
        end
    end
end):in_set("ai/behavior/chase/act")

-- No longer chosen: it stops asking.
app:add_systems(Update, {
    Query[{
        removed = { "ai/agent/chosen" },
        with = { "ai/behavior/chase/option", "ai/agent/option" },
    }],
    -- Only while `ai/nav` stays: going with it, its request is about to be taken off.
    Query[{ with = { "ai/behavior/chase", "ai/nav", "ai/nav/request" } }],
    Commands,
}, function(unchosen, agents, commands)
    for _, o in ipairs(unchosen:iter()) do
        local a = agents:get(o:get("ai/agent/option").entity)
        if a ~= nil and a:get("ai/nav/request").chase ~= nil then
            commands:entity(a:id()):patch({ ["ai/nav/request"] = { chase = null } })
        end
    end
end):in_set("ai/behavior/chase/exit")

-- No way there: it gives up for a while and lets the agent do something else. Its score falls at its
-- next thought, and no longer chosen, it stops asking.
app:add_systems(Update, {
    Res[Time],
    Query[{
        ["or"] = {
            changed = { "ai/steering/state", "ai/nav/path" },
        },
        with = { "ai/behavior/chase", "ai/agent/options", "ai/nav/request" },
        optional = { "ai/steering/state", "ai/nav/path" },
    }],
    Query[{ with = { "ai/agent/chosen", "ai/behavior/chase/option" } }],
    Commands,
}, function(time, agents, chosen, commands)
    for _, a in ipairs(agents:iter()) do
        local o = chosen:iter_many(a:get("ai/agent/options"))[1]
        local steer = a:get("ai/steering/state")
        local path = a:get("ai/nav/path")
        if o ~= nil and a:get("ai/nav/request").chase ~= nil
            and ((steer ~= nil and steer.status == "blocked") or (path ~= nil and path.status == "unreachable")) then
            commands:entity(o:id()):patch({
                ["ai/behavior/chase/state"] = {
                    target = null,
                    at = null,
                    gave_up_until = time:elapsed_secs() + a:get("ai/behavior/chase").give_up_for,
                },
            })
        end
    end
end):in_set("ai/behavior/chase/give_up")

-- `ai/behavior/chase` was taken off an agent that stays: its option and its asking go.
app:add_systems(First, {
    Query[{
        removed = { "ai/behavior/chase" },
        optional = { "ai/agent/options", "ai/nav", "ai/nav/request" },
    }],
    Query[{ with = { "ai/behavior/chase/option" } }],
    Commands,
}, function(removed, options, commands)
    for _, a in ipairs(removed:iter()) do
        for _, o in ipairs(options:iter_many(a:get("ai/agent/options") or {})) do
            commands:entity(o:id()):try_despawn()
        end
        -- Only while `ai/nav` stays: going with it, its request is about to be taken off, and a
        -- patch landing after that would bring it back.
        local request = a:get("ai/nav/request")
        if a:has("ai/nav") and request ~= nil and request.chase ~= nil then
            commands:entity(a:id()):patch({ ["ai/nav/request"] = { chase = null } })
        end
    end
end):in_set("ai/behavior/chase/removed")

return {
    defaults = {
        ["ai/behavior/chase"] = {
            speed = 5.2,
            base_score = 0.9,
            fresh_weight = 0.1,
            fresh_for = 3,
            distance_weight = 0.02,
            switch_margin = 0.25,
            repath_distance = 2,
            give_up_for = 3,
        },
    },
}
