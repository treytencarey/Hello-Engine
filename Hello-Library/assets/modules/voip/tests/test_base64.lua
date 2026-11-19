-- test_base64.lua: voip's base64 decoder reads what root's microphone encoder writes. Root's
-- encoder is held here as text, a copy of vault/microphone's base64.lua, and loaded on its own.
--
-- B1  the RFC 4648 vectors decode
-- B2  every byte value, and every length's remainder, comes back from root's encoder unchanged
-- B3  random strings of 0 to 200 bytes come back unchanged
-- B4  text that is not base64 is refused: a length that is not a multiple of 4, a character
--     outside the alphabet, padding before the end
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Base64 = require("modules/voip/client/base64.lua")

local suite = helpers.create_suite("VoipBase64Suite")
local T = suite.assert_test

-- Root's encoder, as vault/microphone/base64.lua has it.
local ROOT_ENCODER = [=[
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DIGIT = {}
for i = 0, 63 do DIGIT[i] = ALPHABET:sub(i + 1, i + 1) end

local M = {}

function M.encode(bytes)
    local byte, out, j, n = string.byte, {}, 0, #bytes
    for i = 1, n - 2, 3 do
        local a, b, c = byte(bytes, i, i + 2)
        local v = (a << 16) | (b << 8) | c
        out[j + 1] = DIGIT[v >> 18]
        out[j + 2] = DIGIT[(v >> 12) & 63]
        out[j + 3] = DIGIT[(v >> 6) & 63]
        out[j + 4] = DIGIT[v & 63]
        j = j + 4
    end
    local rest = n % 3
    if rest == 1 then
        local v = byte(bytes, n) << 16
        out[j + 1], out[j + 2], out[j + 3] = DIGIT[v >> 18], DIGIT[(v >> 12) & 63], "=="
    elseif rest == 2 then
        local a, b = byte(bytes, n - 1, n)
        local v = (a << 16) | (b << 8)
        out[j + 1], out[j + 2], out[j + 3], out[j + 4] = DIGIT[v >> 18], DIGIT[(v >> 12) & 63], DIGIT[(v >> 6) & 63], "="
    end
    return table.concat(out)
end

return M
]=]

app:add_systems(Startup, {}, function()
    local encode = load(ROOT_ENCODER)().encode

    local vectors = { [""] = "", f = "Zg==", fo = "Zm8=", foo = "Zm9v", foob = "Zm9vYg==", fooba = "Zm9vYmE=", foobar = "Zm9vYmFy" }
    local wrong = {}
    for plain, text in pairs(vectors) do
        if Base64.decode(text) ~= plain or encode(plain) ~= text then wrong[#wrong + 1] = plain end
    end
    T("B1_the_rfc_vectors_decode", #wrong == 0, "wrong: " .. table.concat(wrong, ","))

    local all = {}
    for b = 0, 255 do all[#all + 1] = string.char(b) end
    local every = table.concat(all)
    local bad = {}
    for n = 0, 9 do
        local s = every:sub(1, 256 - n)
        if Base64.decode(encode(s)) ~= s then bad[#bad + 1] = tostring(#s) end
    end
    T("B2_every_byte_and_every_remainder_round_trips", #bad == 0, "lengths wrong: " .. table.concat(bad, ","))

    local failures = 0
    for _ = 1, 500 do
        local bytes = {}
        for i = 1, math.random(0, 200) do bytes[i] = string.char(math.random(0, 255)) end
        local s = table.concat(bytes)
        if Base64.decode(encode(s)) ~= s then failures = failures + 1 end
    end
    T("B3_random_strings_round_trip", failures == 0, failures .. " of 500 wrong")

    T("B4_text_that_is_not_base64_is_refused",
        Base64.decode("Zm9") == nil and Base64.decode("Zm9$") == nil and Base64.decode("Zg==Zm9v") == nil
            and Base64.decode("Z===") == nil,
        string.format("short=%s bad char=%s early pad=%s three pads=%s", tostring(Base64.decode("Zm9")),
            tostring(Base64.decode("Zm9$")), tostring(Base64.decode("Zg==Zm9v")), tostring(Base64.decode("Z===") ~= nil)))
    suite.finish("VOIP_BASE64")
end)
