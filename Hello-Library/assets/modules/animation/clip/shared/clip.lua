-- Where a seek puts a clip, for `animation/clip`. Required by path; not a mod file.

local M = {}

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
