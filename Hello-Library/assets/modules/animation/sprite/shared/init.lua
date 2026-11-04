-- A character's 2D sprite animation: its sheet, and the clip it plays for what it is doing.
-- The server states the sheet (synced); each client draws it and picks the clip from what it
-- sees its own copy doing (walking or standing, and which way it last went). Missing fields
-- get defaults when it is added. Nothing is drawn until it names an `image`.
--
-- animation/sprite = {
--     image = <the sheet's path>,
--     tile_size = { x = <pixels>, y = <pixels> },
--     columns = <frames per row of the sheet>,
--     clips = { <state> = { frames = { <frame index>, ... }, fps = <frames per second> }, ... },
--     speed = <what every clip's fps is multiplied by>,
--     scale = <the drawn size, 1 is a pixel per pixel>,
--     z = <how far above the character it is drawn>,
-- }
--
-- A state is `walk_<facing>` or `idle_<facing>`, and `idle` plays for a state with no clip.

return {
    defaults = {
        ["animation/sprite"] = {
            tile_size = { x = 16, y = 16 },
            columns = 1,
            clips = {
                idle = { frames = { 0 }, fps = 1 },
            },
            speed = 1,
            scale = 1,
            z = 1,
        },
    },
}
