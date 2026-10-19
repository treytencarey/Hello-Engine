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

-- Nodes whose style or interaction changed; every node when the theme changed (a theme
-- filling its colors is such a change, so nodes styled before it are not missed). A role
-- the theme lacks leaves that color alone.
register_system("PostUpdate", function(world)
    local nodes = world:query({
        ["or"] = {
            changed = { "ui/style", "Interaction" },
        },
        with = { "ui/style" },
        optional = { "Interaction" },
    })
    if #world:query({ changed = { "ui/theme" } }) > 0 then
        nodes = world:query({
            with = { "ui/style" },
            optional = { "Interaction" },
        })
    end
    for _, t in ipairs(world:query({ with = { "ui/theme" } })) do
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
            if bg then
                e:patch({ BackgroundColor = { color = { r = bg.r, g = bg.g, b = bg.b, a = bg.a * alpha } } })
            end
            if text then
                e:patch({ TextColor = { color = { r = text.r, g = text.g, b = text.b, a = text.a * alpha } } })
            end
            if border then
                e:patch({
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
end, { label = "Style" })

-- `ui/style` was taken off a node that stays: take off the colors this mod wrote.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "ui/style" } })) do
        e:patch({
            BackgroundColor = null,
            TextColor = null,
            BorderColor = null,
        })
    end
end, { label = "StyleRemoved" })
