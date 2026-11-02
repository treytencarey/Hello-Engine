-- A camera's view state. Camera mods (first_person, third_person, 2d, vr) extend it
-- and drive it; movement reads the yaw. Fields missing when it is added get defaults,
-- and state carried from another world is kept.
--
-- camera = {
--     yaw = <radians>,
--     pitch = <radians>,
--     distance = <metres from the target>,
--     height = <metres above the target>,
--     offset = { x = <metres>, y = <metres>, z = <metres> },
-- }

return {
    defaults = {
        camera = {
            yaw = 0,
            pitch = -0.3,
            distance = 8.0,
            height = 1.5,
            offset = { x = 1.0, y = 0, z = 0 },
        },
    },
}
