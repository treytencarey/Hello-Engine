-- What a console reads of a door on either side: the door's authored `scope/portal`, as its scene's
-- custom properties hold it. Stateless.

local json = require("modules/core/dkjson.lua")

local M = {}

--- The door's `scope/portal` as its scene authored it, or nil for a door no scene authored. A row
--- that names `GltfExtras` reads it; the explicit nil metatables keep dkjson's tables plain.
function M.authored(door)
    if not door:has("GltfExtras") then return nil end
    local extras = door:get("GltfExtras")
    local decoded = json.decode(extras.value or "", 1, nil, nil, nil)
    local value = type(decoded) == "table" and decoded["scope/portal"] or nil
    if type(value) == "string" then
        value = json.decode(value, 1, nil, nil, nil)
    end
    return type(value) == "table" and value or nil
end

return M
