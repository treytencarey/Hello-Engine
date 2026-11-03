---
depends_on: [ai/agent, ai/perception, ai/nav, ai/steering]
conflicts_with: []
exposes: [ai/debug, ai/debug/label, ai/debug/labels]
---

# ai/debug

Draws what an agent is thinking. The server half publishes it in the mod's own component, the one place an agent's insides reach the network, and it is opt-in: put it on the agent. It decides nothing, and it names no behaviour: what is chosen is the `Name` the option entity gives itself.

## Components

- `ai/debug = { chosen, vision_range, vision_fov_deg, awareness_range, hearing_range, path, seen, sound }`, on an agent. Put it on as `{}`, and the server writes the rest at each thought. `chosen` is absent with none. `path` is what it has left to walk, `seen` and `sound` are where it remembers seeing and hearing things, each a list of `{ x, y, z }`, and each `_count` says how many of that list count.
- `ai/debug/label = { entity = <its agent> }`, on a UI text, on the client: a relationship with target `ai/debug/labels`, `linked_spawn = true`.
- `ai/debug/labels`: an agent's label, kept by the engine.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| Update (server) | `ai/debug/publish` | On a changed `ai/agent/tick`, publish |
| Update (client) | `ai/debug/draw` | Each frame, gizmos: its ranges, the cone it looks in, its path, a post where it saw or heard something |
| Update (client) | `ai/debug/label` | On a changed `ai/debug`, keep one label down the side of the window, saying which entity and what is chosen |
| First (client) | `ai/debug/removed` | When it is removed from an agent that stays, its label goes |

## Use

```lua
commands:entity(agent):patch({ ["ai/debug"] = {} })
```

## Notes

- Removing `ai/debug` on the server takes it off the clients' copies, and the label goes.
