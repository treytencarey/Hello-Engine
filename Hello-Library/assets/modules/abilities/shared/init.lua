-- A player's abilities, generically: each one has a key and a cooldown, and what it does is a
-- sub-mod's. A press of an ability that is not cooling starts its cooldown, on both sides, so
-- the owner sees it at once. Each ability mod (`abilities/fireball`) fires on its own press
-- while it is not cooling; the cooldown only says when it may fire again, so something else
-- starting it fires nothing. An ability mod registers its entry here and removes it when it
-- goes. Missing fields get defaults.
--
-- abilities = {
--     <name> = {
--         key = <KeyCode>,
--         cooldown = <seconds>,
--     },
-- }
--
-- abilities/<name>/cooling = {}: present while that ability cools down (a `cooldown` timer).
--
-- The press is the input action `input/game/abilities/<name>`.

-- Defaults, and an entry that went loses its cooldown.
register_system("First", function(world)
    for _, e in ipairs(world:query({ changed = { "abilities" }, optional = { "cooldown" } })) do
        local list = e:get("abilities")
        local fill = {}
        for name, a in pairs(list) do
            if a.cooldown == nil then fill[name] = { cooldown = 1 } end
        end
        if next(fill) then e:patch({ abilities = fill }) end
        local stop = {}
        for timer in pairs(e:get("cooldown") or {}) do
            local name = timer:match("^abilities/(.+)/cooling$")
            if name and list[name] == nil then stop[timer] = null end
        end
        if next(stop) then e:patch({ cooldown = stop }) end
    end
end, { label = "AbilitiesInit" })

-- The fire actions this pass reads, as columns from data: each player's ability names.
local function actions(world)
    local names = {}
    for _, e in ipairs(world:query({ with = { "abilities" } })) do
        for name in pairs(e:get("abilities")) do
            names[#names + 1] = "input/game/abilities/" .. name
        end
    end
    return names
end

-- A press starts the ability's cooldown: the ability fires. A press while it cools starts
-- nothing, because `cooldown` never restarts a running timer.
register_system("Update", function(world)
    local names = actions(world)
    if #names == 0 then return end
    for _, e in ipairs(world:query({
        ["or"] = { added = names },
        with = { "abilities" },
    })) do
        local timers = {}
        for name, a in pairs(e:get("abilities")) do
            if e:is_added("input/game/abilities/" .. name) then
                timers["abilities/" .. name .. "/cooling"] = { remaining = a.cooldown }
            end
        end
        if next(timers) then e:patch({ cooldown = timers }) end
    end
end, { label = "AbilitiesCool" })

-- `abilities` was taken off an entity that stays: stop its cooldowns.
register_system("First", function(world)
    for _, e in ipairs(world:query({
        ["or"] = { removed = { "abilities" } },
        optional = { "abilities" },
    })) do
        local timers = {}
        for name in pairs(e:get("abilities") or {}) do
            timers["abilities/" .. name .. "/cooling"] = null
        end
        if next(timers) and world:get_entity(e:id()) then e:patch({ cooldown = timers }) end
    end
end, { label = "AbilitiesRemoved" })

return {
    ["core/net/sync"] = {
        authority = "server",
        target = "owner",
    },
}
