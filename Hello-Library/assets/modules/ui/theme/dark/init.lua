-- A dark theme: dark panels, light text, blue accents. Add `ui/theme/dark = {}` to an entity
-- to give its world this theme.

register_system("First", function(world)
    for _, e in ipairs(world:query({
        added = { "ui/theme" },
        with = { "ui/theme/dark" },
    })) do
        e:patch({
            ["ui/theme"] = {
                bg = { r = 0.12, g = 0.12, b = 0.14, a = 1 },
                header_bg = { r = 0.15, g = 0.15, b = 0.18, a = 1 },
                icon_bar_bg = { r = 0.08, g = 0.08, b = 0.10, a = 1 },
                icon_bg = { r = 0.15, g = 0.15, b = 0.18, a = 1 },
                icon_hover = { r = 0.22, g = 0.22, b = 0.26, a = 1 },
                icon_active = { r = 0.25, g = 0.35, b = 0.5, a = 1 },
                icon_active_hover = { r = 0.30, g = 0.42, b = 0.58, a = 1 },
                border = { r = 0.08, g = 0.08, b = 0.10, a = 1 },
                row_bg = { r = 0.10, g = 0.10, b = 0.12, a = 1 },
                row_alt = { r = 0.12, g = 0.12, b = 0.14, a = 1 },
                row_hover = { r = 0.18, g = 0.18, b = 0.22, a = 1 },
                row_selected = { r = 0.25, g = 0.35, b = 0.5, a = 1 },
                text = { r = 0.85, g = 0.85, b = 0.85, a = 1 },
                text_dim = { r = 0.55, g = 0.55, b = 0.55, a = 1 },
                text_warn = { r = 1, g = 0.8, b = 0.3, a = 1 },
                text_bad = { r = 1, g = 0.4, b = 0.4, a = 1 },
                text_good = { r = 0.4, g = 1, b = 0.6, a = 1 },
                accent = { r = 0.3, g = 0.6, b = 1, a = 1 },
                folder = { r = 0.9, g = 0.75, b = 0.4, a = 1 },
                file = { r = 0.6, g = 0.7, b = 0.8, a = 1 },
                context_bg = { r = 0.18, g = 0.18, b = 0.22, a = 0.98 },
                context_hover = { r = 0.25, g = 0.25, b = 0.3, a = 1 },
                danger = { r = 0.8, g = 0.3, b = 0.3, a = 1 },
                transparent = { r = 0, g = 0, b = 0, a = 0 },
                drop_zone = { r = 0.2, g = 0.4, b = 0.6, a = 0.3 },
                drop_highlight = { r = 0.2, g = 0.3, b = 0.4, a = 1 },
            },
        })
    end
end, { label = "ThemeDark" })

return { base = "ui/theme" }
