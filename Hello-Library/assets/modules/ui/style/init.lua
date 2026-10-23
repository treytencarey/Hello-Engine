-- UI colors by role. A node says what it is, and this mod alone writes its BackgroundColor,
-- TextColor and BorderColor from the world's theme (`ui/theme`, filled by a theme mod such
-- as `ui/theme/dark`). A node with `hover` or `press` needs Interaction (a Button has it).
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

local app = ...

-- Nodes whose style or interaction changed; every node when the theme changed (a theme
-- filling its colors is such a change, so nodes styled before it are not missed). A role
-- the theme lacks leaves that color alone.
app:add_systems(PostUpdate, {
    Query[{
        ["or"] = {
            changed = { "ui/style", "Interaction" },
        },
        with = { "ui/style" },
        optional = { "Interaction" },
    }],
    Query[{
        with = { "ui/style" },
        optional = { "Interaction" },
    }],
    Query[{ changed = { "ui/theme" } }],
    Query[{ with = { "ui/theme" } }],
    Commands,
}, function(changed_nodes, styled_nodes, theme_changes, themes, commands)
    local nodes = changed_nodes:iter()
    if not theme_changes:is_empty() then
        nodes = styled_nodes:iter()
    end
    for _, t in ipairs(themes:iter()) do
        local theme = t:get("ui/theme")
        for _, e in ipairs(nodes) do
            local style = e:get("ui/style")
            local interaction = e:get("Interaction") or {}
            local alpha = style.alpha or 1
            local background = style.background
            if interaction.Pressed and style.press ~= nil then
                background = style.press
            elseif (interaction.Hovered or interaction.Pressed) and style.hover ~= nil then
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

-- `ui/style` was taken off a node that stays: take off the colors this mod wrote. The edge
-- also comes for a node that despawned, which `try_remove` leaves alone.
app:add_systems(First, {
    Query[{ removed = { "ui/style" } }],
    Commands,
}, function(unstyled, commands)
    for _, e in ipairs(unstyled:iter()) do
        commands:entity(e:id()):try_remove("BackgroundColor", "TextColor", "BorderColor")
    end
end):in_set("ui/style/removed")
