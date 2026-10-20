-- A character's skeletal animation: its model, and the clip it plays for what it is doing.
-- The server states the model (synced); each client draws it and picks the clip from what it
-- sees its own copy doing (walking, jumping, falling, standing). A mod that plays something
-- on purpose (a cast, an emote) writes `animation/action`, which wins while it is there and
-- syncs as that mod declares. Missing fields get defaults when it is added.
--
-- animation = {
--     model = <path prefix of the model's files>,
--     scene = <suffix of the file and label of its scene>,
--     clips = { idle = <suffix>, walk = <suffix>, jump = <suffix>, fall = <suffix>, ... },
--     walk_speed = <m/s at which the walk clip plays at its own speed>,
--     offset = { x = <metres>, y = <metres>, z = <metres> },
-- }
--
-- animation/action = { state = <a clip's name>, speed = <playback speed> }: written by
-- another mod; while present it is played instead of the motion's state.

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "animation" } })) do
        local a = e:get("animation")
        if a.model == nil or a.scene == nil or a.clips == nil or a.walk_speed == nil or a.offset == nil then
            e:patch({
                animation = {
                    model = a.model or "Placeholder-Character/Model",
                    scene = a.scene or "-Idle.glb#Scene0",
                    clips = a.clips or {
                        idle = "-Idle.glb#Animation0",
                        walk = "-Walk.glb#Animation0",
                        jump = "-Jump.glb#Animation0",
                        fall = "-Jump.glb#Animation0",
                    },
                    walk_speed = a.walk_speed or 6,
                    offset = a.offset or { x = 0, y = -0.9, z = 0 },
                },
            })
        end
    end
end, { label = "AnimationInit" })
