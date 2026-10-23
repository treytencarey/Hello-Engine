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

local app = ...
local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Scroll = require("bevy::picking::prelude::Scroll")

app:add_systems(First, {
    Query[{ added = { "sidebar/panel" } }],
    Commands,
}, function(panels, commands)
    for _, e in ipairs(panels:iter()) do
        local p = e:get("sidebar/panel")
        commands:entity(e:id()):patch({
            ["sidebar/panel"] = {
                width = p.width or 280,
                scroll_speed = p.scroll_speed or 20,
            },
        })
    end
end):in_set("sidebar/panel/init")

-- Each part is spawned, then given its parent with `add_child` in the same flush, so no part
-- is ever laid out as a UI root.
app:add_systems(First, {
    Query[{ added = { "sidebar/panel" } }],
    Commands,
}, function(panels, commands)
    for _, e in ipairs(panels:iter()) do
        local p = e:get("sidebar/panel")
        local panel = commands:entity(e:id())
        panel:patch({
            Node = {
                height = { Percent = 100 },
                flex_direction = "Column",
                align_items = "Stretch",
                border = { left = { Px = 1 }, right = { Px = 1 } },
            },
            ["ui/style"] = { background = "bg", border = "border" },
        })
        local header = commands:spawn({
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
        }):id()
        local title = commands:spawn({
            ["sidebar/panel/title"] = {},
            TextFont = { font_size = 14 },
            ["ui/style"] = { text = "text" },
        }):id()
        local scroll = commands:spawn({
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
        })
        -- The wheel scrolls, kept between the top and the end of the content. When content
        -- shrinks, Bevy clamps what is drawn; the next step clamps the offset.
        scroll:observe(On[Pointer[Scroll]], {
            Query[{
                with = { Mut["sidebar/panel/scroll"], Mut["ScrollPosition"] },
                optional = { "ComputedNode" },
            }],
        }, function(event, areas)
            for _, area in ipairs(areas:iter_many_mut({ event.entity })) do
                local s = area:get("sidebar/panel/scroll")
                local node = area:get("ComputedNode")
                local room = math.max(0, node.content_size.y - node.size.y)
                local offset = math.max(0, math.min(room, s.offset - event.event.y * s.speed))
                area:patch({
                    ["sidebar/panel/scroll"] = { offset = offset },
                    ScrollPosition = { x = 0, y = offset },
                })
            end
        end)
        local loading = commands:spawn({
            ["sidebar/panel/loading"] = {},
            Text = { text = "Loading..." },
            TextFont = { font_size = 14 },
            Node = { margin = { top = { Px = 16 } }, align_self = "Center" },
            ["ui/style"] = { text = "text_dim" },
        }):id()
        commands:entity(header):add_child(title)
        commands:entity(scroll:id()):add_child(loading)
        panel:add_child(header):add_child(scroll:id())
    end
end):in_set("sidebar/panel/build"):after("sidebar/panel/init")

-- Title and width follow the config, from the frame the panel is built: the header shows a
-- non-empty title, and the loading text goes once there is a title.
app:add_systems(First, {
    Query[{ changed = { "sidebar/panel" } }],
    Query[{ with = { "sidebar/panel/header", Mut["Node"] } }],
    Query[{ with = { "sidebar/panel/title" } }],
    Query[{ with = { "sidebar/panel/loading" } }],
    Commands,
}, function(panels, headers, titles, loadings, commands)
    for _, e in ipairs(panels:iter()) do
        local p = e:get("sidebar/panel")
        commands:entity(e:id()):patch({ Node = { width = { Px = p.width } } })
        local parts = headers:iter_descendants(e:id())
        for _, header in ipairs(headers:iter_many_mut(parts)) do
            header:patch({ Node = { display = (p.title ~= nil and p.title ~= "") and "Flex" or "None" } })
        end
        for _, title in ipairs(titles:iter_many(parts)) do
            commands:entity(title:id()):patch({ Text = { text = p.title or "" } })
        end
        if p.title ~= nil then
            for _, loading in ipairs(loadings:iter_many(parts)) do
                commands:entity(loading:id()):despawn()
            end
        end
    end
end):in_set("sidebar/panel/title"):after("sidebar/panel/build")

-- `sidebar/panel` was taken off an entity that stays: take off what the base added. The edge
-- also comes for a panel that despawned, which `try_remove` leaves alone.
app:add_systems(First, {
    Query[{ removed = { "sidebar/panel" } }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        commands:entity(e:id()):try_remove("Node", "ui/style")
    end
end):in_set("sidebar/panel/removed")
