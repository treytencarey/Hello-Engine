-- Walking and jumping. The owning client moves its own body from input, relative to where
-- its camera looks, and turns it to face where it goes; every other client eases its copy
-- toward the synced Transform. The owner drives the Transform until prediction returns with
-- the net rewrite, so the server runs no movement. Missing fields get
-- defaults when it is added.
--
-- movement = {
--     speed = <metres per second>,
--     jump = <metres per second upward>,
--     turn = <how fast it turns to face where it goes, per second>,
--     ground = <metres from its origin to just below its feet>,
--     smoothing = <how fast another client's copy follows, per second>,
-- }
--
-- movement/grounded: on the owner's client while it stands on something.
--
-- It moves its body through `Velocity3d`, which the server does not send: one is added
-- when it is missing, and stays when `movement` goes.

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "movement" }, optional = { "Velocity3d" } })) do
        local m = e:get("movement")
        e:patch({
            movement = {
                speed = m.speed or 6,
                jump = m.jump or 5,
                turn = m.turn or 10,
                ground = m.ground or 1,
                smoothing = m.smoothing or 10,
            },
        })
        if not e:has("Velocity3d") then
            e:patch({ Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } } })
        end
    end
end, { label = "MovementInit" })

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
