-- A fireball: a key fires a glowing ball straight along the camera's look; it does not fall
-- or bounce, and it explodes on the first thing it touches other than its caster
-- (`projectile/caster`). Then the fireball cools down for a moment. On the player, it
-- registers itself as an ability (its entry in `abilities`) and removes the entry when it
-- goes. It fires on its own press (`input/game/abilities/fireball` added) when it is not
-- cooling down (`abilities/fireball/cooling`), spawning, from 1 m above the player, an
-- `abilities/projectile` with no gravity that explodes on contact (`projectile/explode`);
-- `abilities` starts the cooldown on the same press. Something else starting the cooldown
-- fires nothing.
-- Missing fields get defaults. This component never crosses the network: the server holds
-- it and fires, and the `abilities` entry reaches the owner.
--
-- abilities/fireball = {
--     key = <KeyCode>,
--     cooldown = <seconds>,
--     speed = <m/s>,
--     radius = <metres>,
--     blast = <the explosion's radius, metres>,
--     color = { r = <0..1>, g = <0..1>, b = <0..1> },
-- }

app:add_systems(First, {
    Query[{ changed = { "abilities/fireball" } }],
    Commands,
}, function(players, commands)
    for _, e in ipairs(players:iter()) do
        local f = e:get("abilities/fireball")
        if f.key == nil or f.cooldown == nil or f.speed == nil or f.radius == nil
            or f.blast == nil or f.color == nil then
            commands:entity(e:id()):patch({
                ["abilities/fireball"] = {
                    key = f.key or "KeyQ",
                    cooldown = f.cooldown or 1,
                    speed = f.speed or 25,
                    radius = f.radius or 0.25,
                    blast = f.blast or 1.5,
                    color = f.color or { r = 1, g = 0.3, b = 0.1 },
                },
            })
        else
            commands:entity(e:id()):patch({ abilities = { fireball = { key = f.key, cooldown = f.cooldown } } })
        end
    end
end):in_set("abilities/fireball")

app:add_systems(Update, {
    Query[{
        added = { "input/game/abilities/fireball" },
        with = { "abilities/fireball", "Transform" },
        -- The cooldown `abilities` starts on this same press shows from next frame.
        without = { "abilities/fireball/cooling" },
        optional = { "camera" },
    }],
    Commands,
}, function(pressed, commands)
    for _, e in ipairs(pressed:iter()) do
        local f = e:get("abilities/fireball")
        local camera = e:get("camera") or {}
        local at = e:get("Transform").translation
        commands:spawn({
            ["abilities/projectile"] = {
                at = { x = at.x, y = at.y + 1, z = at.z },
                yaw = camera.yaw,
                pitch = camera.pitch,
                speed = f.speed,
                radius = f.radius,
                gravity = 0,
                lifetime = 5,
                color = f.color,
            },
            ["projectile/explode"] = { radius = f.blast, color = f.color },
            ["projectile/caster"] = { entity = e:id() },
            -- Every client tells its own hit from its caster from the first frame, so the
            -- caster rides the projectile's first spawn.
            ["core/net/sync"] = { ["projectile/caster"] = { authority = "server" } },
        })
    end
end):in_set("abilities/fireball/fire")

-- `abilities/fireball` was taken off an entity that stays: its entry goes. A despawned player
-- is in the `removed` rows too.
app:add_systems(First, {
    Query[{ removed = { "abilities/fireball" } }],
    Query[{ with = { "abilities" } }],
    Commands,
}, function(removed, players, commands)
    for _, e in ipairs(removed:iter()) do
        if players:contains(e:id()) then
            commands:entity(e:id()):patch({ abilities = { fireball = null } })
        end
    end
end):in_set("abilities/fireball/removed")
