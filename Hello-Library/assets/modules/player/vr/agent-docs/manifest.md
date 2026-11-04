---
depends_on: [vr, vr/input, camera/vr, camera/third_person, movement]
conflicts_with: []
exposes: [player/vr]
---

# player/vr

A player in VR. This mod is the composer: it names what a VR player has, on each side, so that `vr` and the mods below it name nothing. `vr` says when the player's client is in VR; this mod reacts. `player` adds it to every player, and it does nothing until a headset is tracking: a player with no headset keeps its desktop camera.

## Components

- `player/vr = {}`, on a player, added on the server and synced from it. It adds:
  - server, always: `vr`;
  - server, while `vr/active` exists: `camera/vr` in place of `camera/third_person`, and `movement.face = "look"`;
  - the owning client, while `vr/active` exists: `vr/input`.

  When `vr/active` goes, the player gets `camera/third_person` back and `movement.face = "velocity"`. If `player/vr` is removed from an entity that stays, each half removes what it added.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (server) | `player/vr/init` | On an added `player/vr`, add `vr` |
| First (server) | `player/vr/enter` | While `vr/active`, `player/vr` and `movement` are there, on any of them arriving: add `camera/vr`, face the look |
| First (server) | `player/vr/leave` | When `vr/active` goes and `player/vr` stays: add `camera/third_person`, face the velocity |
| First (server) | `player/vr/removed` | When `player/vr` is removed from an entity that stays: remove `vr`; a player in VR gets `camera/third_person` back, and what is no longer a player loses `camera/vr` |
| First (client) | `player/vr/local` | On this client's own player, while `vr/active` is there: add `vr/input` |
| First (client) | `player/vr/local_removed` | When `vr/active` goes: remove `vr/input` |

## Use

A world does not add it: `player` does, on the server. Another mod in the stack joins by a name in the patches here, on the side that needs it.

```lua
-- in `player/vr/enter`, for a mod the server adds while the player is in VR
commands:entity(e:id()):patch({ ["camera/vr"] = {}, movement = { face = "look" } })
```

## Notes

- A camera mod replaces the one it finds under the same base, across levels too, and `camera` stays. So entering only adds `camera/vr`, and leaving only adds `camera/third_person`: `mod_registry` takes off the other on each side, and the eye goes or comes with `camera/3d`.
- The player spends one round trip in third person on entering, as the camera is the server's to choose.
- The swap is written for one desktop camera, `camera/third_person`, the one `player` gives.
- Suites: `player/vr/tests/test_player_vr_net.lua` and `test_player_vr_boot.lua` (poses before the player arrives), over a real connection, with the messages the engine's VR plugin writes. No headset is involved.
