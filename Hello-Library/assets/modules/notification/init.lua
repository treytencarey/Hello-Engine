-- A toast in the top-right corner. Extend it with `return { base = "notification" }`: the
-- base makes your entity a card under the shared overlay, runs the timeout and the
-- fade-out; your mod spawns the content as children of its own entity. Moved under the
-- overlay, the card belongs to this mod and goes with it. Colors come from `ui/style`, so
-- content styled with roles fades with the card. Local UI: never synced.
--
-- notification = {
--     timeout = <seconds until it goes; missing = until dismissed>,
--     dismiss = <true to start the fade-out now>,
--     width = <pixels>,
--     accent = <ui/style role for the card's left edge>,
--     fade = <seconds the fade-out takes>,
-- }
--
-- notification/overlay = {}
--
-- notification/fade = {
--     elapsed = <seconds>,
--     duration = <seconds>,
--     height = <the card's height when the fade began>,
-- }
--
-- notification/alive: present while the timeout runs (a `cooldown` timer).

local app = ...
local Time = require("bevy::time::Time")

-- A new notification fills in its config and becomes a card under the overlay.
app:add_systems(First, {
    Query[{ added = { "notification" } }],
    Query[{ with = { "notification/overlay" } }],
    Commands,
}, function(cards, overlays, commands)
    local overlay
    for _, e in ipairs(cards:iter()) do
        if overlay == nil then
            local shown = overlays:iter()[1]
            overlay = shown and shown:id() or commands:spawn({
                ["notification/overlay"] = {},
                Node = {
                    position_type = "Absolute",
                    top = { Px = 16 },
                    right = { Px = 16 },
                    flex_direction = "Column",
                    align_items = "FlexEnd",
                    row_gap = { Px = 8 },
                },
                -- above the file browser's context menu (500)
                GlobalZIndex = { value = 600 },
                -- only the cards take the pointer, not the gaps between them
                Pickable = { should_block_lower = false, is_hoverable = false },
            }):id()
        end
        local n = e:get("notification")
        local width, accent = n.width or 260, n.accent or "accent"
        local card = commands:entity(e:id())
        card:patch({
            notification = { width = width, accent = accent, fade = n.fade or 0.25 },
            Node = {
                width = { Px = width },
                flex_direction = "Column",
                row_gap = { Px = 6 },
                padding = { left = { Px = 10 }, right = { Px = 10 }, top = { Px = 8 }, bottom = { Px = 8 } },
                border = { left = { Px = 2 }, right = { Px = 1 }, top = { Px = 1 }, bottom = { Px = 1 } },
            },
            BorderRadius = {
                top_left = { Px = 6 }, top_right = { Px = 6 },
                bottom_left = { Px = 6 }, bottom_right = { Px = 6 },
            },
            ["ui/style"] = { background = "bg", border = "border", border_left = accent },
        })
        commands:entity(overlay):add_child(e:id())
        if n.timeout ~= nil then
            card:patch({ cooldown = { ["notification/alive"] = { remaining = n.timeout } } })
        end
    end
end):in_set("notification/card")

-- The timeout ran out, or the extending mod set `dismiss`: the card starts to fade, once.
-- The timeout's edge also comes for a card that despawned; only a card still here fades.
app:add_systems(Update, {
    Query[{
        removed = { "notification/alive" },
        with = { "notification" },
    }],
    Query[{
        changed = { "notification" },
        without = { "notification/fade" },
        optional = { "ComputedNode" },
    }],
    Query[{
        with = { "notification" },
        without = { "notification/fade" },
        optional = { "ComputedNode" },
    }],
    Commands,
}, function(timed_out, changed, cards, commands)
    local ended = {}
    for _, e in ipairs(timed_out:iter()) do
        ended[#ended + 1] = e:id()
    end
    for _, e in ipairs(cards:iter_many(ended)) do
        local node = e:get("ComputedNode")
        commands:entity(e:id()):patch({
            ["notification/fade"] = {
                elapsed = 0,
                duration = e:get("notification").fade,
                height = node and node.size.y or 0,
            },
        })
    end
    for _, e in ipairs(changed:iter()) do
        local n = e:get("notification")
        if n.dismiss == true then
            local node = e:get("ComputedNode")
            commands:entity(e:id()):patch({ ["notification/fade"] = { elapsed = 0, duration = n.fade, height = node and node.size.y or 0 } })
        end
    end
end):in_set("notification/dismiss")

-- Animation polls: each fading card shrinks and every styled node in it fades, easing out.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { Mut["notification/fade"], "notification" },
        optional = { Mut["Node"] },
    }],
    Query[{ with = { Mut["ui/style"] } }],
    Commands,
}, function(time, fading, styled, commands)
    local dt = time:delta_secs()
    for _, e in ipairs(fading:iter_mut()) do
        local fade = e:get("notification/fade")
        local elapsed = fade.elapsed + dt
        local left = 1 - math.min(1, elapsed / fade.duration)
        local factor = left * left * left
        e:patch({ ["notification/fade"] = { elapsed = elapsed } })
        if fade.height > 0 then
            e:patch({ Node = { height = { Px = fade.height * factor }, overflow = { x = "Hidden", y = "Hidden" } } })
        end
        local card = styled:iter_descendants(e:id())
        table.insert(card, 1, e:id())
        for _, node in ipairs(styled:iter_many_mut(card)) do
            node:patch({ ["ui/style"] = { alpha = factor } })
        end
        if elapsed >= fade.duration then
            commands:entity(e:id()):despawn()
        end
    end
end):in_set("notification/fade"):after("notification/dismiss")

-- `notification` removed: the card goes. The overlay needs no removing: with the last
-- notification this mod unloads, and the entities it owns go with it. The edge also comes
-- for a card that despawned, which `try_despawn` leaves alone.
app:add_systems(First, {
    Query[{ removed = { "notification" } }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        commands:entity(e:id()):try_despawn()
    end
end):in_set("notification/removed")
