-- --host (windowed: a headless run has no font loader)
-- ui/style's font: the theme's `font` on every text, styled or not.
--
--   SF1 a styled text and a plain one get the theme's font, and each keeps its own size
--   SF2 a text spawned later, and a span under it, get it too
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("StyleFontSuite")
local T = suite.assert_test

local FONT = "fonts/DejaVuSans.ttf"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ ["ui/theme/dark"] = {} })
    commands:spawn({ ["zz/text"] = { name = "styled" }, Node = {}, Text = "styled · ⚠", ["ui/style"] = { text = "text" } })
    commands:spawn({ ["zz/text"] = { name = "plain" }, Node = {}, Text = "plain ▼ ●", TextFont = { font_size = 9 } })
end)

local function font_of(world, name)
    for _, e in ipairs(world:query({ with = { "zz/text", "TextFont" } })) do
        if e:get("zz/text").name == name then return e:get("TextFont") end
    end
end

local function show(f) return f and (tostring(f.font) .. " @" .. tostring(f.font_size)) or "none" end

local phase, clock = "loading", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "loading" and clock > 0.5 then
        local styled, plain = font_of(world, "styled"), font_of(world, "plain")
        T("SF1_styled_and_plain_text_get_the_themes_font_and_keep_their_size",
            styled and plain and tostring(styled.font) == FONT and tostring(plain.font) == FONT
                and styled.font_size == 20 and plain.font_size == 9,
            "styled " .. show(styled) .. ", plain " .. show(plain))
        local later = commands:spawn({ ["zz/text"] = { name = "later" }, Node = {}, Text = "later … " }):id()
        commands:spawn({ ["zz/text"] = { name = "span" }, TextSpan = "span ·", ChildOf = later })
        step("later")

    elseif phase == "later" and clock > 0.3 then
        local later, span = font_of(world, "later"), font_of(world, "span")
        T("SF2_a_later_text_and_its_span_get_it_too",
            later and span and tostring(later.font) == FONT and tostring(span.font) == FONT,
            "later " .. show(later) .. ", span " .. show(span))
        phase = "done"
        suite.finish("StyleFontSuite")
    end

    if phase ~= "done" and clock > 10 then
        T("SF0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("StyleFontSuite")
    end
end)
