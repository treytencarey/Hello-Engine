-- Top-down 2D walking. The owning client moves its own body from input; every other client
-- eases its copy toward the synced Transform. The owner drives the Transform until prediction
-- returns with the net rewrite, so the server runs no movement. Missing fields get defaults
-- when it is added.
--
-- movement/2d = {
--     speed = <pixels per second>,
--     acceleration = <how fast the velocity reaches the keys', per second>,
--     deceleration = <how fast it dies with no key held, per second>,
--     smoothing = <how fast another client's copy follows, per second>,
-- }
--
-- It moves its body through `Velocity2d`, which the server does not send: one is added when
-- it is missing, and stays when `movement/2d` goes.

app:add_systems(First, {
    Query[{
        added = { "movement/2d" },
        without = { "Velocity2d" },
    }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        commands:entity(e:id()):insert({ Velocity2d = { linvel = { x = 0, y = 0 }, angvel = 0 } })
    end
end):in_set("movement/2d/init")

return {
    defaults = {
        ["movement/2d"] = {
            speed = 160,
            acceleration = 14,
            deceleration = 20,
            smoothing = 16,
        },
    },
    ["core/net/sync"] = {
        authority = "server",
    },
}
