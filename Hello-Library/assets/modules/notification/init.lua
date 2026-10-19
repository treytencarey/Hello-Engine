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

-- A new notification fills in its config and becomes a card under the overlay.
register_system("First", function(world)
    local overlay
    for _, e in ipairs(world:query({ added = { "notification" } })) do
        overlay = overlay or world:query({ with = { "notification/overlay" }, limit = 1 })[1]
        if overlay == nil then
            overlay = spawn({
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
            })
        end
        local n = e:get("notification")
        local width, accent = n.width or 260, n.accent or "accent"
        e:patch({
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
            ChildOf = overlay:id(),
        })
        if n.timeout ~= nil then
            e:patch({ cooldown = { ["notification/alive"] = { remaining = n.timeout } } })
        end
    end
end, { label = "NotificationCard" })

-- The timeout ran out, or the extending mod set `dismiss`: the card starts to fade, once.
register_system("Update", function(world)
    for _, e in ipairs(world:query({
        removed = { "notification/alive" },
        with = { "notification" },
        without = { "notification/fade" },
        optional = { "ComputedNode" },
    })) do
        local node = e:get("ComputedNode")
        e:patch({
            ["notification/fade"] = {
                elapsed = 0,
                duration = e:get("notification").fade,
                height = node and node.size.y or 0,
            },
        })
    end
    for _, e in ipairs(world:query({
        changed = { "notification" },
        without = { "notification/fade" },
        optional = { "ComputedNode" },
    })) do
        local n = e:get("notification")
        if n.dismiss == true then
            local node = e:get("ComputedNode")
            e:patch({ ["notification/fade"] = { elapsed = 0, duration = n.fade, height = node and node.size.y or 0 } })
        end
    end
end, { label = "NotificationDismiss" })

-- Animation polls: each fading card shrinks and every styled node in it fades, easing out.
register_system("Update", function(world)
    local dt = world:delta_time() or 0
    for _, e in ipairs(world:query({ with = { "notification/fade", "notification" } })) do
        local fade = e:get("notification/fade")
        local elapsed = fade.elapsed + dt
        local left = 1 - math.min(1, elapsed / fade.duration)
        local factor = left * left * left
        e:patch({ ["notification/fade"] = { elapsed = elapsed } })
        if fade.height > 0 then
            e:patch({ Node = { height = { Px = fade.height * factor }, overflow = { x = "Hidden", y = "Hidden" } } })
        end
        for _, node in ipairs(world:query({ entities = { e:id() }, with = { "ui/style" } })) do
            node:patch({ ["ui/style"] = { alpha = factor } })
        end
        if elapsed >= fade.duration then
            despawn(e:id())
        end
    end
end, { label = "NotificationFade", after = { "NotificationDismiss" } })

-- `notification` removed: the card goes. The overlay needs no removing: with the last
-- notification this mod unloads, and the entities it owns go with it.
register_system("First", function(world)
    for _, e in ipairs(world:query({ removed = { "notification" } })) do
        despawn(e:id())
    end
end, { label = "NotificationRemoved" })
