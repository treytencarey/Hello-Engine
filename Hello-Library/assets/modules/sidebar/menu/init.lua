-- A sidebar panel holding a list of items other mods put in it: each mod spawns its own items
-- into the list when the list appears, and the menu names none of them. The menu gives each item
-- its button and its label, and keeps the list in `order`. A click on an item is its own mod's,
-- which observes it.
--
-- sidebar/menu = {}
--
-- sidebar/menu/state = {
--     open = <whether the panel is open>,
-- }
--
-- sidebar/menu/button = {}
-- sidebar/menu/view = {}
-- sidebar/menu/list = {}
--
-- sidebar/menu/item = {
--     title = <text>,
--     order = <position in the list>,
--     on = <true or false for a toggle, which shows On or Off; absent otherwise>,
-- }

-- What the panel keeps through a reload lives on the carrier, which a reload leaves alone, while
-- everything this mod spawned goes. `sidebar` taken off the carrier takes this state with it, as a
-- part of its name, and leaves the carrier: a closed panel starts again.
app:add_systems(First, {
    Query[{
        added = { "sidebar/menu" },
        optional = { "sidebar/menu/state" },
    }],
    Query[{
        removed = { "sidebar/menu/state" },
        with = { "sidebar/menu" },
    }],
    Commands,
}, function(carriers, stripped, commands)
    for _, e in ipairs(carriers:iter()) do
        if not e:has("sidebar/menu/state") then
            commands:entity(e:id()):insert({ ["sidebar/menu/state"] = { open = false } })
        end
    end
    for _, e in ipairs(stripped:iter()) do
        commands:entity(e:id()):try_insert({ ["sidebar/menu/state"] = { open = false } })
    end
end):in_set("sidebar/menu")

-- The button goes in the bar for a local player with the menu: on a new bar (the sidebar built
-- or reloaded), and on the menu itself (added, or this mod reloaded).
app:add_systems(Update, {
    Query[{ with = { "sidebar/menu", "core/net/local" } }],
    Query[{ with = { "sidebar/bar" } }],
    Query[{ with = { "sidebar/menu/button" } }],
    Commands,
}, function(carriers, bars, buttons, commands)
    local bar = bars:iter()[1]
    if bar ~= nil and not carriers:is_empty() and buttons:is_empty() then
        commands:spawn({
            ["sidebar/button"] = { icon = "icons/settings.png", title = "Menu", order = 5 },
            ["sidebar/menu/button"] = {},
            ChildOf = bar:id(),
        })
    end
end):in_set("sidebar/menu"):run_if({
    Query[{ added = { "sidebar/bar" } }],
    Query[{
        ["or"] = {
            added = { "sidebar/menu", "core/net/local" },
        },
        with = { "sidebar/menu", "core/net/local" },
    }],
}, function(new_bars, new_carriers)
    return not new_bars:is_empty() or not new_carriers:is_empty()
end)

-- A new button that was open before a reload opens again, by the path a click takes. It waits for
-- the sidebar to make it an icon: an icon drawn active reacts to `sidebar/button/open` on a node.
app:add_systems(Update, {
    Query[{
        added = { "Node" },
        with = { "sidebar/menu/button" },
    }],
    Query[{ with = { "sidebar/menu", "sidebar/menu/state" } }],
    Query[{ with = { "sidebar/button/open" } }],
    Commands,
}, function(icons, carriers, open_buttons, commands)
    for _, icon in ipairs(icons:iter()) do
        local carrier = carriers:iter()[1]
        local state = carrier and carrier:get("sidebar/menu/state")
        if state ~= nil and state.open then
            local order = 0
            for _, o in ipairs(open_buttons:iter()) do
                local opened = o:get("sidebar/button/open")
                order = math.max(order, opened.order)
            end
            commands:entity(icon:id()):insert({ ["sidebar/button/open"] = { order = order + 1 } })
        end
    end
end):in_set("sidebar/menu")

app:add_systems(Update, {
    Query[{
        added = { "sidebar/button/open" },
        with = { "sidebar/menu/button" },
    }],
    Query[{ with = { "sidebar/container" } }],
    Query[{ with = { "sidebar/menu", Mut["sidebar/menu/state"] } }],
    Commands,
}, function(opened, containers, carriers, commands)
    for _, _ in ipairs(opened:iter()) do
        local container = containers:iter()[1]
        local carrier = carriers:iter_mut()[1]
        if container ~= nil and carrier ~= nil then
            commands:spawn({
                ["sidebar/panel"] = { width = 240, title = "Menu" },
                ["sidebar/menu/view"] = {},
                ChildOf = container:id(),
            })
            carrier:get_mut("sidebar/menu/state").open = true
        end
    end
end):in_set("sidebar/menu")

-- Only a button still here closing is someone closing the panel. A reload takes the button too, and
-- its edge comes the same: that closes nothing, because the panel is to come back.
app:add_systems(Update, {
    Query[{
        removed = { "sidebar/button/open" },
        with = { "sidebar/menu/button" },
    }],
    Query[{ with = { "sidebar/menu/button" } }],
    Query[{ with = { "sidebar/menu/view" } }],
    Query[{ with = { Mut["sidebar/menu/state"] } }],
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
            row:get_mut("sidebar/menu/state").open = false
        end
    end
end):in_set("sidebar/menu")

-- The list goes in the panel's scroll area, which `sidebar/panel` builds a frame after the panel,
-- and builds again when it reloads.
app:add_systems(Update, {
    Query[{ added = { "sidebar/panel/scroll" } }],
    Query[{ with = { "sidebar/menu/view" } }],
    Commands,
}, function(scrolls, views, commands)
    for _, scroll in ipairs(scrolls:iter()) do
        if views:iter_many(views:iter_ancestors(scroll:id()))[1] ~= nil then
            commands:spawn({
                ["sidebar/menu/list"] = {},
                Node = {
                    flex_direction = "Column",
                    align_items = "Stretch",
                    flex_shrink = 0,
                    row_gap = { Px = 4 },
                },
                ChildOf = scroll:id(),
            })
        end
    end
end):in_set("sidebar/menu")

-- The item is its own label, so a click on its text lands on the item its owner observes. An owner
-- may change `order` too, so any changed item puts its list back in order.
app:add_systems(Update, {
    Query[{
        changed = { "sidebar/menu/item" },
        optional = { Mut["Text"], "ChildOf" },
    }],
    Query[{
        with = { "sidebar/menu/list" },
        optional = { "Children" },
    }],
    Query[{ with = { "sidebar/menu/item" } }],
    Commands,
}, function(changed, lists, items, commands)
    local holders = {}
    for _, e in ipairs(changed:iter_mut()) do
        local item = e:get("sidebar/menu/item")
        local label = item.title
        if item.on == true then
            label = label .. ": On"
        elseif item.on == false then
            label = label .. ": Off"
        end
        if e:has("Text") then
            e:get_mut("Text"):set_if_neq(label)
        else
            commands:entity(e:id()):insert_if_new({
                Button = {},
                Node = {
                    width = { Percent = 100 },
                    flex_shrink = 0,
                    padding = { left = { Px = 8 }, right = { Px = 8 }, top = { Px = 6 }, bottom = { Px = 6 } },
                },
                ["ui/style"] = { background = "row_bg", hover = "row_hover", text = "text" },
                Text = { text = label },
                TextFont = { font_size = 13 },
            })
        end
        if e:has("ChildOf") then
            holders[#holders + 1] = e:get("ChildOf")
        end
    end
    for _, list in ipairs(lists:iter_many(holders)) do
        local children = list:get("Children") or {}
        local listed = items:iter_many(children)
        table.sort(listed, function(a, b)
            local first, second = a:get("sidebar/menu/item"), b:get("sidebar/menu/item")
            return first.order < second.order
        end)
        local row = commands:entity(list:id())
        for i, item in ipairs(listed) do
            row:insert_child(i - 1, item:id())
        end
    end
end):in_set("sidebar/menu")

return {
    defaults = {
        ["sidebar/menu/item"] = {
            title = "",
            order = 0,
        },
    },
}
