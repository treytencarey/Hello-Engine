---
depends_on: [core/mod_registry]
conflicts_with: []
exposes: [gltf/mod_registry]
---

# gltf/mod_registry

Blender custom properties become components. Put `["gltf/mod_registry"] = {}` on an entity that carries a `SceneRoot`: each key of a node's glTF extras (`GltfExtras`) is inserted on that node as a component, and each key of the scene's own extras (`GltfSceneExtras`, Blender: the scene's custom properties) on the scene's node. A key that names a mod (`collider/mesh`) loads that mod through the core mod registry; any other key (`player/spawner/point`) is plain data for the mod that reads it.

Root `init.lua`: it runs on both sides and declares no `core/net/sync`. Each side spawns the scene's nodes from its own copy of the GLB.

**Names from the map file.** This mod inserts components whose names it reads from the GLB. That is its job: it is how a map loads the mods its objects name, so a Blender property can bring in any mod on the world's ladder. It is an approved exception to writing component names as literals.

## Components

- `gltf/mod_registry = {}`, on the entity that carries the `SceneRoot`. No fields, and nothing kept on it.

| Extras value | Component |
|---|---|
| a table (Blender: a property group, set from Python) | the table, as the config |
| a string holding a JSON object (typed in Blender's UI) | the decoded table |
| anything else (`1`, `true`, `"x"`) | none: a component's config is an object, and add-ons stamp scalar properties on scenes |

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| First | `gltf/mod_registry/apply` | On a node's `GltfExtras` or `GltfSceneExtras` added or changed, with a carrier above it (`carriers:iter_many(carriers:iter_ancestors(node))[1]`), and on every such node below a carrier that gains `gltf/mod_registry`: insert each key as a component |
| First | `gltf/mod_registry/removed` | The carrier loses `gltf/mod_registry` and stays: take each key its nodes' extras name off them; the nodes stay |

## Use

```lua
commands:spawn({
    SceneRoot = asset_server:load("modules/<map>/assets/<map>.glb#Scene0"),
    ["gltf/mod_registry"] = {},
    ChildOf = map:id(),
})
```

In Blender, give an object a custom property named after the component (`player/spawner/point`) and export with File > Export > glTF, **Include > Custom Properties** ticked (off by default).

## Notes

- A re-export refills the scene's handle in place, and Bevy respawns every node with new entities, which arrive as `added` again. A property deleted in Blender never reaches a new node, so nothing is kept to diff against. Identify a node by its `Name`, never its entity.
- Extras changed in place on a live node (only by code) add or replace keys; a key dropped that way stays on the node until the carrier loses this mod or the scene respawns.
- `Name` reads back as written (`fx_floor`), with no quotes to strip.
- Only node and scene extras are read; mesh and material extras (`GltfMeshExtras`, `GltfMaterialExtras`) are not.
- A key whose mod has only a `client/` half lands on the server as plain data.

## Tests

`tests/test.lua`, server side, on a copy of `tests/fixtures/markers.glb` (a Blender export: fx_box `collider/bb`, fx_floor `collider/mesh`, fx_start `player/spawner/point`, fx_view `fx/view`, fx_light `fx/light`, fx_json a JSON-string property, the scene's `fx/look`; the `fx/` names are the suite's own). G1 keys land with their config, the scene's on the scene's node; G2 a JSON string is decoded; G3 names read as written; G4 an in-place edit adds a key and skips scalars; G5 a re-export applies the new nodes and a renamed key leaves its old name on no node; G6 the component added to a loaded scene applies it; G7 taken off, its nodes lose their components and stay; G8 a reload of the mod: the nodes keep their components, and `fx_box` keeps one box.
