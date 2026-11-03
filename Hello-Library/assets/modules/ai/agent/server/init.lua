-- What makes an entity an agent: a memory, a clock it thinks by, and a choice among the options
-- linked to it. Behaviours are separate mods: each spawns an option entity linked by `ai/agent/option`
-- and keeps its score current, and this mod puts `ai/agent/chosen` on the highest. It names none of
-- them. An archetype brings it, as its base.
--
-- ai/agent = {
--     think_hz = <how many times a second it thinks>,
--     hysteresis = <how far, as a share, another option must beat the chosen one>,
-- }
--
-- ai/agent/memory = {
--     seen = { { entity, at = { x, y, z }, seen_at }, ... }: written by `ai/perception`,
--     sound = { { at = { x, y, z }, heard_at }, ... }: written by `ai/perception`'s hearing,
-- }
--
-- ai/agent/tick = { n, next_at }: `n` moves each time it thinks
--
-- ai/agent/option = { entity = <the agent>, score }: on an option entity
-- ai/agent/options: the options of an agent, kept by the engine
-- ai/agent/chosen: on the option entity that is chosen, while it is

local Time = require("bevy::time::Time")

-- Each agent starts its clock at a random point of its interval, so a batch spawned on one frame
-- never all think on one frame. A reload runs this again, and what it has learned stays.
app:add_systems(First, {
    Res[Time],
    Query[{
        added = { "ai/agent" },
        optional = { "ai/agent/memory", "ai/agent/tick" },
    }],
    Commands,
}, function(time, added, commands)
    for _, e in ipairs(added:iter()) do
        local entity = commands:entity(e:id())
        if not e:has("ai/agent/memory") then
            entity:insert({ ["ai/agent/memory"] = { seen = {}, sound = {} } })
        end
        if not e:has("ai/agent/tick") then
            entity:insert({
                ["ai/agent/tick"] = { n = 0, next_at = time:elapsed_secs() + math.random() / e:get("ai/agent").think_hz },
            })
        end
    end
end):in_set("ai/agent/init")

-- Timed, so it polls.
app:add_systems(First, {
    Res[Time],
    Query[{ with = { "ai/agent", Mut["ai/agent/tick"] } }],
}, function(time, agents)
    local now = time:elapsed_secs()
    for _, e in ipairs(agents:iter_mut()) do
        local tick = e:get("ai/agent/tick")
        if now >= tick.next_at then
            e:patch({ ["ai/agent/tick"] = { n = tick.n + 1, next_at = now + 1 / e:get("ai/agent").think_hz } })
        end
    end
end):in_set("ai/agent/clock")

-- PostUpdate, after the options' scores are written in Update. The highest score over 0 is chosen,
-- and with none nothing is. Between equals the chosen one stays, else the first linked wins. Another
-- must beat the chosen one by `hysteresis`, so two near equals don't swap at every thought.
app:add_systems(PostUpdate, {
    Query[{ changed = { "ai/agent/option" } }],
    Query[{
        changed = { "ai/agent/options" },
        with = { "ai/agent" },
    }],
    Query[{ with = { "ai/agent", "ai/agent/options" } }],
    Query[{
        with = { "ai/agent/option" },
        optional = { "ai/agent/chosen" },
    }],
    Commands,
}, function(rescored, relinked, agents, options, commands)
    local list = {}
    for _, o in ipairs(rescored:iter()) do
        list[#list + 1] = o:get("ai/agent/option").entity
    end
    for _, a in ipairs(relinked:iter()) do
        list[#list + 1] = a:id()
    end
    for _, a in ipairs(agents:iter_many(list)) do
        local chosen, best, best_score = nil, nil, 0
        for _, o in ipairs(options:iter_many(a:get("ai/agent/options"))) do
            local score = o:get("ai/agent/option").score
            if o:has("ai/agent/chosen") then
                chosen = o
            end
            if score > best_score then
                best, best_score = o, score
            end
        end

        local stays = 0
        if chosen ~= nil then
            stays = chosen:get("ai/agent/option").score
        end
        local winner = chosen
        if stays <= 0 then
            winner = best
        elseif best ~= nil and best_score > stays * (1 + a:get("ai/agent").hysteresis) then
            winner = best
        end

        if winner == nil or chosen == nil or winner:id() ~= chosen:id() then
            if chosen ~= nil then
                commands:entity(chosen:id()):try_remove("ai/agent/chosen")
            end
            if winner ~= nil then
                commands:entity(winner:id()):try_insert({ ["ai/agent/chosen"] = {} })
            end
        end
    end
end):in_set("ai/agent/choose")

-- `ai/agent` was taken off an entity that stays: nothing is chosen for it now.
app:add_systems(First, {
    Query[{
        removed = { "ai/agent" },
        with = { "ai/agent/options" },
    }],
    Query[{ with = { "ai/agent/chosen" } }],
    Commands,
}, function(removed, chosen, commands)
    for _, a in ipairs(removed:iter()) do
        for _, o in ipairs(chosen:iter_many(a:get("ai/agent/options"))) do
            commands:entity(o:id()):try_remove("ai/agent/chosen")
        end
    end
end):in_set("ai/agent/removed")

return {
    defaults = {
        ["ai/agent"] = {
            think_hz = 5,
            hysteresis = 0.15,
        },
    },
    relationships = {
        ["ai/agent/option"] = { target = "ai/agent/options", linked_spawn = true },
    },
}
