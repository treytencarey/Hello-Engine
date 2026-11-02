---
depends_on: [ai/nav/volumes]
conflicts_with: [ai/nav/volumes/box]
exposes: [ai/nav/volumes/scene]
---

# ai/nav/volumes/scene

Walkable volumes authored in a scene: every node at or below the entity whose name holds `include` gets an `ai/nav/volume`, which its base `ai/nav/volumes` bakes. It loads no scene; it reads what the map spawned. Server only; nothing syncs.

## Components

- `ai/nav/volumes/scene = { include }`: the text a node's name must hold, by default `"_nav"`.
- `ai/nav/volume = { hx, hy, hz, scene = true }`, on each matching node. Its half extents are the node's world scale. When `ai/nav/volumes/scene` goes, it takes off those saying `scene = true`, and the nodes stay. It is not a sub-component of this mod, because `mod_registry` despawns a mod's sub-components' entities below its carrier, and those are the map's nodes.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/nav/volumes/scene/tag` | For a new `Name`, or every node below a new or changed `ai/nav/volumes/scene`: a matching node with no volume gets one |
| First | `ai/nav/volumes/scene/removed` | When `ai/nav/volumes/scene` is removed, take off its volumes |

## Use

```lua
-- on the server, on the entity whose scene holds the nodes
commands:entity(map):patch({ ["ai/nav/volumes/scene"] = { include = "_nav" } })
```

## Notes

- A node's size is its world scale times a 2 m cube, the size Blender's default cube has. Author nav volumes without applying transforms before export: applying them bakes the size into the mesh and leaves a scale of 1, a 2 m box however large it looks. Otherwise size them with `ai/nav/volumes/box`.
- A rotated node's box is the axis-aligned box around it.
- It reads `GlobalTransform` in First, which holds the last frame's propagation. A scene's nodes land before that propagation, so theirs is right. A node spawned in First itself, or a `Name` added to a moved entity, reads what it had.
- It extends `ai/nav/volumes`, which has one child per entity: this or `ai/nav/volumes/box`.
