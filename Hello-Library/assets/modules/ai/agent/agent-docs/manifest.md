---
depends_on: []
conflicts_with: []
exposes: [ai/agent, ai/agent/memory, ai/agent/tick, ai/agent/option, ai/agent/options, ai/agent/chosen]
---

# ai/agent

What makes an entity an agent: a memory, a clock it thinks by, and a choice among the options linked to it. Behaviours are separate mods that each spawn an option entity and keep its score current; this mod puts `ai/agent/chosen` on the highest and names none of them. An archetype brings it, as its `base`. Server only.

## Components

- `ai/agent = { think_hz, hysteresis }`, on each agent. Missing fields get defaults when it is added: `think_hz` 5, the times a second it thinks; `hysteresis` 0.15, how far, as a share, another option must beat the chosen one.
- `ai/agent/memory = { seen = { { entity, at = { x, y, z }, seen_at }, ... }, sound = { { at = { x, y, z }, heard_at }, ... } }`: added with `ai/agent`, written by `ai/perception`, read by behaviours. A reload keeps it.
- `ai/agent/tick = { n, next_at }`: `n` moves each time it thinks, and readers react to its `changed` edge. Its first thought comes at a random point of its interval, so a batch spawned on one frame never all think on one frame.
- `ai/agent/option = { entity = <the agent>, score }`, on an option entity: a relationship with target `ai/agent/options`, `linked_spawn = true`, so options go with their agent.
- `ai/agent/options`: the options of an agent, kept by the engine.
- `ai/agent/chosen`: on the option entity that is chosen, while it is.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `ai/agent/init` | On an added `ai/agent`, add a memory and a clock if there are none |
| First | `ai/agent/clock` | Polls: moves `ai/agent/tick` when `next_at` comes |
| First | `ai/agent/removed` | When `ai/agent` is removed from an entity that stays, nothing is chosen for it |
| PostUpdate | `ai/agent/choose` | On a changed `ai/agent/option` or `ai/agent/options`, choose again |

## Use

```lua
-- a behaviour, for each agent it is on
commands:spawn({
    ["ai/agent/option"] = { entity = agent, score = 0 },
    ["my/behavior/option"] = {},
    Name = "my behavior",
})

-- it enters and leaves on the edges of `ai/agent/chosen` beside its own marker
Query[{ added = { "ai/agent/chosen" }, with = { "my/behavior/option" } }]
Query[{ removed = { "ai/agent/chosen" }, with = { "my/behavior/option" } }]
```

## Notes

- The highest score over 0 is chosen. With every score at 0, nothing is chosen, and nothing is asked of `ai/nav`.
- Between equals the chosen one stays. With none chosen, the first linked wins.
- Another must beat the chosen one by `hysteresis`, so two near equals don't swap at every thought. A chosen option falling to 0 gives way to any above it.
- A behaviour that goes despawns its own option. When a chosen option goes, the next is chosen at once.
- An option's `Name` is for the debug overlay, and nothing reads it to decide anything.
