---
depends_on: [input, core/net]
conflicts_with: []
exposes: [placement]
---

# placement

A client places an entity it spawned: while the entity carries `placement`, it follows where this client's player points, onto the first collider the ray meets, and every other client sees it move. Left click (the right trigger in VR) confirms it, and the server takes it over. Escape (B in VR) or a right click cancels it, despawning it everywhere.

## Components

- `placement = {}`: on the placed entity while it is being placed. The client that places it spawns it with both it and its `Transform` synced with client authority:

  ```lua
  commands:spawn({
      placement = {},
      Transform = { translation = at },
      ["core/net/sync"] = {
          placement = { authority = "client" },
          Transform = { authority = "client", reliable = false },
      },
      -- the mod being placed, and its own data
  })
  ```

  The spawn is a request (`core/net/predict`). The mod being placed approves it in its server half: it inserts what it vouches for, `placement` and this `core/net/sync` included, and removes `core/net/predict`.

- Confirming is the owner removing `placement`. The removal reaches the server, and the server sets `core/net/sync.Transform` back to `{ authority = "server" }`.

Bindings, on this client's player while it owns an entity being placed:
`input/ui.placement = { confirm = { button = "Left" }, cancel = { key = "Escape", button = "Right", take = true } }`. `vr/input` maps the right trigger to the left button and B to Escape. The cancel takes Escape and the right button, so the sidebar's Escape does nothing while placing.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (client) | `placement/bind` | On an entity of this client's starting to be placed, or `input` arriving while one is: bind `input/ui.placement` |
| First (client) | `placement/unbind` | When `placement` goes and none is left being placed: unbind |
| Update (client) | `placement/follow` | Polls: cast the ray (`vr/pointer/ray` if the player has it, else the mouse through `camera/3d/eye`) with Rapier, skipping the placed entity and the player with what hangs under each, and move the entity to the hit |
| Update (client) | `placement/confirm` | On the confirm action's press, remove `placement` |
| Update (client) | `placement/cancel` | On the cancel action's release, despawn what is being placed |
| First (server) | `placement/taken` | When `placement` goes from an entity that stays, set its `Transform` sync back to the server's authority |

## Notes

- Cancel acts on release, so the Escape is let go before the binding goes: the mode's other bindings of Escape never see it.
- A client sends a component change only for an entity the server has confirmed. A move made while the spawn waits for that would never reach the server, so the entity's `Transform` is marked again once the confirmation lands.
- The entity's `Transform` is sent unreliably while it is placed, so the last move before a confirm can be lost; the server then takes it over where it last heard. A spawner that needs the exact place syncs `Transform` reliably.
- The mouse ray reads the window's physical cursor position: a world VM's camera draws into an image of the window's physical size.
- Suite: `placement/tests/test_placement_net.lua`, over a real connection, with the VR pointer's ray. The mouse ray needs a window and a real cursor, and is not checked.
