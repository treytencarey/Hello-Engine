-- A ray turned into Bevy's picking on a screen, for this client's own player. When the first thing
-- the player's `pointer/ray` meets is a pointer target within `range`, Bevy's picking hears it as
-- the mouse pointer on that target's image: it moves there, scrolls, presses, and a long press is a
-- right click. A ray source writes the ray and has `pointer` as its base: `pointer/view` is the
-- desktop's (the view's centre, or the cursor), `vr/pointer` the VR controller's. While the ray is on
-- a target the wheel is the screen's: the camera does not zoom.
--
-- pointer = {
--     long_press = <seconds a press is held still to be a right click>,
--     long_press_tolerance = <pixels it may move and still count as still>,
--     range = <metres: a target further along the ray is not met>,
-- }
--
-- pointer/ray = { origin = { x, y, z }, direction = { x, y, z } }: in world space, by the source
--
-- pointer/target = { image = <render target handle>, width, height }: on a mesh, by its maker
--
-- pointer/hovered = { x, y }: on the target the ray is on, in its image's pixels
--
-- pointer/press = {
--     at = <elapsed seconds when pressed; absent once it moved too far for a long press>,
--     x, y = <pixels on the target where it was pressed>,
--     long = <true once the long press was sent>,
-- }: on the player while a press that began on a target is held
--
-- Bindings, in `input/game` and `input/ui`: pointer = { press = { button = "Left" }, scroll = { scroll
-- = true } }; the scroll binding takes the wheel (`take = true`) while a target is hovered.

local bevy = require("bevy::prelude")
local MeshRayCast = require("bevy::picking::prelude::MeshRayCast")
local PointerInput = require("bevy::picking::pointer::PointerInput")
local Time = require("bevy::time::Time")

local MODES = { "input/game", "input/ui" }

--- The pointer's group, the wheel taken or not.
local function bindings(take)
    return { press = { button = "Left" }, scroll = { scroll = true, take = take or nil } }
end

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "pointer", "input" },
        },
        with = { "pointer", "input" },
    }],
    Query[{ with = { "pointer/hovered" } }],
    Commands,
}, function(players, hovered, commands)
    -- read now: the change runs after this system, when its parameters are gone
    local take = not hovered:is_empty()
    for _, e in ipairs(players:iter()) do
        for _, mode in ipairs(MODES) do
            commands:entity(e:id()):entry(mode):or_default():and_modify(function(group)
                group.pointer = bindings(take)
            end)
        end
    end
end):in_set("pointer/bind")

-- The edge also comes for a player that despawned. `and_modify` does nothing to a mode that went
-- with `input`, so it cannot bring the bindings back.
app:add_systems(First, {
    Query[{ removed = { "pointer" } }],
    Query[{ with = { "pointer/hovered" } }],
    Commands,
}, function(removed, hovered, commands)
    for _, e in ipairs(removed:iter()) do
        local player = commands:get_entity(e:id())
        if player ~= nil then
            for _, mode in ipairs(MODES) do
                player:entry(mode):and_modify(function(group)
                    group.pointer = nil
                end)
            end
            player:try_remove("pointer/ray", "pointer/press")
        end
        for _, h in ipairs(hovered:iter()) do
            commands:entity(h:id()):try_remove("pointer/hovered")
        end
    end
end):in_set("pointer/removed")

-- The player and what hangs under it (a laser, its body) never stand in the way; anything else
-- does, and only a target answers. A player is a root, so its descendants share its root. Bevy's
-- picking skips a move with no delta, so a ray held still sends none. When the ray leaves a target
-- the pointer leaves its image, off the edge: Bevy's picking presses what the pointer hovers, and
-- only a move moves it, so a hidden cursor's next click would land where it was left. The mouse
-- pointer is reused: a pointer of its own would be `PointerId::Custom`, which Lua cannot build.
app:add_systems(Update, {
    MeshRayCast,
    Query[{
        changed = { "pointer/ray" },
        with = { "pointer" },
        optional = { "input/game/pointer/scroll", "input/ui/pointer/scroll" },
    }],
    Query[{ with = { "pointer/target" } }],
    Query[{ with = { "pointer/hovered", "pointer/target" } }],
    bevy.MessageWriter[PointerInput],
    Commands,
}, function(ray_cast, players, targets, hovered, pointer, commands)
    for _, e in ipairs(players:iter()) do
        local me = e:id()
        local hit = ray_cast:cast_ray(e:get("pointer/ray"), {
            filter = function(entity)
                return players:root_ancestor(entity) ~= me
            end,
        })[1]
        if hit ~= nil and (not targets:contains(hit.entity) or hit.ray_mesh_hit.distance > e:get("pointer").range) then
            hit = nil
        end
        local was = hovered:iter()[1]
        if was ~= nil and (hit == nil or was:id() ~= hit.entity) then
            commands:entity(was:id()):try_remove("pointer/hovered")
            pointer:write({
                pointer_id = "Mouse",
                location = { target = { Image = was:get("pointer/target").image }, position = { x = -1, y = -1 } },
                action = { Move = { delta = { x = -0.001, y = -0.001 } } },
            })
        end
        local uv = hit and hit.ray_mesh_hit.uv
        if uv ~= nil then
            local target = targets:get(hit.entity):get("pointer/target")
            local x, y = uv.x * target.width, uv.y * target.height
            local before = was ~= nil and was:id() == hit.entity and was:get("pointer/hovered") or nil
            local location = { target = { Image = target.image }, position = { x = x, y = y } }
            if before == nil or before.x ~= x or before.y ~= y then
                pointer:write({
                    pointer_id = "Mouse",
                    location = location,
                    action = { Move = { delta = before and { x = x - before.x, y = y - before.y } or { x = 0.001, y = 0.001 } } },
                })
                commands:entity(hit.entity):insert({ ["pointer/hovered"] = { x = x, y = y } })
            end
            local scroll = e:get("input/game/pointer/scroll") or e:get("input/ui/pointer/scroll")
            if scroll ~= nil then
                pointer:write({
                    pointer_id = "Mouse",
                    location = location,
                    action = { Scroll = { unit = "Line", x = scroll.dx, y = scroll.dy } },
                })
            end
        end
        -- The wheel is the screen's while the ray is on one: its scroll binding takes it.
        if (was == nil) ~= (uv == nil) then
            local take = uv ~= nil
            for _, mode in ipairs(MODES) do
                commands:entity(me):entry(mode):and_modify(function(group)
                    if group.pointer ~= nil then group.pointer = bindings(take) end
                end)
            end
        end
    end
end):in_set("pointer/cast")

-- A release after a long press sends no primary release, so the press does not also click.
app:add_systems(Update, {
    Res[Time],
    Query[{
        ["or"] = { added = { "input/game/pointer/press", "input/ui/pointer/press" } },
        with = { "pointer" },
    }],
    Query[{
        ["or"] = { removed = { "input/game/pointer/press", "input/ui/pointer/press" } },
        with = { "pointer/press" },
    }],
    Query[{ with = { "pointer/hovered", "pointer/target" } }],
    bevy.MessageWriter[PointerInput],
    Commands,
}, function(time, pressed, released, hovered, pointer, commands)
    local on = hovered:iter()[1]
    local location = nil
    if on ~= nil then
        local at = on:get("pointer/hovered")
        location = { target = { Image = on:get("pointer/target").image }, position = { x = at.x, y = at.y } }
    end
    for _, e in ipairs(pressed:iter()) do
        if location ~= nil then
            pointer:write({ pointer_id = "Mouse", location = location, action = { Press = "Primary" } })
            commands:entity(e:id()):insert({
                ["pointer/press"] = {
                    at = time:elapsed_secs(),
                    x = location.position.x,
                    y = location.position.y,
                    long = false,
                },
            })
        end
    end
    for _, e in ipairs(released:iter()) do
        if location ~= nil and not e:get("pointer/press").long then
            pointer:write({ pointer_id = "Mouse", location = location, action = { Release = "Primary" } })
        end
        commands:entity(e:id()):try_remove("pointer/press")
    end
end):in_set("pointer/press"):after("pointer/cast")

-- Timed, so it polls while a press is held.
app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "pointer", Mut["pointer/press"] } }],
    Query[{ with = { "pointer/hovered", "pointer/target" } }],
    bevy.MessageWriter[PointerInput],
}, function(time, holding, hovered, pointer)
    local on = hovered:iter()[1]
    for _, e in ipairs(holding:iter_mut()) do
        local p = e:get("pointer")
        local press = e:get_mut("pointer/press")
        if on ~= nil and press.at ~= nil and not press.long then
            local at = on:get("pointer/hovered")
            if math.sqrt((at.x - press.x) ^ 2 + (at.y - press.y) ^ 2) > p.long_press_tolerance then
                press.at = nil
            elseif time:elapsed_secs() - press.at >= p.long_press then
                local location = { target = { Image = on:get("pointer/target").image }, position = { x = at.x, y = at.y } }
                pointer:write({ pointer_id = "Mouse", location = location, action = { Press = "Secondary" } })
                pointer:write({ pointer_id = "Mouse", location = location, action = { Release = "Secondary" } })
                press.long = true
            end
        end
    end
end):in_set("pointer/long_press"):after("pointer/press")

return {
    defaults = {
        pointer = {
            long_press = 0.5,
            long_press_tolerance = 15,
            range = 3,
        },
    },
}
