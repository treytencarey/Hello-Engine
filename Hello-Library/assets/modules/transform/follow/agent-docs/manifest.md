---
depends_on: []
conflicts_with: []
exposes: [transform/follow]
---

# transform/follow

A child that follows its parent's position but keeps its own world rotation. Use it for anything that should move with an entity without turning with it: a camera eye, a name tag, a health bar.

## Components

- `transform/follow = { rotation = { x, y, z, w }, offset = { x, y, z } }` on a child (`ChildOf`):
  - `rotation` is the world rotation the child should have;
  - `offset` is where it should sit relative to its parent, in world space.

  The owner of the child writes these; this mod writes the child's `Transform` from them.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| PostUpdate, before `TransformSystems::Propagate` | `transform/follow` | Set each follower's local transform so that, after Bevy propagates transforms, it sits at `offset` from its parent with world rotation `rotation` |

## Use

```lua
commands:spawn({
    Transform = {},
    ["transform/follow"] = {
        rotation = { x = 0, y = 0, z = 0, w = 1 },
        offset = { x = 0, y = 2, z = 0 },
    },
    ChildOf = player:id(),
})
```

## Notes

- Runs every frame over followers only: motion polls.
- The parent's rotation is read from its own `Transform`. That is exact when the parent is a root entity; a parent that is itself a child is followed one frame late.
- The parent's scale is not undone; a scaled parent scales the offset.
- The child's own `Transform` is overwritten every frame. Change `transform/follow`, not the child's `Transform`.
