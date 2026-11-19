-- A sidebar panel, "People", listing who is online in this world: one row per player replicated
-- here, showing who the player is. Other mods add items to a row, a button or a text, as children
-- of the row on its `added` edge, and observe their own buttons' clicks; the panel lays them out
-- after the name, in `order`, and never learns what one does. Local UI: never synced.
--
-- sidebar/people = {}
--
-- sidebar/people/state = {
--     open = <whether the panel is open>,
-- }
--
-- sidebar/people/button = {}
-- sidebar/people/view = {}
--
-- sidebar/people/row = {}
--
-- sidebar/people/row/player = {
--     entity = <the player's replica>,
-- }
--
-- sidebar/people/row/players: a player's rows, kept by the engine
--
-- sidebar/people/row/item = {
--     order = <position among the row's items>,
--     label = <text>,
--     button = <true for a button, false for a text>,
--     enabled = <false dims a button and its text>,
-- }

-- Who a row names: the player's `user_id`, which the server copies from the client's join
-- ticket, or its client while it has none (an anonymous join).
local function name_of(player)
    if player.user_id ~= nil and player.user_id ~= "" then
        return tostring(player.user_id)
    end
    return "Player " .. tostring(player.client_id)
end

-- What the panel keeps through a reload lives on the carrier, which a reload leaves alone, while
-- everything this mod spawned goes. `sidebar` taken off the carrier takes this state with it, as a
-- part of its name, and leaves the carrier: a closed panel starts again.
app:add_systems(First, {
    Query[{
        added = { "sidebar/people" },
        optional = { "sidebar/people/state" },
    }],
    Query[{
        removed = { "sidebar/people/state" },
        with = { "sidebar/people" },
    }],
    Commands,
}, function(carriers, stripped, commands)
    for _, e in ipairs(carriers:iter()) do
        if not e:has("sidebar/people/state") then
            commands:entity(e:id()):insert({ ["sidebar/people/state"] = { open = false } })
        end
    end
    for _, e in ipairs(stripped:iter()) do
        commands:entity(e:id()):try_insert({ ["sidebar/people/state"] = { open = false } })
    end
end):in_set("sidebar/people")

-- The button goes in the bar for an owned carrier of the panel: on a new bar (the sidebar built
-- or reloaded), and on the panel itself (added, given to this client, or this mod reloaded).
app:add_systems(Update, {
    Query[{ with = { "sidebar/people" } }],
    Query[{ with = { "sidebar/bar" } }],
    Query[{ with = { "sidebar/people/button" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(carriers, bars, buttons, own, commands)
    local bar = bars:iter()[1]
    if bar == nil or not buttons:is_empty() then return end
    for _, n in ipairs(own:iter()) do
        for _, _ in ipairs(carriers:iter_many(n:get("core/net/owns"))) do
            commands:spawn({
                ["sidebar/button"] = { icon = "icons/friends.png", title = "People", order = 6 },
                ["sidebar/people/button"] = {},
                ChildOf = bar:id(),
            })
            return
        end
    end
end):in_set("sidebar/people"):run_if({
    Query[{ added = { "sidebar/bar" } }],
    Query[{
        ["or"] = {
            added = { "sidebar/people", "core/net/owner" },
            changed = { "core/net/owner" },
        },
        with = { "sidebar/people", "core/net/owner" },
    }],
}, function(new_bars, new_carriers)
    return not new_bars:is_empty() or not new_carriers:is_empty()
end)

-- A new button that was open before a reload opens again, by the path a click takes. It waits for
-- the sidebar to make it an icon: an icon drawn active reacts to `sidebar/button/open` on a node.
app:add_systems(Update, {
    Query[{
        added = { "Node" },
        with = { "sidebar/people/button" },
    }],
    Query[{ with = { "sidebar/people", "sidebar/people/state" } }],
    Query[{ with = { "sidebar/button/open" } }],
    Commands,
}, function(icons, carriers, open_buttons, commands)
    for _, icon in ipairs(icons:iter()) do
        local carrier = carriers:iter()[1]
        local state = carrier and carrier:get("sidebar/people/state")
        if state ~= nil and state.open then
            local order = 0
            for _, o in ipairs(open_buttons:iter()) do
                local opened = o:get("sidebar/button/open")
                order = math.max(order, opened.order)
            end
            commands:entity(icon:id()):insert({ ["sidebar/button/open"] = { order = order + 1 } })
        end
    end
end):in_set("sidebar/people")

app:add_systems(Update, {
    Query[{
        added = { "sidebar/button/open" },
        with = { "sidebar/people/button" },
    }],
    Query[{ with = { "sidebar/container" } }],
    Query[{ with = { "sidebar/people", Mut["sidebar/people/state"] } }],
    Commands,
}, function(opened, containers, carriers, commands)
    for _, _ in ipairs(opened:iter()) do
        local container = containers:iter()[1]
        local carrier = carriers:iter_mut()[1]
        if container ~= nil and carrier ~= nil then
            commands:spawn({
                ["sidebar/panel"] = { width = 280, title = "People" },
                ["sidebar/people/view"] = {},
                ChildOf = container:id(),
            })
            carrier:get_mut("sidebar/people/state").open = true
        end
    end
end):in_set("sidebar/people")

-- Only a button still here closing is someone closing the panel. A reload takes the button too, and
-- its edge comes the same: that closes nothing, because the panel is to come back. The rows and
-- their items go with the panel.
app:add_systems(Update, {
    Query[{
        removed = { "sidebar/button/open" },
        with = { "sidebar/people/button" },
    }],
    Query[{ with = { "sidebar/people/button" } }],
    Query[{ with = { "sidebar/people/view" } }],
    Query[{ with = { Mut["sidebar/people/state"] } }],
    Commands,
}, function(closed, buttons, views, states, commands)
    local ids = {}
    for _, b in ipairs(closed:iter()) do
        ids[#ids + 1] = b:id()
    end
    for _, _ in ipairs(buttons:iter_many(ids)) do
        for _, view in ipairs(views:iter()) do
            commands:entity(view:id()):try_despawn()
        end
        for _, row in ipairs(states:iter_mut()) do
            row:get_mut("sidebar/people/state").open = false
        end
    end
end):in_set("sidebar/people")

-- The rows go in the panel's scroll area, which `sidebar/panel` builds a frame after the panel and
-- builds again when it reloads: a new scroll area gets a row for every player, and a player
-- arriving while the panel is open gets one. A player with a row already (its target list) gets
-- none. A mirror of another world's player is not in this world.
app:add_systems(Update, {
    Query[{ added = { "sidebar/panel/scroll" } }],
    Query[{
        added = { "player" },
        without = { "WorldMirror", "core/net/peer/mirror" },
    }],
    Query[{
        added = { "player/2d" },
        without = { "WorldMirror", "core/net/peer/mirror" },
    }],
    Query[{ with = { "sidebar/people/view" } }],
    Query[{ with = { "sidebar/panel/scroll" } }],
    Query[{
        any_of = { "player", "player/2d" },
        without = { "WorldMirror", "core/net/peer/mirror" },
        optional = { "player", "player/2d", "sidebar/people/row/players" },
    }],
    Commands,
}, function(new_scrolls, arrived, arrived_2d, views, scrolls, players, commands)
    for _, view in ipairs(views:iter()) do
        local scroll = scrolls:iter_many(scrolls:iter_descendants(view:id()))[1]
        if scroll ~= nil then
            local wanted
            if new_scrolls:contains(scroll:id()) then
                wanted = players:iter()
            else
                local ids = {}
                for _, p in ipairs(arrived:iter()) do ids[#ids + 1] = p:id() end
                for _, p in ipairs(arrived_2d:iter()) do ids[#ids + 1] = p:id() end
                wanted = players:iter_many(ids)
            end
            for _, p in ipairs(wanted) do
                if not p:has("sidebar/people/row/players") then
                    local player = p:has("player") and p:get("player") or p:get("player/2d")
                    local row = commands:spawn({
                        ["sidebar/people/row"] = {},
                        ["sidebar/people/row/player"] = { entity = p:id() },
                        Node = {
                            width = { Percent = 100 },
                            min_height = { Px = 32 },
                            flex_shrink = 0,
                            flex_direction = "Row",
                            align_items = "Center",
                            column_gap = { Px = 6 },
                            padding = { left = { Px = 8 }, right = { Px = 8 }, top = { Px = 4 }, bottom = { Px = 4 } },
                        },
                        ["ui/style"] = { background = "row_bg" },
                        ChildOf = scroll:id(),
                    }):id()
                    commands:spawn({
                        Text = { text = name_of(player) },
                        TextFont = { font_size = 12 },
                        Node = { flex_grow = 1, min_width = { Px = 0 } },
                        ["ui/style"] = { text = "text" },
                        ChildOf = row,
                    })
                end
            end
        end
    end
end):in_set("sidebar/people"):run_if({
    Query[{ with = { "sidebar/people/view" } }],
    Query[{ added = { "sidebar/panel/scroll" } }],
    Query[{ added = { "player" } }],
    Query[{ added = { "player/2d" } }],
}, function(views, scrolls, players, players_2d)
    return not views:is_empty() and (not scrolls:is_empty() or not players:is_empty() or not players_2d:is_empty())
end)

-- A row's name follows its player's. Its text is the row's child that is not an item.
app:add_systems(Update, {
    Query[{
        changed = { "player" },
        with = { "sidebar/people/row/players" },
    }],
    Query[{
        changed = { "player/2d" },
        with = { "sidebar/people/row/players" },
    }],
    Query[{
        with = { "sidebar/people/row" },
        optional = { "Children" },
    }],
    Query[{
        with = { Mut["Text"] },
        without = { "sidebar/people/row/item" },
    }],
}, function(changed, changed_2d, rows, texts)
    local function rename(p, player)
        local name = name_of(player)
        for _, row in ipairs(rows:iter_many(p:get("sidebar/people/row/players"))) do
            for _, t in ipairs(texts:iter_many_mut(row:get("Children") or {})) do
                t:get_mut("Text"):set_if_neq(name)
            end
        end
    end
    for _, p in ipairs(changed:iter()) do rename(p, p:get("player")) end
    for _, p in ipairs(changed_2d:iter()) do rename(p, p:get("player/2d")) end
end):in_set("sidebar/people")

-- `player` taken off an entity that stays: it is no one's row. A player that despawns takes its
-- rows itself (the relationship's `linked_spawn`).
app:add_systems(Update, {
    Query[{ removed = { "player" } }],
    Query[{ removed = { "player/2d" } }],
    Query[{ with = { "sidebar/people/row", "sidebar/people/row/player" } }],
    Query[{
        any_of = { "player", "player/2d" },
        without = { "WorldMirror", "core/net/peer/mirror" },
    }],
    Commands,
}, function(removed, removed_2d, rows, players, commands)
    local ids = {}
    for _, p in ipairs(removed:iter()) do ids[#ids + 1] = p:id() end
    for _, p in ipairs(removed_2d:iter()) do ids[#ids + 1] = p:id() end
    for _, gone in ipairs(ids) do
        for _, row in ipairs(rows:iter()) do
            local link = row:get("sidebar/people/row/player")
            if link.entity == gone and not players:contains(gone) then
                commands:entity(row:id()):try_despawn()
            end
        end
    end
end):in_set("sidebar/people")

-- An item is its own label, so a click on its text lands on the item its owner observes. A changed
-- item, `added` included, is drawn again and puts its row back in order: the name, then the items
-- by `order`.
app:add_systems(Update, {
    Query[{
        changed = { "sidebar/people/row/item" },
        optional = { Mut["Text"], Mut["ui/style"], "ChildOf" },
    }],
    Query[{
        with = { "sidebar/people/row" },
        optional = { "Children" },
    }],
    Query[{ with = { "sidebar/people/row/item" } }],
    Query[{
        with = { "Text" },
        without = { "sidebar/people/row/item" },
    }],
    Commands,
}, function(changed, rows, items, names, commands)
    local holders = {}
    for _, e in ipairs(changed:iter_mut()) do
        local item = e:get("sidebar/people/row/item")
        local label = tostring(item.label or "")
        local style
        if item.button and item.enabled ~= false then
            style = { background = "icon_bg", hover = "icon_hover", press = "icon_active", border = "border", text = "text" }
        elseif item.button then
            style = { background = "row_alt", border = "border", text = "text_dim" }
        else
            style = { text = item.enabled == false and "text_dim" or "text" }
        end
        if not e:has("Text") and item.button then
            commands:entity(e:id()):insert_if_new({
                Button = {},
                Node = {
                    flex_shrink = 0,
                    justify_content = "Center",
                    align_items = "Center",
                    padding = { left = { Px = 8 }, right = { Px = 8 }, top = { Px = 3 }, bottom = { Px = 3 } },
                    border = { left = { Px = 1 }, right = { Px = 1 }, top = { Px = 1 }, bottom = { Px = 1 } },
                },
                BorderRadius = {
                    top_left = { Px = 4 }, top_right = { Px = 4 },
                    bottom_left = { Px = 4 }, bottom_right = { Px = 4 },
                },
                ["ui/style"] = style,
                Text = { text = label },
                TextFont = { font_size = 11 },
            })
        elseif not e:has("Text") then
            commands:entity(e:id()):insert_if_new({
                Node = { flex_shrink = 0 },
                ["ui/style"] = style,
                Text = { text = label },
                TextFont = { font_size = 11 },
            })
        else
            e:get_mut("Text"):set_if_neq(label)
            if e:has("ui/style") then
                e:get_mut("ui/style"):set_if_neq(style)
            end
        end
        if e:has("ChildOf") then
            holders[#holders + 1] = e:get("ChildOf")
        end
    end
    for _, row in ipairs(rows:iter_many(holders)) do
        local children = row:get("Children") or {}
        local listed = items:iter_many(children)
        table.sort(listed, function(a, b)
            local first, second = a:get("sidebar/people/row/item"), b:get("sidebar/people/row/item")
            return first.order < second.order
        end)
        local parent = commands:entity(row:id())
        local at = 0
        for _, name in ipairs(names:iter_many(children)) do
            parent:insert_child(at, name:id())
            at = at + 1
        end
        for _, item in ipairs(listed) do
            parent:insert_child(at, item:id())
            at = at + 1
        end
    end
end):in_set("sidebar/people")

-- `sidebar/people/row/item` taken off an entity that stays: take off what the panel added. The
-- edge also comes for an item that despawned, which `try_remove` leaves alone.
app:add_systems(Update, {
    Query[{ removed = { "sidebar/people/row/item" } }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        commands:entity(e:id()):try_remove("Button", "Node", "BorderRadius", "ui/style", "Text", "TextFont")
    end
end):in_set("sidebar/people")

return {
    defaults = {
        ["sidebar/people/row/item"] = {
            order = 0,
            label = "",
            button = false,
            enabled = true,
        },
    },
    relationships = {
        ["sidebar/people/row/player"] = { target = "sidebar/people/row/players", linked_spawn = true },
    },
}
