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

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "camera" } })) do
        local c = e:get("camera")
        e:patch({
            camera = {
                yaw = c.yaw or 0,
                pitch = c.pitch or -0.3,
                distance = c.distance or 8.0,
                height = c.height or 1.5,
                offset = c.offset or { x = 1.0, y = 0, z = 0 },
            },
        })
    end
end, { label = "CameraInit" })
