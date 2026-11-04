---
depends_on: []
conflicts_with: []
exposes: [vr, vr/active]
---

# vr

Whether a client is in VR. A client states it for its own player, as only it can see its headset. `vr` does nothing else: `player/vr` puts it on a player, and reacts to `vr/active`.

## Components

- `vr = { timeout }`, added by `player/vr` on the server and synced from it:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `timeout` | seconds without a pose before it counts as off | 2 |

- `vr/active = {}`: exists while this player's headset is tracking. Written by the owning client and synced by hand, with client authority, to the server and every other client. React to its `added` and `removed` edges.
- `vr/tracking = { at }`: when the last pose arrived, on the owner's client. It never crosses.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (server) | `vr/sync` | On an added `vr`, declare `vr/active`'s sync |
| First (server) | `vr/unsync` | When `vr` is removed from an entity that stays, take that sync off |
| First (client) | `vr/detect` | Polls: reads `VrPoseInput`. On this client's own player, adds `vr/active` at a pose once its sync has arrived, and removes it after `timeout` with none |

## Use

```lua
-- in a mod, on any side: a player went into VR
app:add_systems(First, {
    Query[{ added = { "vr/active" } }],
}, function(entered)
    for _, e in ipairs(entered:iter()) do
        -- ...
    end
end)
```

## Notes

- A pose is the signal, not the host's VR mode, which this mod never reads: a player with no headset gets no `vr/active`, and a host with VR on and tracking off keeps the desktop camera.
- The engine forwards `VrInputRaw` and `VrPoseInput` from the host to every world. Only the world holding this client's own player (`core/net/local`) states anything.
- Suites: `vr/tests/test_vr.lua` for the wait on its sync, and `player/vr`'s over a real connection. No headset is involved: they write the messages the engine's VR plugin writes.
