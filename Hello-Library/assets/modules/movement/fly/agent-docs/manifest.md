---
depends_on: [movement, input, sidebar/menu]
conflicts_with: []
exposes: [movement/fly, movement/fly/item]
---

# movement/fly

Flight for the local player, with no-clip beside it. F turns flight on or off. While it flies the body has no gravity, Space climbs and ShiftLeft sinks at `movement`'s speed, and walls and floors still stop it. No-clip makes the body's collider a sensor, so nothing stops it. It needs flight: turning it on turns flight on, and turning flight off turns it off. Both are toggles in the sidebar's menu too. Only a world that adds it to its player has it; the library's player does not.

## Components

- `movement/fly = { on, noclip }` on the local player, added by the world's own client half. Never synced.

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `on` | whether it flies | false |
  | `noclip` | whether it passes through walls and floors; only while it flies | false |

- `movement/fly/item = { field }`: marks its two `sidebar/menu/item`s in the menu's list, "Flight" (`field = "on"`, `order = 2`) and "No-clip" (`field = "noclip"`, `order = 3`). A click flips that field, and each item's `on` follows it.
- What it adds to its carrier, and takes off when `movement/fly` goes: the `fly` group in `input/game` (`toggle` on KeyF, `up` on Space, `down` on ShiftLeft), `GravityScale3d` (0 while it flies, 1 after) and `Sensor3d` (while no-clip is on).

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `movement/fly` | For a local carrier with `input`, bind the `fly` group (again when `input` is added back) |
| First | `movement/fly` | When `movement/fly` is taken off, as its last value says: take off `Sensor3d`, and `GravityScale3d` if it was not flying, else set it to 1; unbind unless `input` went too |
| Update | `movement/fly` | F (`input/game/fly/toggle` added) flips `on` |
| Update | `movement/fly` | On a changed `movement/fly`: `GravityScale3d` 0 while it flies and 1 after, and `Sensor3d` while no-clip is on |
| Update, after `movement/walk` and `movement/jump` | `movement/fly` | Polls while it flies: set the vertical velocity from `up` and `down` at `movement.speed` |
| Update | `movement/fly` | On a new menu list or a new local carrier, spawn the two items in each list holding none, with their click observers. A run condition over those edges skips it otherwise |
| Update | `movement/fly` | On a changed `movement/fly`, write each item's `on` from its field |

| Observer | Purpose |
|----------|---------|
| `Pointer<Click>` on an item | Flip the item's field on the local carrier's `movement/fly` |

## Use

```lua
-- a world's player, in its client half, for its local player
commands:entity(player):insert_if_new({ ["movement/fly"] = {} })
```

## Notes

- Rapier applies `GravityScale3d` only when it changes, and ignores its removal: a body it is taken from keeps no gravity (measured: one went on climbing at 6 m/s after flight was turned off). So turning flight off sets the scale back to 1, and it stays while `movement/fly` is on the entity. When `movement/fly` goes, a scale at 1 is taken off; one taken off mid-flight is set to 1 and stays, as taking it off would leave the body weightless.
- It owns `GravityScale3d` and `Sensor3d` on its carrier: a player that carries either for another reason has it rewritten or taken off.
- Space is also `movement`'s jump. While it flies, the vertical velocity it sets each frame, after movement's, replaces a jump's, and a ceiling or floor that stops the body does not stop it climbing or sinking again.
- The toggles keep no-clip within flight; the component written by hand does not (`noclip = true` with `on = false` is a sensor that falls).
- F is game input, so it does nothing while the sidebar is open; the menu's items work then.
- Rapier reports no sensor-to-sensor contact, so with no-clip on, walking into a portal's trigger (a sensor ball) does not cross.
- `player/client` turns the body `Dynamic` again on every changed `RigidBody3d`, and flight does not touch the body type. Other clients see the server's copy, kinematic, following the owner's Transform.
- Suites: `test_fly.lua` runs headless, on a real player standing on a floor under gravity: keys through `input` as a device-less source writes them, real clicks on the menu's items, a reload, and `movement/fly` taken off while it flies and while it does not.
