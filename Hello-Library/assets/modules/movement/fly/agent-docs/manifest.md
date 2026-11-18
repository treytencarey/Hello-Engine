---
depends_on: [movement, input, sidebar/menu]
conflicts_with: []
exposes: [movement/fly, movement/fly/item]
---

# movement/fly

Flight for the local player, with no-clip beside it. F turns flight on or off. While it flies the body has no gravity, Space climbs and ControlLeft sinks at `movement`'s speed (its `run` while movement's run, Shift, is held and `run` is set), and walls and floors still stop it. No-clip makes the body's collider a sensor, so nothing stops it. It needs flight: turning it on turns flight on, and turning flight off turns it off. Both are toggles in the sidebar's menu too. Only a world that adds it to its player has it; the library's player does not.

## Components

- `movement/fly = { on, noclip }` on a player, added by the world on its server. It syncs with the owner's authority: the owner's client flips it, and the server and the other clients see it. It acts only on this client's own player: another's copy keeps its gravity, its collider and its keys, here and on the server.

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `on` | whether it flies | false |
  | `noclip` | whether it passes through walls and floors; only while it flies | false |

- `movement/fly/item = { field }`: marks its two `sidebar/menu/item`s in the menu's list, "Flight" (`field = "on"`, `order = 2`) and "No-clip" (`field = "noclip"`, `order = 3`). A click flips that field, and each item's `on` follows it.
- What it adds to its carrier, and takes off when `movement/fly` goes: the `fly` group in `input/game` (`toggle` on KeyF, `up` on Space, `down` on ControlLeft; Shift is `movement`'s `run`, read here, not bound again), `GravityScale3d` (0 while it flies) and `Sensor3d` (while no-clip is on).

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `movement/fly` | For a local carrier with `input`, bind the `fly` group (again when `input` is added back) |
| First | `movement/fly` | When `movement/fly` is taken off this client's own player, as its last value says: take off `Sensor3d`, and `GravityScale3d` if it was flying; unbind unless `input` went too |
| Update | `movement/fly` | F (`input/game/fly/toggle` added) flips `on` |
| Update | `movement/fly` | On a changed `movement/fly` on this client's own player: `GravityScale3d` 0 while it flies, taken off when it stops (only while it is still 0), and `Sensor3d` while no-clip is on |
| Update, after `movement/walk` and `movement/jump` | `movement/fly` | Polls while it flies: set the vertical velocity from `up` and `down` at `movement.speed`, or `movement.run` while `input/game/movement/run` is held and `run` is set |
| Update | `movement/fly` | On a new menu list or a new local carrier, spawn the two items in each list holding none, with their click observers. A run condition over those edges skips it otherwise |
| Update | `movement/fly` | On a changed `movement/fly`, write each item's `on` from its field |

| Observer | Purpose |
|----------|---------|
| `Pointer<Click>` on an item | Flip the item's field on the local carrier's `movement/fly` |

## Use

```lua
-- a world's player, in its server half: every copy has it, and its owner flies it
commands:entity(player):insert_if_new({ ["movement/fly"] = {} })
```

## Notes

- Rapier applies `GravityScale3d` only when it changes and ignores its removal, so a body flight takes its scale from keeps a scale of 0 until something gives it one again (measured: one went on climbing at 6 m/s). The library's player does: `player/client` puts a scale of 1 back on its local body when one is taken off. A world flying another body gives it the same.
- While it flies it writes any scale on its carrier to 0, and stopping takes that off: a scale the body had before is not kept. It owns `Sensor3d` on its carrier the same way.
- Space is also `movement`'s jump. While it flies, the vertical velocity it sets each frame, after movement's, replaces a jump's, and a ceiling or floor that stops the body does not stop it climbing or sinking again.
- The toggles keep no-clip within flight; the component written by hand does not (`noclip = true` with `on = false` is a sensor that falls).
- F is game input, so it does nothing while the sidebar is open; the menu's items work then.
- Rapier reports no sensor-to-sensor contact, so with no-clip on, walking into a portal's trigger (a sensor ball) does not cross.
- `player/client` turns the body `Dynamic` again on every changed `RigidBody3d`, and flight does not touch the body type. Other clients see the server's copy, kinematic, following the owner's Transform.
- Suites: `test_fly.lua` runs headless, on a real player standing on a floor under gravity: keys through `input` as a device-less source writes them, real clicks on the menu's items, a reload, `movement/fly` taken off while it flies and while it does not, and another client's flying copy left alone. `test_fly_net.lua` runs headless over a real connection: flight the owner turns on reaches the server's copy, which keeps its gravity and collider.
