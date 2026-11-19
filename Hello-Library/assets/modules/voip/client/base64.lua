-- voip's base64 decoder (RFC 4648, with padding), for the frames root's microphone encodes.
-- Stateless.

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE = {}
for i = 1, 64 do VALUE[ALPHABET:byte(i)] = i - 1 end

local M = {}

--- The bytes `text` holds, or nil when it is not base64.
function M.decode(text)
    local n = #text
    if n % 4 ~= 0 then return nil end
    local byte, char, out, j = string.byte, string.char, {}, 0
    for i = 1, n, 4 do
        local a, b, c, d = byte(text, i, i + 3)
        local va, vb = VALUE[a], VALUE[b]
        if va == nil or vb == nil then return nil end
        local v = (va << 18) | (vb << 12)
        if d == 61 then
            -- '=' pads only the last group: one for two bytes, two for one.
            if i + 3 ~= n then return nil end
            if c == 61 then
                j = j + 1
                out[j] = char(v >> 16)
            else
                local vc = VALUE[c]
                if vc == nil then return nil end
                v = v | (vc << 6)
                j = j + 1
                out[j] = char(v >> 16, (v >> 8) & 255)
            end
        else
            local vc, vd = VALUE[c], VALUE[d]
            if vc == nil or vd == nil then return nil end
            v = v | (vc << 6) | vd
            j = j + 1
            out[j] = char(v >> 16, (v >> 8) & 255, v & 255)
        end
    end
    return table.concat(out)
end

return M
