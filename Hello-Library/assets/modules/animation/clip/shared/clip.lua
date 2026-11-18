-- What `animation/clip` needs of a clip: the asset it names, and where a seek puts
-- it. Required by path; not a mod file.

local M = {}

--- The asset a clip names, or nil. An animation named in the node's own glTF resolves here once
--- a glTF's animations can be read; until then a name plays nothing.
function M.resolve(clip)
    if clip:find("#", 1, true) then return clip end
    return nil
end

-- How far short of its length a clip's end is placed: Bevy wraps a clip standing at its length back
-- to 0 when it does not move on (paused), so a door paused at its end showed shut (measured).
local SHORT_OF_END = 1e-4

--- Where `to` (seconds, or "end") puts a clip `duration` seconds long, within its length. Nil
--- while the length is not known.
function M.place(to, duration)
    if duration == nil then return nil end
    local last = math.max(0, duration - SHORT_OF_END)
    if to == "end" then return last end
    return math.max(0, math.min(to, last))
end

return M
