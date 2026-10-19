---
depends_on: [cooldown, ui/style]
conflicts_with: []
exposes: [notification, notification/overlay, notification/fade, notification/alive]
---

# notification

A toast in the top-right corner, stacked with the others. Extend it with `return { base = "notification" }`: the base makes your entity a card under the shared overlay, runs the timeout and fades it out; your mod spawns the content as children of its own entity. Local UI: never synced.

## Components

- `notification = { timeout, dismiss, width, accent, fade }` on your entity, which becomes the card. Missing `width` (260), `accent` (`"accent"`, a `ui/style` role for the card's left edge) and `fade` (0.25 seconds) get defaults when it is added. `timeout` missing means it stays until dismissed; set `dismiss = true` to start the fade-out.
- `notification/overlay`: the shared overlay the cards stack in, made by the base when the first notification comes.
- `notification/fade = { elapsed, duration, height }` on your entity while it fades out.
- `notification/alive`: on your entity while the timeout runs, as a `cooldown` timer.

The base also gives your entity `Node`, `BorderRadius`, `ui/style` and `ChildOf` (the overlay), in one patch so it is never a UI root. Moved under the overlay, it belongs to the notification mod.

## Systems

| Schedule | Label | Purpose |
|----------|-------|---------|
| First | NotificationCard | On an added `notification`, fill in missing config, make the entity a card under the overlay (made if needed, found with `limit = 1`; all notifications share it), start the timeout |
| Update | NotificationDismiss | When the timeout ends or `dismiss` is set, start the fade (once) |
| Update, after `NotificationDismiss` | NotificationFade | Animation polls: shrink the card and fade every styled node in it, easing out; despawn your entity at the end |
| First | NotificationRemoved | When `notification` is removed, the card is despawned |

## Use

```lua
-- my/notice/init.lua
register_system("First", function(world)
    for _, e in ipairs(world:query({ added = { "my/notice" } })) do
        spawn({ Text = { text = e:get("my/notice").message }, ["ui/style"] = { text = "text" } })
            :with_parent(e:id())
    end
end)
return { base = "notification" }

-- anywhere
spawn({ ["my/notice"] = { message = "Saved" }, notification = { timeout = 4, accent = "text_good" } })
```

## Notes

- Your entity becomes the notification mod's once it is under the overlay, and goes with it: a reload of the notification mod clears the open toasts.
- Content styled with `ui/style` roles fades with the card; colors written directly do not.
- Despawning your entity, or removing `notification` from it, removes the card at once, without a fade.
- The overlay goes by itself: with the last notification the mod unloads, and core removes the entities its script spawned. While it is up, only the cards take the pointer: the overlay itself is `Pickable` with `should_block_lower = false`.
- Layout needs a window: the suite runs windowed. It stands in for a world VM (an instance id), where spawns carry their mod's stamp.
