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

app:add_systems(First, {
    Query[{ changed = { "abilities/grenade" } }],
    Commands,
}, function(players, commands)
    for _, e in ipairs(players:iter()) do
        local g = e:get("abilities/grenade")
        commands:entity(e:id()):patch({ abilities = { grenade = { key = g.key, cooldown = g.cooldown } } })
    end
end):in_set("abilities/grenade/init")

app:add_systems(Update, {
    Query[{
        added = { "input/game/abilities/grenade" },
        with = { "abilities/grenade", "Transform" },
        -- The cooldown `abilities` starts on this same press shows from next frame.
        without = { "abilities/grenade/cooling" },
        optional = { "camera" },
    }],
    Commands,
}, function(pressed, commands)
    for _, e in ipairs(pressed:iter()) do
        local g = e:get("abilities/grenade")
        local camera = e:get("camera") or {}
        local at = e:get("Transform").translation
        commands:spawn({
            ["abilities/projectile"] = {
                at = { x = at.x, y = at.y + 1, z = at.z },
                yaw = camera.yaw,
                pitch = camera.pitch,
                speed = g.speed,
                radius = g.radius,
                color = g.color,
            },
            ["core/script/owner"] = false,
        })
    end
end):in_set("abilities/grenade/fire")

-- `abilities/grenade` was taken off an entity that stays: its entry goes. A despawned player
-- is in the `removed` rows too.
app:add_systems(First, {
    Query[{ removed = { "abilities/grenade" } }],
    Query[{ with = { "abilities" } }],
    Commands,
}, function(removed, players, commands)
    for _, e in ipairs(removed:iter()) do
        if players:contains(e:id()) then
            commands:entity(e:id()):patch({ abilities = { grenade = null } })
        end
    end
end):in_set("abilities/grenade/removed")

return {
    defaults = {
        ["abilities/grenade"] = {
            key = "KeyG",
            cooldown = 1,
            speed = 20,
            radius = 0.2,
            color = { r = 0.4, g = 0.9, b = 0.3 },
        },
    },
}
