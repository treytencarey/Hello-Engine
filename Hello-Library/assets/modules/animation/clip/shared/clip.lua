-- What both halves of `animation/clip` need of a clip: the asset it names, and where a seek puts
-- it. Required by path; not a mod file.

local M = {}

--- The asset a clip names, or nil. An animation named in the node's own glTF resolves here once
--- a glTF's animations can be read; until then a name plays nothing.
function M.resolve(clip)
    if clip:find("#", 1, true) then return clip end
    return nil
end

--- Where `to` (seconds, or "end") puts a clip `duration` seconds long, within its length. Nil
--- while the length is not known.
function M.place(to, duration)
    if duration == nil then return nil end
    if to == "end" then return duration end
    return math.max(0, math.min(to, duration))
end

--- The length of the longest clip the node names with a weight, from the loaded clips; nil while
--- one of them has not loaded.
function M.length(wanted, clips, asset_server)
    local longest = 0
    for clip, weight in pairs(wanted.clips or {}) do
        local path = M.resolve(clip)
        if path and weight > 0 then
            local asset = clips:get(asset_server:load(path))
            if asset == nil then return nil end
            longest = math.max(longest, asset.duration)
        end
    end
    return longest
end

return M
