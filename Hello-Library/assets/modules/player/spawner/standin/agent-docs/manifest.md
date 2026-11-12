---
depends_on: [player, movement, camera/third_person, core/world/flip]
conflicts_with: []
exposes: [player/spawner/standin]
---

# player/spawner/standin

The player's stand-in in a client world that root shows before the crossing into it is decided. When a player walks into a portal, its client asks root to predict the crossing (`scope/portal`), and root shows the target world at once while the player is still the other world's. In that target world this mod makes a local stand-in of the player where it would arrive, which the player walks on with, until the real player arrives from the target's server and takes its place, or the prediction rolls back. Client only (`client/init.lua`).

## Components

- `player/spawner/standin = {}`: on root's predicted ask, `core/world/flip { scope, predicted = { at, place, look } }`, which the asking client spawns with it, so this mod loads wherever root's ask is mirrored; and on the stand-in made from it. Only a client half, so it runs in client worlds only.
- The stand-in: `player/spawner/standin = {}`, `["core/net/sync"] = false`, `["core/script/owner"] = false`, and once its place is found, `player = {}`, `Transform`, a dynamic capsule body (`RigidBody3d = "Dynamic"`, `Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } }`, `LockedAxes3d = "ROTATION_LOCKED"`, `Velocity3d`), `movement = {}`, `camera/third_person = {}`, `camera` (the player's whole camera, below) and `["core/net/local"] = true`. Its client is the only one that ever sees it.
  - Where: `predicted.place` is the player's world transform relative to the door it walked through; the stand-in stands at the node of this world's map that the door's `at` names, times `place`, so it is as far in front of that node and as turned as the player was at the door. With no `at` (any other portal), at `place` itself.
  - Its camera: `predicted.look` is the player's whole camera as it walked in, with its yaw made relative to the body, so it holds in any frame. The stand-in's `camera` is a copy of it, every field kept (distance, height and offset as well as pitch), with `yaw = look.yaw + <the yaw of its facing>`: a crossing keeps the whole camera, and only the yaw turns with a turned place.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| PostUpdate, after `TransformSystems.Propagate` | `player/spawner/spawn` | While an ask of root's (`WorldMirror.world_id == 0`) carrying `player/spawner/standin` names this world's scope with `status == "predicted"`, and no stand-in has a body: with no stand-in, spawn one at once and make one pass over every `Name` for `at`; with one waiting for its place (the map still landing), check only the `Name`s added since. Once the place is found, or with no `at`, insert the stand-in's body, camera and the rest (above) |
| PostUpdate | `player/spawner/left` | On any `core/world/flip` changed or removed, while a stand-in stands: when no ask of root's naming this world is `predicted` or `promoting`, despawn the stand-ins |
| Update | `player/spawner/spawn` | On `core/net/local` added to a `player` that is not a stand-in (the real player arriving): it takes the stand-in's `Transform` and `camera` (both the owner's, which its client then sends as its own), and the stand-in is despawned |

## Use

Nothing to add by hand: `scope/portal`'s client half puts `player/spawner/standin = {}` on the predicted ask it spawns.

```lua
commands:spawn({
    ["core/world/flip"] = { scope = target, predicted = { at = at, place = place, look = look } },
    ["player/spawner/standin"] = {},
    WorldShared = {},
    ["core/net/sync"] = false,
    ["core/script/owner"] = false,
})
```

## Notes

- Only root's ask counts: any world could share one naming this world.
- The stand-in is not this world's player: it is never synced, and the world net's observer gate keeps a local entity in a world that only watches from making it `owned`, so the stand-in does not make the world look played.
- Lifetime: it stands while root's ask is `predicted`, and through `promoting` (confirmed) until the real player arrives. It goes when the ask fails (`predict-timeout`, `world-vanished`, `promotion-timeout`) or root drops it (another crossing superseded it). A `done` ask is root's pin for the world and stays, so it never counts.
- The real player takes the stand-in's place whether its server handed it over (it arrived at the placed handed Transform) or not (it arrived at a spawn point): either way it stands where the stand-in walked to.
- The stand-in has no model of its own: only its body, its walk and its camera.
- The place is found by `Name` alone, never per frame: one pass when the stand-in is made, and the `Name`s added since while it waits. Root rewrites the ask every frame while it waits for its confirmation, so the ask's own edges cannot say when to make a pass. Only the place's value is kept, never its entity; the first node of that name is the place.
- Suite: `player/tests/test_player_handover_client.lua`, headless: none from a lookalike ask or from root's naming another world; made at once with no body until the place lands, then at the place turned, with the player's whole camera, its yaw turned, local and never synced; kept once confirmed; the real player taking its place and whole camera as it goes; through any other portal where the player stood; and gone when the prediction fails.
