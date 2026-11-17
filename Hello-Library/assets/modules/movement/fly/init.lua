-- Flight for the local player, with no-clip beside it: F turns flight on and off, and while it is
-- on the body has no gravity, Space climbs and ShiftLeft sinks, at movement's speed. No-clip makes
-- the body's collider a sensor, so walls and floors don't stop it; it needs flight. Both are items
-- in the sidebar's menu too. Only a world that adds it to its player has it.
--
-- movement/fly = {
--     on = <whether it flies>,
--     noclip = <whether it passes through walls and floors; only while it flies>,
-- }
--
-- movement/fly/item = {
--     field = <"on" or "noclip": the field a click on this menu item flips>,
-- }

local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")

-- No-clip needs flight: a flip that leaves no-clip on without flight carries the other field with
-- it, so no-clip turned on turns flight on, and flight turned off turns no-clip off.
local function flip(fly, field)
    fly[field] = not fly[field]
    if fly.noclip and not fly.on then
        fly.on, fly.noclip = fly[field], fly[field]
    end
end

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "movement/fly", "core/net/local", "input" },
        },
        with = { "movement/fly", "core/net/local", "input" },
    }],
    Commands,
}, function(owned, commands)
    for _, e in ipairs(owned:iter()) do
        commands:entity(e:id()):entry("input/game"):or_default():and_modify(function(game)
            game.fly = {
                toggle = { key = "KeyF" },
                up = { key = "Space" },
                down = { key = "ShiftLeft" },
            }
        end)
    end
end):in_set("movement/fly")

-- `movement/fly` was taken off: take off what it added, as its last value says, and unbind unless
-- `input` went too, as its bindings go with it. Taken off while it flies, the scale can only go back
-- to 1: rapier ignores its removal. The edge also comes for a player that despawned, which
-- `try_remove` leaves alone and which has no row in `scaled` or `bound`.
app:add_systems(First, {
    Query[{
        ["or"] = {
            removed = { "movement/fly" },
        },
        optional = { "movement/fly" },
    }],
    Query[{ with = { Mut["GravityScale3d"] } }],
    Query[{ with = { "input", "input/game" } }],
    Commands,
}, function(removed, scaled, bound, commands)
    local gone, flying = {}, {}
    for _, e in ipairs(removed:iter()) do
        local was = e:get("movement/fly") or {}
        if was.on then
            flying[#flying + 1] = e:id()
        else
            commands:entity(e:id()):try_remove("GravityScale3d")
        end
        if was.noclip then
            commands:entity(e:id()):try_remove("Sensor3d")
        end
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(scaled:iter_many_mut(flying)) do
        e:get_mut("GravityScale3d"):set_if_neq(1)
    end
    for _, e in ipairs(bound:iter_many(gone)) do
        commands:entity(e:id()):entry("input/game"):and_modify(function(game)
            game.fly = nil
        end)
    end
end):in_set("movement/fly")

app:add_systems(Update, {
    Query[{
        added = { "input/game/fly/toggle" },
        with = { Mut["movement/fly"], "core/net/local" },
    }],
}, function(toggled)
    for _, e in ipairs(toggled:iter_mut()) do
        flip(e:get_mut("movement/fly"), "on")
    end
end):in_set("movement/fly")

-- No gravity while it flies, and a sensor while it passes through. With flight off the scale goes
-- back to 1 and stays: rapier applies `GravityScale3d` only when it changes and ignores its
-- removal, so a body it is taken from keeps no gravity.
app:add_systems(Update, {
    Query[{
        changed = { "movement/fly" },
        optional = { Mut["GravityScale3d"], "Sensor3d" },
    }],
    Commands,
}, function(changed, commands)
    for _, e in ipairs(changed:iter_mut()) do
        local fly = e:get("movement/fly")
        local entity = commands:entity(e:id())
        if e:has("GravityScale3d") then
            e:get_mut("GravityScale3d"):set_if_neq(fly.on and 0 or 1)
        elseif fly.on then
            entity:insert({ GravityScale3d = { value = 0 } })
        end
        if fly.noclip and not e:has("Sensor3d") then
            entity:insert({ Sensor3d = {} })
        elseif not fly.noclip and e:has("Sensor3d") then
            entity:remove("Sensor3d")
        end
    end
end):in_set("movement/fly")

-- Polls while it flies, after movement's own writes: a grounded jump's vertical velocity is replaced,
-- and a ceiling or a floor that stops the body doesn't stop it climbing or sinking again.
app:add_systems(Update, {
    Query[{
        with = { "movement/fly", "movement", "core/net/local", Mut["Velocity3d"] },
        optional = { "input/game/fly/up", "input/game/fly/down" },
    }],
}, function(fliers)
    for _, e in ipairs(fliers:iter_mut()) do
        local fly = e:get("movement/fly")
        if fly.on then
            local m = e:get("movement")
            local up = e:get("input/game/fly/up")
            local down = e:get("input/game/fly/down")
            e:get_mut("Velocity3d").linvel.y = m.speed * ((up and up.value or 0) - (down and down.value or 0))
        end
    end
end):in_set("movement/fly"):after("movement/walk"):after("movement/jump")

-- The items go in the menu's list for a local player with flight: on a new list (the menu opened,
-- or reloaded), and on the carrier itself (added, or this mod reloaded). Each shows its field.
app:add_systems(Update, {
    Query[{ with = { "movement/fly", "core/net/local" } }],
    Query[{
        with = { "sidebar/menu/list" },
        optional = { "Children" },
    }],
    Query[{ with = { "movement/fly/item" } }],
    Commands,
}, function(carriers, lists, items, commands)
    local carrier = carriers:iter()[1]
    if carrier ~= nil then
        local fly = carrier:get("movement/fly")
        for _, list in ipairs(lists:iter()) do
            local children = list:get("Children") or {}
            if items:iter_many(children)[1] == nil then
                local flight = commands:spawn({
                    ["sidebar/menu/item"] = { title = "Flight", order = 2, on = fly.on },
                    ["movement/fly/item"] = { field = "on" },
                    ChildOf = list:id(),
                })
                local noclip = commands:spawn({
                    ["sidebar/menu/item"] = { title = "No-clip", order = 3, on = fly.noclip },
                    ["movement/fly/item"] = { field = "noclip" },
                    ChildOf = list:id(),
                })
                for _, item in ipairs({ flight, noclip }) do
                    item:observe(On[Pointer[Click]], {
                        Query[{ with = { "movement/fly/item" } }],
                        Query[{ with = { Mut["movement/fly"], "core/net/local" } }],
                    }, function(event, clicked, fliers)
                        local row = clicked:get(event.entity)
                        if row ~= nil then
                            local field = row:get("movement/fly/item").field
                            for _, e in ipairs(fliers:iter_mut()) do
                                flip(e:get_mut("movement/fly"), field)
                            end
                        end
                    end)
                end
            end
        end
    end
end):in_set("movement/fly"):run_if({
    Query[{ added = { "sidebar/menu/list" } }],
    Query[{
        ["or"] = {
            added = { "movement/fly", "core/net/local" },
        },
        with = { "movement/fly", "core/net/local" },
    }],
}, function(new_lists, new_carriers)
    return not new_lists:is_empty() or not new_carriers:is_empty()
end)

-- The items show the state, which lives on the player.
app:add_systems(Update, {
    Query[{
        changed = { "movement/fly" },
        with = { "core/net/local" },
    }],
    Query[{ with = { "movement/fly/item", Mut["sidebar/menu/item"] } }],
}, function(changed, items)
    for _, e in ipairs(changed:iter()) do
        local fly = e:get("movement/fly")
        for _, item in ipairs(items:iter_mut()) do
            local field = item:get("movement/fly/item").field
            item:get_mut("sidebar/menu/item").on = fly[field]
        end
    end
end):in_set("movement/fly")

return {
    defaults = {
        ["movement/fly"] = {
            on = false,
            noclip = false,
        },
    },
}
