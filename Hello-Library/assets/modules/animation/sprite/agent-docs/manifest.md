---
depends_on: []
conflicts_with: []
exposes: [animation/sprite, animation/sprite/image, animation/sprite/playing, animation/sprite/motion]
---

# animation/sprite

A character's 2D sprite animation: its sheet, and the clip it plays for what it is doing. The server states the sheet; each client draws it and picks the clip from what it sees its own copy doing. `player/2d/spawner` gives every 2D player one, with the sheet its world names.

## Components

- `animation/sprite = { image, tile_size, columns, clips, speed, scale, z }`: on a character, synced from the server. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `image` | the sheet's path; with none, nothing is drawn and nothing is loaded | none |
  | `tile_size` | `{ x, y }`, a frame's size in pixels | `{ 16, 16 }` |
  | `columns` | frames per row of the sheet | 1 |
  | `clips` | `{ <state> = { frames = { <frame index>, ... }, fps } }`, a clip per state | `idle`, frame 0 |
  | `speed` | what every clip's `fps` is multiplied by | 1 |
  | `scale` | the drawn size, 1 is a pixel per pixel | 1 |
  | `z` | how far above the character it is drawn | 1 |

  A frame index counts from the sheet's top left, row by row, from 0. A state is `walk_<facing>` or `idle_<facing>`, with `<facing>` one of `up`, `down`, `left`, `right`, and `idle` plays for a state with no clip of its own.

- On each client, never synced:
  - `animation/sprite/image = { path, scale, z }`: a child of the character holding the `Sprite`, and what it was built from.
  - `animation/sprite/playing = { state, facing, started }`: the clip it should play, the way it last went, and when the clip started on this world's clock.
  - `animation/sprite/motion = { at = { x, y } }`: where the character was last frame.

  If `animation/sprite` is removed from an entity that stays, `mod_registry` takes these off and despawns the child.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (client) | `animation/sprite/image` | On a changed `animation/sprite` that names an image: spawn the child with `Sprite = { image = asset_server:load(image) }`, or replace it when the image, `scale` or `z` differs from what it was built from |
| Update (client) | `animation/sprite/state` | Polls: from the body's velocity while that says it moves, else its motion since last frame, the state to play and the way it faces. Skips a frame with no time passed |
| Update (client), after `animation/sprite/state` | `animation/sprite/frame` | Polls: the frame the clip has reached, written to the sprite's `rect` only when it differs |

## Use

```lua
-- on the server: a character drawn from a sheet of 13 frames a row of 64 pixels
commands:spawn({
    ["animation/sprite"] = {
        image = "hero.png",
        tile_size = { x = 64, y = 64 },
        columns = 13,
        clips = {
            idle_down = { frames = { 130 }, fps = 1 },
            walk_down = { frames = { 130, 131, 132 }, fps = 10 },
        },
    },
    Transform = { translation = at },
})
```

## Notes

- The motion is the body's `Velocity2d` while that says it moves, else how its Transform moved since last frame. Rapier writes a kinematic copy's velocity at its fixed steps, and a frame holding two steps reads as still, so a copy is also read from its Transform. Moving faster than 0.1 pixels a second is walking. Two clients can play different clips for one character for a moment, where their copies move differently.
- The frame is worked out from when the clip started, so a frame's passing writes only the `rect`, and a state that stays the same writes nothing.
- The sheet is an asset handle (`asset_server:load`). Bevy refills it in place when the file changes or arrives, and nothing here runs again.
- A change to `animation/sprite` replaces only what it names anew: a new image, `scale` or `z` replaces the child, and a new `tile_size`, `columns`, `clips` or `speed` is read by the next frame.
- A headless run has no image loader, and `asset_server:load` refuses the file there, so a client with no window cannot draw one. The state and frame suite holds a sprite as this mod would build it and runs headless; the suite for what builds it runs windowed.
- There is no `animation/action` yet: nothing in 2D plays anything on purpose.
