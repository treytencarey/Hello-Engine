-- The base of every sidebar panel: a column with a header holding the title, and a scroll
-- area below it for the panel's content. Extend it with `base = "sidebar/panel"`, put your
-- content in the child marked `sidebar/panel/scroll`, and set `title` when it is ready;
-- until then the scroll area says "Loading...". A title of "" hides the header.
--
-- sidebar/panel = {
--     title = <text>,
--     width = <pixels>,
--     scroll_speed = <pixels per wheel step>,
-- }
--
-- sidebar/panel/header = {}
-- sidebar/panel/title = {}
-- sidebar/panel/loading = {}
--
-- sidebar/panel/scroll = {
--     offset = <pixels scrolled>,
--     speed = <pixels per wheel step>,
-- }

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "sidebar/panel" } })) do
        local p = e:get("sidebar/panel")
        e:patch({
            ["sidebar/panel"] = {
                width = p.width or 280,
                scroll_speed = p.scroll_speed or 20,
            },
        })
    end
end, { label = "SidebarPanelInit" })

register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "sidebar/panel" } })) do
        local p = e:get("sidebar/panel")
        e:patch({
            Node = {
                height = { Percent = 100 },
                flex_direction = "Column",
                align_items = "Stretch",
                border = { left = { Px = 1 }, right = { Px = 1 } },
            },
            ["ui/style"] = { background = "bg", border = "border" },
        })
        local header = spawn({
            ["sidebar/panel/header"] = {},
            Node = {
                width = { Percent = 100 },
                height = { Px = 36 },
                flex_shrink = 0,
                flex_direction = "Row",
                align_items = "Center",
                padding = { left = { Px = 12 }, right = { Px = 8 } },
            },
            ["ui/style"] = { background = "header_bg" },
        }):with_parent(e:id())
        spawn({
            ["sidebar/panel/title"] = {},
            TextFont = { font_size = 14 },
            ["ui/style"] = { text = "text" },
        }):with_parent(header:id())
        local scroll = spawn({
            ["sidebar/panel/scroll"] = { offset = 0, speed = p.scroll_speed },
            Node = {
                width = { Percent = 100 },
                flex_grow = 1,
                flex_direction = "Column",
                align_items = "Stretch",
                overflow = { x = "Visible", y = "Scroll" },
                padding = { left = { Px = 8 }, right = { Px = 8 }, bottom = { Px = 8 }, top = { Px = 8 } },
            },
            ScrollPosition = { x = 0, y = 0 },
        }):with_parent(e:id())
        -- The wheel scrolls, kept between the top and the end of the content. When content
        -- shrinks, Bevy clamps what is drawn; the next step clamps the offset.
        scroll:observe("Pointer<Scroll>", function(w, target, event)
            local area = w:get_entity(target:id())
            local s = area:get("sidebar/panel/scroll")
            local node = area:get("ComputedNode")
            local room = math.max(0, node.content_size.y - node.size.y)
            local offset = math.max(0, math.min(room, s.offset - event.event.y * s.speed))
            area:patch({
                ["sidebar/panel/scroll"] = { offset = offset },
                ScrollPosition = { x = 0, y = offset },
            })
        end)
        spawn({
            ["sidebar/panel/loading"] = {},
            Text = { text = "Loading..." },
            TextFont = { font_size = 14 },
            Node = { margin = { top = { Px = 16 } }, align_self = "Center" },
            ["ui/style"] = { text = "text_dim" },
        }):with_parent(scroll:id())
    end
end, { label = "SidebarPanelBuild", after = { "SidebarPanelInit" } })

-- Title and width follow the config, from the frame the panel is built: the header shows a
-- non-empty title, and the loading text goes once there is a title.
register_system("First", function(world)
    for _, e in ipairs(world:query({
        changed = { "sidebar/panel" },
    })) do
        local p = e:get("sidebar/panel")
        e:patch({ Node = { width = { Px = p.width } } })
        for _, header in ipairs(world:query({
            entities = { e:id() },
            with = { "sidebar/panel/header" },
        })) do
            header:patch({ Node = { display = (p.title ~= nil and p.title ~= "") and "Flex" or "None" } })
        end
        for _, title in ipairs(world:query({
            entities = { e:id() },
            with = { "sidebar/panel/title" },
        })) do
            title:patch({ Text = { text = p.title or "" } })
        end
        if p.title ~= nil then
            for _, loading in ipairs(world:query({
                entities = { e:id() },
                with = { "sidebar/panel/loading" },
            })) do
                despawn(loading:id())
            end
        end
    end
end, { label = "SidebarPanelTitle", after = { "SidebarPanelBuild" } })

-- `sidebar/panel` was taken off an entity that stays: take off what the base added.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "sidebar/panel" } })) do
        e:patch({
            Node = null,
            ["ui/style"] = null,
        })
    end
end, { label = "SidebarPanelRemoved" })
