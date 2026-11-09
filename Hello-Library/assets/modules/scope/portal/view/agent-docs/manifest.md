---
depends_on: [scope/portal, core/world/observe, core/compositor/stencil]
conflicts_with: []
exposes: [scope/portal/view]
---

# scope/portal/view

How a portal looks on a client, and the world it shows. A placed portal asks root to observe its target (join-only: observing never starts a world). Root's answer decides: allowed, the target's picture shows through the portal's mesh, drawn from the pose of this player's `camera/3d/eye` (core's pose bridge); refused, the portal is locked and says why. Client only (`client/init.lua`); on a server the component is plain data.

## Components

- `scope/portal/view = { mode }`: `"3d"`, the view brings a sphere of radius 1.2; `"none"`, the carrier brings its own mesh (a glTF door's surface), and the view only puts the stencil on it.
- What it writes: the observe ask (below), `core/compositor/stencil { world = target }` on the mesh that shows the target, `scope/portal/locked { reason }` on the portal, and for `"3d"` the portal's `Mesh3d` and `MeshMaterial3d<StandardMaterial>`.
- The ask, one per placed portal, a child of it: `{ ["core/world/observe"] = { ref = target, libraries = <this world's library records>, hosted = <true while scope/portal/hosted> }, WorldShared = {}, ["core/net/sync"] = false, ["core/script/owner"] = false }`. `libraries` holds copies of this world's own `core/world/library` records (not mirrors), each `{ library, cache, order }`, so the observer world reads the viewer's libraries. Root answers on its own entity, `core/world/observe/answer { ref, state, reason }`.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| Update | `scope/portal/view/client` | Observe: each placed portal whose target is not this world's scope keeps one ask naming its target; an ask naming another ref (a changed target) or a second one is despawned, and `hosted` is set while the portal has `scope/portal/hosted` and taken out when it goes (`entry("core/world/observe"):and_modify`, so the ask stays and root sees it change). Runs on `scope/portal`, `scope/portal/view` or `scope/portal/hosted` added, `scope/portal` changed, `placement` or `scope/portal/hosted` removed, and this world's own row changing (a promoted world catches up) |
| Update | `scope/portal/view/client` | Settle: from root's answers only (`WorldMirror.world_id == 0`): `allowed` puts `core/compositor/stencil { world = target }` on the portal's mesh and removes `scope/portal/locked`; `refused` removes the stencil and sets `scope/portal/locked { reason }` (`refused` when none is given). With `"none"` and no `Mesh3d` on the carrier, the mesh is each child with a `Mesh3d` (a glTF node's primitives). Runs on an answer added or changed, `scope/portal/view` or `Mesh3d` added, `placement` removed, and this world's own row changing |
| PostUpdate | `scope/portal/view/client` | Look, `"3d"` only: on `scope/portal/view` or `scope/portal/locked` added, the lock changed, or `placement` or the lock removed, give the portal a sphere `Mesh3d` of radius 1.2 if it has none, and a material: red and glowing while being placed (base 1.0, 0.3, 0.1; emissive 2.0, 0.5, 0.1), dim while locked (0.15, 0.15, 0.18), plain while waiting; nothing while the stencil is on, as the stencil owns the material then |
| Update | `scope/portal/view/client` | On `scope/portal/view` removed from an entity that stays: remove the stencil (from the carrier and its mesh children) and the lock, the sphere and its material for `"3d"`, and despawn the portal's asks |

None of these run in a world that only observes (its own `core/world/status` says `observer = true`); a promoted world's row changes, which runs them over every portal it skipped.

## Use

`scope/portal`'s approval gives a placed portal `scope/portal/view { mode = "3d" }`. A scene door names `"none"`:

```json
{ "scope/portal": { "target": "github:treytencarey/hello-backrooms:new-room" },
  "scope/portal/view": { "mode": "none" } }
```

## Notes

- Only root's answer counts: a world's own entity or another world's mirror could say anything. `core/world/load.hosted` is root's own; this mod never writes it.
- Root asks once more after a `not-running` refusal when the ask carries `hosted` (core's `core/world/observe`); a second refusal is final until `hosted` goes and comes back.
- The ask is not reaped with this mod's file, so a reload keeps it and root keeps the observed world loaded. It goes with its portal, with the view, or when the target changes.
- The stencil swaps the mesh's material and, when it goes, leaves none (`core/compositor/stencil`). A `"none"` door that is allowed and then refused shows no surface until its scene respawns; a `"3d"` portal gets the dim material.
- Suite: `tests/test_view.lua`, headless. The look (sphere and colours) needs StandardMaterial assets, which a headless run lacks, and has no case.
