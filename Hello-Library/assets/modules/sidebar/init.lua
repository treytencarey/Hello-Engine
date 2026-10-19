-- The sidebar: an icon bar at the left edge, one icon per `sidebar/button`, and the panels the
-- buttons open beside it. Escape opens it; while it is open, Escape closes the newest open
-- panel, or the sidebar when none is open. A panel mod spawns its own button into the bar
-- when a bar appears; the sidebar makes it an icon, and the panel mod opens its panel while
-- the button carries `sidebar/button/open`, which a click on the icon toggles. Everything
-- in the container goes with it, so a new bar gets new buttons. Only the local player's
-- sidebar is drawn.
--
-- sidebar = {}
--
-- sidebar/open = {}: present while the sidebar is open.
--
-- sidebar/button = {
--     icon = <image path>,
--     title = <text>,
--     order = <position in the bar>,
-- }
--
-- sidebar/button/open = {
--     order = <one above the open buttons' highest when it opened; Escape closes the highest>,
-- }
--
-- sidebar/container = {}
--
-- sidebar/bar = {}

register_system("First", function(world)
    for _, e in ipairs(world:query({
        ["or"] = {
            added = { "sidebar", "core/net/local", "input" },
        },
        with = { "sidebar", "core/net/local" },
        optional = { "sidebar/open" },
    })) do
        e:patch({
            ["input/game"] = { sidebar = { toggle = { key = "Escape" } } },
            ["input/ui"] = { sidebar = { toggle = { key = "Escape" } } },
        })
        if #world:query({ with = { "sidebar/container" }, limit = 1 }) == 0 then
            -- A UI root of its own: a UI node under the player would not be laid out. Shown
            -- if the sidebar is open already (a reload: `sidebar/open` gets no new edge).
            local container = spawn({
                ["sidebar/container"] = {},
                Node = {
                    position_type = "Absolute",
                    left = { Px = 0 },
                    top = { Px = 0 },
                    bottom = { Px = 0 },
                    flex_direction = "Row",
                    align_items = "Stretch",
                    display = e:has("sidebar/open") and "Flex" or "None",
                },
                GlobalZIndex = { value = 100 },
            })
            spawn({
                ["sidebar/bar"] = {},
                Node = {
                    width = { Px = 48 },
                    height = { Percent = 100 },
                    flex_direction = "Column",
                    align_items = "Center",
                    row_gap = { Px = 4 },
                    padding = { left = { Px = 4 }, right = { Px = 4 }, top = { Px = 4 }, bottom = { Px = 4 } },
                },
                ["ui/style"] = { background = "icon_bar_bg" },
            }):with_parent(container:id())
        end
    end
end, { label = "SidebarSetup" })

-- The player left this world: its sidebar closes.
register_system("First", function(world)
    for _, e in ipairs(world:query({
        removed = { "core/net/local" },
        with = { "sidebar/open" },
    })) do
        e:patch({ ["sidebar/open"] = null })
    end
end, { label = "SidebarAway" })

-- `sidebar` removed: its UI goes, with every button and panel in it.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "sidebar" } })) do
        for _, c in ipairs(world:query({ with = { "sidebar/container" }, limit = 1 })) do
            despawn(c:id())
        end
        e:patch({
            ["input/game"] = { sidebar = null },
            ["input/ui"] = { sidebar = null },
        })
    end
end, { label = "SidebarRemoved" })

-- Escape in game input opens the sidebar. Escape in UI input closes the newest open panel,
-- or the sidebar when none is open.
register_system("Update", function(world)
    for _, e in ipairs(world:query({
        added = { "input/game/sidebar/toggle" },
        with = { "sidebar", "core/net/local" },
    })) do
        e:patch({ ["sidebar/open"] = {} })
    end
    for _, e in ipairs(world:query({
        added = { "input/ui/sidebar/toggle" },
        with = { "sidebar", "core/net/local" },
    })) do
        local newest
        for _, b in ipairs(world:query({ with = { "sidebar/button", "sidebar/button/open" } })) do
            if newest == nil or b:get("sidebar/button/open").order > newest:get("sidebar/button/open").order then
                newest = b
            end
        end
        if newest ~= nil then
            newest:patch({ ["sidebar/button/open"] = null })
        else
            e:patch({ ["sidebar/open"] = null })
        end
    end
end, { label = "SidebarToggle" })

-- Opening shows the sidebar and gives the player the cursor and UI input.
register_system("Update", function(world)
    for _, e in ipairs(world:query({
        added = { "sidebar/open" },
        with = { "sidebar" },
    })) do
        for _, c in ipairs(world:query({ with = { "sidebar/container" }, limit = 1 })) do
            c:patch({ Node = { display = "Flex" } })
        end
        e:patch({ input = { mode = "input/ui", show_cursor = true } })
    end
end, { label = "SidebarShow", after = { "SidebarToggle" } })

-- Closing hides it, closes every panel, and gives game input back.
register_system("Update", function(world)
    for _, e in ipairs(world:query({
        removed = { "sidebar/open" },
        with = { "sidebar" },
    })) do
        for _, c in ipairs(world:query({ with = { "sidebar/container" }, limit = 1 })) do
            c:patch({ Node = { display = "None" } })
        end
        e:patch({ input = { mode = "input/game", show_cursor = false } })
        for _, b in ipairs(world:query({ with = { "sidebar/button", "sidebar/button/open" } })) do
            b:patch({ ["sidebar/button/open"] = null })
        end
    end
end, { label = "SidebarHide", after = { "SidebarToggle" } })

-- A new button becomes an icon.
register_system("Update", function(world)
    for _, b in ipairs(world:query({ added = { "sidebar/button" } })) do
        b:patch({
            Button = {},
            Node = {
                width = { Px = 36 },
                height = { Px = 36 },
                justify_content = "Center",
                align_items = "Center",
            },
            BorderRadius = {
                top_left = { Px = 6 }, top_right = { Px = 6 },
                bottom_left = { Px = 6 }, bottom_right = { Px = 6 },
            },
            ["ui/style"] = { background = "icon_bg", hover = "icon_hover" },
        })
        -- A click opens the button's panel, or closes it.
        b:observe("Pointer<Click>", function(w, target)
            local pressed = w:get_entity(target:id())
            if pressed:has("sidebar/button/open") then
                pressed:patch({ ["sidebar/button/open"] = null })
            else
                local order = 0
                for _, o in ipairs(w:query({ with = { "sidebar/button/open" } })) do
                    order = math.max(order, o:get("sidebar/button/open").order)
                end
                pressed:patch({ ["sidebar/button/open"] = { order = order + 1 } })
            end
        end)
        spawn({
            Text = { text = string.sub(b:get("sidebar/button").title or "?", 1, 1) },
            TextFont = { font_size = 18 },
            ["ui/style"] = { text = "text_dim" },
        }):with_parent(b:id())
    end
end, { label = "SidebarIcons" })

-- The bar keeps its icons in `order`.
register_system("Update", function(world)
    for _, _ in ipairs(world:query({ added = { "sidebar/button" } })) do
        for _, bar in ipairs(world:query({ with = { "sidebar/bar" }, limit = 1 })) do
            local buttons = world:query({ entities = { bar:id() }, with = { "sidebar/button" } })
            table.sort(buttons, function(a, b)
                return a:get("sidebar/button").order < b:get("sidebar/button").order
            end)
            local ids = {}
            for _, b in ipairs(buttons) do
                ids[#ids + 1] = b:id()
            end
            bar:patch({ Children = ids })
        end
        break
    end
end, { label = "SidebarOrder" })

-- An icon shows whether its panel is open.
register_system("Update", function(world)
    for _, b in ipairs(world:query({ added = { "sidebar/button/open" }, with = { "Node" } })) do
        b:patch({ ["ui/style"] = { background = "icon_active", hover = "icon_active_hover" } })
    end
end, { label = "SidebarIconOpen" })

register_system("Update", function(world)
    for _, b in ipairs(world:query({ removed = { "sidebar/button/open" }, with = { "Node" } })) do
        b:patch({ ["ui/style"] = { background = "icon_bg", hover = "icon_hover" } })
    end
end, { label = "SidebarIconClosed", after = { "SidebarToggle", "SidebarHide" } })
