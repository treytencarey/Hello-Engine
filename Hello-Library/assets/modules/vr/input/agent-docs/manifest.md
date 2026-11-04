---
depends_on: [input]
conflicts_with: []
exposes: [vr/input, vr/input/pose]
---

# vr/input

VR controllers as ordinary input. Each control presses the key or mouse button it is mapped to, through the messages `input` takes from anything that is not a device, so a mod binds its actions into `input/game` or `input/ui` as usual, and walking on the left stick needs no VR code in `movement`. The mod also puts the headset's and controllers' poses on the player, in world space. `player/vr` adds it on the owning client while the player is in VR. It works only on this client's own player (`core/net/local`), and never crosses.

## Components

- `vr/input = { press, release, deadzone, controls }`. Missing fields get defaults when it is added, and `controls` is replaced whole if given:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `press` | how far a trigger or grip goes to press (buttons are all or nothing) | 0.6 |
  | `release` | how far it comes back to let go | 0.4 |
  | `deadzone` | how far a stick goes to count; past it, the stick's strength runs from 0 to 1 | 0.15 |
  | `controls` | `<control> = { key = <KeyCode> }` or `{ button = <MouseButton> }`, with `analog = true` for a strength | below |

  | Control | Default | Control | Default |
  |---------|---------|---------|---------|
  | `left_stick_up` | `KeyW`, analog | `a` | `Space` |
  | `left_stick_down` | `KeyS`, analog | `b` | `Escape` |
  | `left_stick_left` | `KeyA`, analog | `x` | `Tab` |
  | `left_stick_right` | `KeyD`, analog | `y` | `KeyR` |
  | `right_stick_left` | `ArrowLeft`, analog | `right_grip` | `KeyG` |
  | `right_stick_right` | `ArrowRight`, analog | `left_grip` | `KeyH` |
  | `right_trigger` | left mouse button | `left_trigger` | right mouse button |

  Up and down on the right stick scroll, as a wheel does (`input/synthetic_mouse_wheel`).
- `vr/input/held = { <control> = <1, or the strength> }`: what is pressed now.
- `vr/input/pose = { hmd_position, hmd_rotation, hmd_forward, left_position, left_rotation, left_forward, right_position, right_rotation, right_forward }`: the latest pose, in world space (the player's `VmXrRig` applied), replaced with each pose. One writer, read with a query.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First, before `input/held` | `vr/input/raw` | Each `VrInputRaw` control pressed, let go or changed in strength becomes `input/synthetic_key`, `input/synthetic_mouse_button` and `input/analog`; the right stick's up and down become `input/synthetic_mouse_wheel` |
| First | `vr/input/pose` | Writes `vr/input/pose` from the latest `VrPoseInput` |
| First, before `input/held` | `vr/input/removed` | When `vr/input` goes, lets go of every mapped key and button |

## Use

```lua
-- read where the right hand points, in a mod's system
app:add_systems(Update, {
    Query[{
        with = { "vr/input/pose", "core/net/local" },
    }],
}, function(players)
    for _, e in ipairs(players:iter()) do
        local pose = e:get("vr/input/pose")
        -- pose.right_position, pose.right_forward
    end
end)
```

## Notes

- `VmXrRig` trails by a frame: it is written in `Update`, from the player's position and turn. The poses are lifted through what is there.
- That a pose is in tracking space has been read from the engine (its host's tracking root does not move), not measured on a headset.
- Suite: `vr/input/tests/test_vr_input.lua`, with the messages the engine's VR plugin writes. No headset is involved.
