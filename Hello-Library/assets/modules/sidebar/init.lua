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

local app = ...
local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")

app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "sidebar", "core/net/local", "input" },
        },
        with = { "sidebar", "core/net/local" },
        optional = { "sidebar/open" },
    }],
    Query[{ with = { "sidebar/container" } }],
    Commands,
}, function(players, containers, commands)
    local arrived = players:iter()
    for _, e in ipairs(arrived) do
        commands:entity(e:id()):patch({
            ["input/game"] = { sidebar = { toggle = { key = "Escape" } } },
            ["input/ui"] = { sidebar = { toggle = { key = "Escape" } } },
        })
    end
    -- One container for every local player. A UI root of its own: a UI node under the player
    -- would not be laid out. Shown if the sidebar is open already (a reload: `sidebar/open`
    -- gets no new edge). The bar gets its parent in the flush that spawns it, so it is never
    -- laid out as a UI root.
    local first = arrived[1]
    if first ~= nil and containers:is_empty() then
        local container = commands:spawn({
            ["sidebar/container"] = {},
            Node = {
                position_type = "Absolute",
                left = { Px = 0 },
                top = { Px = 0 },
                bottom = { Px = 0 },
                flex_direction = "Row",
                align_items = "Stretch",
                display = first:has("sidebar/open") and "Flex" or "None",
            },
            GlobalZIndex = { value = 100 },
        })
        container:add_child(commands:spawn({
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
        }):id())
    end
end):in_set("sidebar/setup")

-- The player left this world: its sidebar closes. The edge also comes for a player that
-- despawned, which `try_remove` leaves alone.
app:add_systems(First, {
    Query[{
        removed = { "core/net/local" },
        with = { "sidebar/open" },
    }],
    Commands,
}, function(away, commands)
    for _, e in ipairs(away:iter()) do
        commands:entity(e:id()):try_remove("sidebar/open")
    end
end):in_set("sidebar/away")

-- `sidebar` removed: its UI goes, with every button and panel in it. The edge also comes for a
-- player that despawned: only bindings still there are taken off.
app:add_systems(First, {
    Query[{ removed = { "sidebar" } }],
    Query[{ with = { "sidebar/container" } }],
    Query[{ with = { Mut["input/game"] } }],
    Query[{ with = { Mut["input/ui"] } }],
    Commands,
}, function(removed, containers, game_bindings, ui_bindings, commands)
    for _, e in ipairs(removed:iter()) do
        local container = containers:iter()[1]
        if container ~= nil then
            commands:entity(container:id()):despawn()
        end
        for _, b in ipairs(game_bindings:iter_many_mut({ e:id() })) do
            b:patch({ ["input/game"] = { sidebar = null } })
        end
        for _, b in ipairs(ui_bindings:iter_many_mut({ e:id() })) do
            b:patch({ ["input/ui"] = { sidebar = null } })
        end
    end
end):in_set("sidebar/removed")

-- Escape in game input opens the sidebar. Escape in UI input closes the newest open panel,
-- or the sidebar when none is open.
app:add_systems(Update, {
    Query[{
        added = { "input/game/sidebar/toggle" },
        with = { "sidebar", "core/net/local" },
    }],
    Query[{
        added = { "input/ui/sidebar/toggle" },
        with = { "sidebar", "core/net/local" },
    }],
    Query[{ with = { "sidebar/button", "sidebar/button/open" } }],
    Commands,
}, function(opening, closing, open_buttons, commands)
    for _, e in ipairs(opening:iter()) do
        commands:entity(e:id()):insert({ ["sidebar/open"] = {} })
    end
    for _, e in ipairs(closing:iter()) do
        local newest
        for _, b in ipairs(open_buttons:iter()) do
            if newest == nil or b:get("sidebar/button/open").order > newest:get("sidebar/button/open").order then
                newest = b
            end
        end
        if newest ~= nil then
            commands:entity(newest:id()):remove("sidebar/button/open")
        else
            commands:entity(e:id()):remove("sidebar/open")
        end
    end
end):in_set("sidebar/toggle")

-- Opening shows the sidebar and gives the player the cursor and UI input.
app:add_systems(Update, {
    Query[{
        added = { "sidebar/open" },
        with = { "sidebar" },
    }],
    Query[{ with = { "sidebar/container", Mut["Node"] } }],
    Commands,
}, function(opened, containers, commands)
    for _, e in ipairs(opened:iter()) do
        for _, c in ipairs(containers:iter_mut()) do
            c:patch({ Node = { display = "Flex" } })
        end
        commands:entity(e:id()):patch({ input = { mode = "input/ui", show_cursor = true } })
    end
end):in_set("sidebar/show"):after("sidebar/toggle")

-- Closing hides it, closes every panel, and gives game input back. The edge also comes for a
-- player that despawned: only one still here gets game input back.
app:add_systems(Update, {
    Query[{
        removed = { "sidebar/open" },
        with = { "sidebar" },
    }],
    Query[{ with = { "sidebar/container", Mut["Node"] } }],
    Query[{ with = { "sidebar" } }],
    Query[{ with = { "sidebar/button", "sidebar/button/open" } }],
    Commands,
}, function(closed, containers, players, open_buttons, commands)
    for _, e in ipairs(closed:iter()) do
        for _, c in ipairs(containers:iter_mut()) do
            c:patch({ Node = { display = "None" } })
        end
        for _, p in ipairs(players:iter_many({ e:id() })) do
            commands:entity(p:id()):patch({ input = { mode = "input/game", show_cursor = false } })
        end
        for _, b in ipairs(open_buttons:iter()) do
            commands:entity(b:id()):remove("sidebar/button/open")
        end
    end
end):in_set("sidebar/hide"):after("sidebar/toggle")

-- A new button becomes an icon.
app:add_systems(Update, {
    Query[{ added = { "sidebar/button" } }],
    Commands,
}, function(buttons, commands)
    for _, b in ipairs(buttons:iter()) do
        local button = b:get("sidebar/button")
        local icon = commands:entity(b:id())
        icon:patch({
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
        icon:observe(On[Pointer[Click]], {
            Query[{ with = { "sidebar/button/open" } }],
            Commands,
        }, function(event, open, commands)
            if open:contains(event.entity) then
                commands:entity(event.entity):remove("sidebar/button/open")
            else
                local order = 0
                for _, o in ipairs(open:iter()) do
                    order = math.max(order, o:get("sidebar/button/open").order)
                end
                commands:entity(event.entity):insert({ ["sidebar/button/open"] = { order = order + 1 } })
            end
        end)
        icon:add_child(commands:spawn({
            Text = { text = string.sub(button.title or "?", 1, 1) },
            TextFont = { font_size = 18 },
            ["ui/style"] = { text = "text_dim" },
        }):id())
    end
end):in_set("sidebar/icons")

-- The bar keeps its icons in `order`.
app:add_systems(Update, {
    Query[{ added = { "sidebar/button" } }],
    Query[{ with = { "sidebar/bar" } }],
    Query[{ with = { "sidebar/button" } }],
    Commands,
}, function(new_buttons, bars, buttons, commands)
    for _, _ in ipairs(new_buttons:iter()) do
        for _, bar in ipairs(bars:iter()) do
            local icons = buttons:iter_many(buttons:iter_descendants(bar:id()))
            table.sort(icons, function(a, b)
                return a:get("sidebar/button").order < b:get("sidebar/button").order
            end)
            local row = commands:entity(bar:id())
            for i, b in ipairs(icons) do
                row:insert_child(i - 1, b:id())
            end
        end
        break
    end
end):in_set("sidebar/order")

-- An icon shows whether its panel is open.
app:add_systems(Update, {
    Query[{
        added = { "sidebar/button/open" },
        with = { "Node" },
    }],
    Commands,
}, function(opened, commands)
    for _, b in ipairs(opened:iter()) do
        commands:entity(b:id()):patch({ ["ui/style"] = { background = "icon_active", hover = "icon_active_hover" } })
    end
end):in_set("sidebar/icon_open")

-- The edge also comes for a button that despawned: only one still here is restyled.
app:add_systems(Update, {
    Query[{
        removed = { "sidebar/button/open" },
        with = { "Node" },
    }],
    Query[{ with = { "Node", Mut["ui/style"] } }],
}, function(closed, icons)
    local ids = {}
    for _, b in ipairs(closed:iter()) do
        ids[#ids + 1] = b:id()
    end
    for _, b in ipairs(icons:iter_many_mut(ids)) do
        b:patch({ ["ui/style"] = { background = "icon_bg", hover = "icon_hover" } })
    end
end):in_set("sidebar/icon_closed"):after("sidebar/toggle"):after("sidebar/hide")
