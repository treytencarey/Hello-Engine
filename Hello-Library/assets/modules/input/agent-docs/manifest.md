---
depends_on: []
conflicts_with: []
exposes: [input, input/held, input/actions]
---

# input

Keys, mouse buttons, motion and scroll, turned into one component per bound action. An action component exists only while the action is active, so a mod reads input with ordinary query edges instead of flags.

## Components

- `input = { mode, show_cursor, sensitivity }` on each local player:
  - `mode` names the component holding the bindings that apply, such as `"input/game"` or `"input/ui"`. With no mode set, nothing is active.
  - `show_cursor` shows the cursor when true and confines it when false.
  - `sensitivity` scales motion and scroll.
- `input/game`, `input/ui` (or any other mode component): bindings, `{ <group> = { <action> = <binding> } }`, where a binding is `{ key = <KeyCode> }`, `{ button = <MouseButton> }`, `{ motion = true }` or `{ scroll = true }`. Each mod writes its own group.
- `<mode>/<group>/<action>`: present while the action is active. `{ value = <1, or the analog strength> }` for keys and buttons; `{ dx, dy }` for motion and scroll, present only on frames with movement. Added, updated and removed by `input`.
- `input/held`, `input/actions`: `input`'s own state (held keys and buttons; which action components it added).

## Messages

Input that does not come from a device, written by any mod (a suite, a replay, an on-screen control) with `MessageWriter["<name>"]`; `input` adds them, and a mod writing one before `input` loads adds it too (`app:add_message`, which adds nothing the second time).

- `input/synthetic_key`: a key, shaped as Bevy's `KeyboardInput` (`{ key_code = <KeyCode>, state = "Pressed" | "Released" }`).
- `input/synthetic_mouse_button`: a mouse button, shaped as Bevy's `MouseButtonInput` (`{ button = <MouseButton>, state = ... }`).
- `input/synthetic_mouse_wheel`: a scroll, `{ x, y }`.
- `input/analog`: an analog strength for a held key, `{ key_code = <KeyCode>, value = <0..1> }`.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `input/held` | Fold keys, buttons (Bevy's and the synthetic messages) and `input/analog` into `input/held` |
| PreUpdate | `input` | Turn the active mode's bindings into action components; write only what changed |
| PreUpdate | `input/cursor` | On a changed `input`, apply `show_cursor` |

## Use

```lua
-- bind, in your mod's client half
commands:entity(player):patch({ ["input/game"] = { movement = { forward = { key = "KeyW" }, jump = { key = "Space" } } } })

-- read, in Update, through declared queries
app:add_systems(Update, {
    Query[{ with = { "input/game/movement/forward" } }],    -- held
    Query[{ added = { "input/game/movement/jump" } }],      -- pressed
    Query[{ removed = { "input/game/movement/jump" } }],    -- released
    Query[{ changed = { "input/game/look/zoom" } }],        -- a scroll this frame
}, function(held, pressed, released, scrolled)
    for _, e in ipairs(pressed:iter()) do
        -- jump
    end
end)

-- switch a player, for example when a menu opens
commands:entity(player):patch({ input = { mode = "input/ui", show_cursor = true } })

-- unbind
commands:entity(player):patch({ ["input/game"] = { movement = null } })
```

## Notes

- Actions are delivered in `PreUpdate`, so a mod reading them in `Update` needs no ordering edge.
- Removing `input` removes its actions, held state and every mod's bindings (`input/game`, `input/ui`): they are `input's` sub-components, and `mod_registry` removes a mod's parts with it. A mod that binds also binds on `added = { "input" }`, so its bindings come back with `input`.
- Bindings are data components and are not synced: bind in your client half. To use an action on the server, declare sync for that action component.
- Switching mode removes the old mode's actions, and a key held through the switch does nothing in the new mode until it is released (`input/held.through`): the Escape that opens a menu does not also close it.
- Every key event reaches every local player. There is no per-player device routing yet (split-screen).
- An action component removed by anything else is written again while it is still active: `input` owns it.
