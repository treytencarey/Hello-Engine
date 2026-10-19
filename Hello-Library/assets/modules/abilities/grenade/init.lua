-- A grenade: a key lobs a small glowing ball along the camera's look; it falls, bounces and
-- ends when its lifetime does, then the grenade cools down for a moment. On the player, it
-- registers itself as an ability (its entry in `abilities`) and removes the entry when it
-- goes. It fires on its own press (`input/game/abilities/grenade` added) when it is not
-- cooling down (`abilities/grenade/cooling`), and spawns an `abilities/projectile` from 1 m
-- above the player; `abilities` starts the cooldown on the same press. Something else
-- starting the cooldown fires nothing. Missing fields get defaults. This component never crosses the
-- network: the server holds it and fires, and the `abilities` entry reaches the owner.
--
-- abilities/grenade = {
--     key = <KeyCode>,
--     cooldown = <seconds>,
--     speed = <m/s>,
--     radius = <metres>,
--     color = { r = <0..1>, g = <0..1>, b = <0..1> },
-- }

register_system("First", function(world)
    for _, e in ipairs(world:query({ changed = { "abilities/grenade" } })) do
        local g = e:get("abilities/grenade")
        if g.key == nil or g.cooldown == nil or g.speed == nil or g.radius == nil or g.color == nil then
            e:patch({
                ["abilities/grenade"] = {
                    key = g.key or "KeyG",
                    cooldown = g.cooldown or 1,
                    speed = g.speed or 20,
                    radius = g.radius or 0.2,
                    color = g.color or { r = 0.4, g = 0.9, b = 0.3 },
                },
            })
        else
            e:patch({ abilities = { grenade = { key = g.key, cooldown = g.cooldown } } })
        end
    end
end, { label = "AbilitiesGrenade" })

register_system("Update", function(world)
    for _, e in ipairs(world:query({
        added = { "input/game/abilities/grenade" },
        with = { "abilities/grenade", "Transform" },
        -- The cooldown `abilities` starts on this same press shows from next frame.
        without = { "abilities/grenade/cooling" },
        optional = { "camera" },
    })) do
        local g = e:get("abilities/grenade")
        local camera = e:get("camera") or {}
        local at = e:get("Transform").translation
        spawn({
            ["abilities/projectile"] = {
                at = { x = at.x, y = at.y + 1, z = at.z },
                yaw = camera.yaw,
                pitch = camera.pitch,
                speed = g.speed,
                radius = g.radius,
                color = g.color,
            },
        })
    end
end, { label = "AbilitiesGrenadeFire" })

-- `abilities/grenade` was taken off an entity that stays: its entry goes.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "abilities/grenade" } })) do
        if world:get_entity(e:id()) then e:patch({ abilities = { grenade = null } }) end
    end
end, { label = "AbilitiesGrenadeRemoved" })
