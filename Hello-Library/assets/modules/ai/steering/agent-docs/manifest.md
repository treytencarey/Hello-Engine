---
depends_on: [ai/nav]
conflicts_with: []
exposes: [ai/steering, ai/steering/state]
---

# ai/steering

Walks an agent along its path from `ai/nav/path`, keeps it apart from its neighbours and says how it went. It writes `Velocity3d` and lets Rapier move the body, as a walking player does, so agents and players collide alike. Server only; nothing syncs.

## Components

- `ai/steering = { ... }`, on each agent. Whoever wants another speed patches `speed`, and it applies at once. Missing fields get defaults when it is added:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `speed` | metres per second | 2 |
  | `arrive_radius` | metres from the last waypoint that count as there | 0.9 |
  | `pass_radius` | metres from any other waypoint that count as past it | 0.7 |
  | `height_radius` | metres of height from a waypoint that count as on its floor | 1.5 |
  | `ease_radius` | metres from the last waypoint at which it starts slowing | 2.25 |
  | `ease_floor` | the share of its speed it slows to | 0.25 |
  | `separation_radius` | metres within which a neighbour pushes it away | 1.5 |
  | `separation_strength` | how hard a neighbour pushes, as a share of its speed | 1.2 |
  | `turn_speed` | how fast it turns to face where it goes, per second | 6 |
  | `stall_sample` | seconds between checks that it is getting anywhere | 0.5 |
  | `stall_distance` | metres it must cover between checks | 0.25 |
  | `stall_timeout` | seconds without getting anywhere before it is blocked | 1.5 |

- `ai/steering/state = { status, cursor, for_solved, stall_x, stall_z, stall_t, stuck_for }`. `status` is `"idle"`, `"moving"`, `"arrived"` or `"blocked"`. `for_solved` is the `ai/nav/path` `solved_id` the progress belongs to, so a reader can tell it from a stale `"arrived"`. It goes with `ai/steering`, by `mod_registry`.
- `Velocity3d`: added with `ai/steering` when the entity has none, and left in place when it goes.

It reads `ai/nav/path = { solved_id, path = { { x, z }, ... } }`; a new `solved_id` starts from the first waypoint.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/steering/init` | On an added `ai/steering`, fill in missing fields, and add `Velocity3d` and `ai/steering/state` if there are none |
| First | `ai/steering/removed` | When `ai/steering` is removed from an entity that stays, stand it still |
| Update | `ai/steering/start` | On a changed `ai/nav/path` with a new `solved_id`, or new state, start from the first waypoint |
| Update | `ai/steering/walk` | Polls: walk to the next waypoint, write `Velocity3d` and the Transform's rotation, keep apart from neighbours, check for a stall |
| Update | `ai/steering/stop` | When `ai/nav/path` is removed, stand it still and go idle |

## Use

```lua
-- on the server, on an agent with a body
commands:entity(agent):patch({ ["ai/steering"] = { speed = 3 } })

-- how it is going: read in a declared query
Query[{ changed = { "ai/steering/state" } }]
```

## Notes

- `ai/steering/state` is written only when something changes, and its stall check is sampled, so a walking agent writes it twice a second at most.
- Each of `"idle"` from an empty path, `"blocked"` and `"arrived"` stands it still, and then it stops writing `Velocity3d`, so whatever else moves the body can.
- `pass_radius` stays under the 1 m a bake of `ai/nav/volumes` leaves around a cliff at its default `cell`: turning in from further out cuts the corner of what the margin goes around, and stalls against it.
- It moves the body by `linvel` x and z only, and Rapier handles height. A waypoint on another floor is not reached until the height is within `height_radius`, so one it cannot get to ends in `"blocked"`, not `"arrived"`. A storey needs to be further than `height_radius` plus the height of an agent's centre above its floor.
- It reads positions from `Transform`, so an agent is a root, never a child of something that moves.
- Separation looks at every other agent with a path, once per frame each: cost grows with the square of agents walking.
