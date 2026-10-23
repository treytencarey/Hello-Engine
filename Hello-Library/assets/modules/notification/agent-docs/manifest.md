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

The base also gives your entity `Node`, `BorderRadius` and `ui/style`, and adds it to the overlay with Bevy's `add_child` in the same system's commands, so it is never a UI root. Moved under the overlay, it belongs to the notification mod.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `notification/card` | On an added `notification`, fill in missing config, make the entity a card under the overlay (made if needed, else the first row of a declared `notification/overlay` query; all notifications share it), start the timeout |
| Update | `notification/dismiss` | When the timeout ends or `dismiss` is set, start the fade (once) |
| Update, after `notification/dismiss` | `notification/fade` | Animation polls: shrink the card and fade every styled node in it, easing out; despawn your entity at the end |
| First | `notification/removed` | When `notification` is removed, the card is despawned |

## Use

```lua
-- my/notice/init.lua
local app = ...

app:add_systems(First, {
    Query[{ added = { "my/notice" } }],
    Commands,
}, function(notices, commands)
    for _, e in ipairs(notices:iter()) do
        commands:spawn({
            Text = { text = e:get("my/notice").message },
            ["ui/style"] = { text = "text" },
            ChildOf = e:id(),
        })
    end
end):in_set("my/notice")

return { base = "notification" }

-- anywhere, through a system's Commands
commands:spawn({ ["my/notice"] = { message = "Saved" }, notification = { timeout = 4, accent = "text_good" } })
```

## Notes

- Your entity becomes the notification mod's once it is under the overlay, and goes with it: a reload of the notification mod clears the open toasts.
- Content styled with `ui/style` roles fades with the card; colors written directly do not.
- Despawning your entity, or removing `notification` from it, removes the card at once, without a fade.
- The overlay goes by itself: with the last notification the mod unloads, and core removes the entities its script spawned. While it is up, only the cards take the pointer: the overlay itself is `Pickable` with `should_block_lower = false`.
- Layout needs a window: the suite runs windowed. It stands in for a world VM (an instance id), where spawns carry their mod's stamp.
