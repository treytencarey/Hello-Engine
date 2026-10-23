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

local app = ...

-- Defaults, and an entry that went loses its cooldown.
app:add_systems(First, {
    Query[{
        changed = { "abilities" },
        optional = { "cooldown" },
    }],
    Commands,
}, function(players, commands)
    for _, e in ipairs(players:iter()) do
        local list = e:get("abilities")
        local entity = commands:entity(e:id())
        local fill = {}
        for name, a in pairs(list) do
            if a.cooldown == nil then fill[name] = { cooldown = 1 } end
        end
        if next(fill) then entity:patch({ abilities = fill }) end
        local stop = {}
        for timer in pairs(e:get("cooldown") or {}) do
            local name = timer:match("^abilities/(.+)/cooling$")
            if name and list[name] == nil then stop[timer] = null end
        end
        if next(stop) then entity:patch({ cooldown = stop }) end
    end
end):in_set("abilities/init")

-- A press starts the ability's cooldown: the ability fires. A press while it cools starts
-- nothing, because `cooldown` never restarts a running timer. The fire actions it reads are
-- columns from data: each player's ability names.
app:add_systems(Update, {
    Query[{ with = { "abilities" } }],
    Commands,
}, function(players, commands)
    local names = {}
    for _, e in ipairs(players:iter()) do
        for name in pairs(e:get("abilities")) do
            names[#names + 1] = "input/game/abilities/" .. name
        end
    end
    if #names == 0 then return end
    for _, e in ipairs(players:with_columns({ ["or"] = { added = names } }):iter()) do
        local timers = {}
        for name, a in pairs(e:get("abilities")) do
            if e:is_added("input/game/abilities/" .. name) then
                timers["abilities/" .. name .. "/cooling"] = { remaining = a.cooldown }
            end
        end
        if next(timers) then commands:entity(e:id()):patch({ cooldown = timers }) end
    end
end):in_set("abilities/cool")

-- `abilities` was taken off an entity that stays: stop its cooldowns. A despawned player is in
-- the `removed` rows too.
app:add_systems(First, {
    Query[{
        ["or"] = { removed = { "abilities" } },
        optional = { "abilities" },
    }],
    Query[{ with = { "cooldown" } }],
    Commands,
}, function(removed, timed, commands)
    for _, e in ipairs(removed:iter()) do
        local timers = {}
        for name in pairs(e:get("abilities") or {}) do
            timers["abilities/" .. name .. "/cooling"] = null
        end
        if next(timers) and timed:contains(e:id()) then
            commands:entity(e:id()):patch({ cooldown = timers })
        end
    end
end):in_set("abilities/removed")

return {
    ["core/net/sync"] = {
        authority = "server",
        target = "owner",
    },
}
