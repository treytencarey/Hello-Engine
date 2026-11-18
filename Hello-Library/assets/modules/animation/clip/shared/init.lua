-- Clips playing on a node, both sides: the defaults. The client plays them; the server runs their
-- clock for what it drives.
--
-- animation/clip = {
--     clips = { [<clip>] = <weight>, ... },
--     speed = <1 plays forward, -1 backward, 0 pauses; any other value scales>,
--     repeat = <true loops; false holds the end it reaches>,
-- }
-- animation/clip/seek = { to = <seconds of clip time, within its length, or "end"> }

return {
    defaults = {
        ["animation/clip"] = {
            clips = {},
            speed = 1,
            ["repeat"] = false,
        },
    },
}
