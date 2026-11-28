-- UI colors by role. A node says what it is, and this mod alone writes its BackgroundColor,
-- TextColor and BorderColor from the world's theme (`ui/theme`, filled by a theme mod such
-- as `ui/theme/dark`). A node with `hover` gets Bevy's `Hovered`, which picking keeps true while
-- the pointer is on the node or any of its descendants. A node with `press` gets Bevy's `Pressed`
-- from the pointer's `Press` on it or a descendant, until its `Release`, `DragEnd` or `Cancel`.
--
-- ui/style = {
--     background = <role>,
--     text = <role>,
--     border = <role, all four sides>,
--     border_left = <role, the left side>,
--     hover = <role for the background while hovered>,
--     press = <role for the background while pressed>,
--     alpha = <0..1, scales every color>,
-- }

local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Press = require("bevy::picking::prelude::Press")
local Release = require("bevy::picking::prelude::Release")
local DragEnd = require("bevy::picking::prelude::DragEnd")
local Cancel = require("bevy::picking::prelude::Cancel")
local AssetServer = require("bevy::asset::AssetServer")

-- Picking keeps `Hovered` only on the entities that carry it, so a node with a hover role gets one.
-- `Interaction` would not do: bevy_ui updates it only for cameras drawing to a window, and a world
-- draws to a texture. It stays when `ui/style` goes, as another mod may read it.
app:add_systems(First, {
    Query[{ changed = { "ui/style" }, without = { "Hovered" } }],
    Commands,
}, function(styled, commands)
    for _, e in ipairs(styled:iter()) do
        if e:get("ui/style").hover ~= nil then
            commands:entity(e:id()):insert_if_new({ Hovered = false })
        end
    end
end):in_set("ui/style/init")

-- Nodes whose style or hover changed, or that were pressed or let go; every node when the theme
-- changed (a theme filling its colors is such a change, so nodes styled before it are not missed).
-- A role the theme lacks leaves that color alone.
app:add_systems(PostUpdate, {
    Query[{
        ["or"] = {
            changed = { "ui/style", "Hovered" },
            added = { "Pressed" },
        },
        with = { "ui/style" },
        optional = { "Hovered", "Pressed" },
    }],
    Query[{ removed = { "Pressed" } }],
    Query[{
        with = { "ui/style" },
        optional = { "Hovered", "Pressed" },
    }],
    Query[{ changed = { "ui/theme" } }],
    Query[{ with = { "ui/theme" } }],
    Commands,
}, function(changed_nodes, let_go, styled_nodes, theme_changes, themes, commands)
    local nodes = changed_nodes:iter()
    if not theme_changes:is_empty() then
        nodes = styled_nodes:iter()
    else
        local gone = {}
        for _, e in ipairs(let_go:iter()) do gone[#gone + 1] = e:id() end
        for _, e in ipairs(styled_nodes:iter_many(gone)) do nodes[#nodes + 1] = e end
    end
    local t = themes:iter()[1]
    if t then
        local theme = t:get("ui/theme")
        for _, e in ipairs(nodes) do
            local style = e:get("ui/style")
            local alpha = style.alpha or 1
            local background = style.background
            if style.press ~= nil and e:has("Pressed") then
                background = style.press
            elseif style.hover ~= nil and e:has("Hovered") and e.Hovered:get() then
                background = style.hover
            end
            local bg = background and theme[background]
            local text = style.text and theme[style.text]
            local border = style.border and theme[style.border]
            local left = (style.border_left and theme[style.border_left]) or border
            local node = commands:entity(e:id())
            if bg then
                node:patch({ BackgroundColor = { color = { r = bg.r, g = bg.g, b = bg.b, a = bg.a * alpha } } })
            end
            if text then
                node:patch({ TextColor = { color = { r = text.r, g = text.g, b = text.b, a = text.a * alpha } } })
            end
            if border then
                node:patch({
                    BorderColor = {
                        left = { r = left.r, g = left.g, b = left.b, a = left.a * alpha },
                        right = { r = border.r, g = border.g, b = border.b, a = border.a * alpha },
                        top = { r = border.r, g = border.g, b = border.b, a = border.a * alpha },
                        bottom = { r = border.r, g = border.g, b = border.b, a = border.a * alpha },
                    },
                })
            end
        end
    end
end):in_set("ui/style")

-- The theme's `font` (an asset path) on every text in the world, styled or not: Bevy's own font
-- has ASCII only, so a `·` or a `⚠` in any mod's text would be a box. A new text gets it; every
-- text gets it when the theme changes. A theme with no font leaves the text on Bevy's.
local fonts = {}
app:add_systems(PostUpdate, {
    Query[{ added = { "Text" } }],
    Query[{ added = { "TextSpan" } }],
    Query[{ added = { "Text2d" } }],
    Query[{ with = { "Text" } }],
    Query[{ with = { "TextSpan" } }],
    Query[{ with = { "Text2d" } }],
    Query[{ changed = { "ui/theme" } }],
    Query[{ with = { "ui/theme" } }],
    Res[AssetServer],
    Commands,
}, function(new_texts, new_spans, new_2d, texts, spans, texts_2d, theme_changes, themes, asset_server, commands)
    local t = themes:iter()[1]
    local path = t and t:get("ui/theme").font
    if path == nil then return end
    local kinds = { new_texts, new_spans, new_2d }
    if not theme_changes:is_empty() then kinds = { texts, spans, texts_2d } end
    local found = {}
    for _, kind in ipairs(kinds) do
        for _, e in ipairs(kind:iter()) do found[#found + 1] = e end
    end
    if #found == 0 or fonts[path] == false then return end
    if fonts[path] == nil then
        -- A headless run has no font loader, and the load is refused there: its text stays on
        -- Bevy's font, which nothing draws.
        local ok, handle = pcall(asset_server.load, asset_server, path)
        fonts[path] = ok and handle or false
        if not ok then return end
    end
    for _, e in ipairs(found) do
        commands:entity(e:id()):patch({ TextFont = { font = fonts[path] } })
    end
end):in_set("ui/style/font")

-- A pointer event reaches each node on its way up from the node it hit (a button's label is hit,
-- not the button), so a node with a press role is pressed whichever of its descendants was.
app:add_observer(On[Pointer[Press]], {
    Query[{ with = { "ui/style" } }],
    Commands,
}, function(event, nodes, commands)
    for _, e in ipairs(nodes:iter_many({ event.entity })) do
        if e:get("ui/style").press ~= nil then
            commands:entity(e:id()):insert({ Pressed = {} })
        end
    end
end)

--- The press is over.
local function let_go(event, pressed, commands)
    for _, e in ipairs(pressed:iter_many({ event.entity })) do
        commands:entity(e:id()):try_remove("Pressed")
    end
end

-- A release off the node reaches only what is under the pointer then; the press's own end there
-- is its drag's `DragEnd`, which reaches the node it hit and its ancestors.
app:add_observer(On[Pointer[Release]], {
    Query[{ with = { "ui/style", "Pressed" } }],
    Commands,
}, let_go)
app:add_observer(On[Pointer[DragEnd]], {
    Query[{ with = { "ui/style", "Pressed" } }],
    Commands,
}, let_go)
app:add_observer(On[Pointer[Cancel]], {
    Query[{ with = { "ui/style", "Pressed" } }],
    Commands,
}, let_go)

-- `ui/style` was taken off a node that stays: take off the colors and the press this mod wrote.
-- The edge also comes for a node that despawned, which `try_remove` leaves alone.
app:add_systems(First, {
    Query[{ removed = { "ui/style" } }],
    Commands,
}, function(unstyled, commands)
    for _, e in ipairs(unstyled:iter()) do
        commands:entity(e:id()):try_remove("BackgroundColor", "TextColor", "BorderColor", "Pressed")
    end
end):in_set("ui/style/removed")
