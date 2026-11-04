---
depends_on: [input, cooldown]
conflicts_with: []
exposes: [abilities, abilities/<name>/cooling]
---

# abilities

A player's abilities, generically: each has a key and a cooldown, and what it does belongs to its own mod (`abilities/fireball`). A press of an ability's key starts its cooldown on both sides, so the owner's client has it at once. Each ability mod fires on its own press (`input/game/abilities/<name>` added) while it is not cooling; the cooldown only says when it may fire again, so something else starting it (a debuff) fires nothing. The server reads the owner's press as a synced input action.

## Components

- `abilities = { <name> = { key, cooldown } }`: one entry per ability, on the player. Each ability mod writes its own entry and removes it when it goes. Missing fields get defaults:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `key` | the `KeyCode` that fires it | none: an entry without a key is never bound |
  | `cooldown` | seconds before it fires again | 1 |

  Synced from the server, to the owner only.
- `abilities/<name>/cooling`: present on each side while that ability cools down, as a `cooldown` timer. It is not the ability firing: anything may start it. Added and removed through `cooldown`, which never syncs.
- The press is the input action `input/game/abilities/<name>`, written by `input` on the owner's client while the key is held.
- On the owner's client it writes the group `abilities` into `input/game` (the bindings, client data). On the server it adds each action's entry to the player's `core/net/sync`: `{ authority = "client", target = "owner" }`. The mod that reads another mod's data across the network declares its sync.
- An entry that goes loses its binding, its sync entry and its cooldown. If `abilities` is removed from an entity that stays, all of them go.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First (both) | `abilities/init` | Fill in a missing `cooldown`; stop the cooldown of an entry that went |
| Update (both) | `abilities/cool` | On a press, start that ability's cooldown: the ability fires |
| First (both) | `abilities/removed` | When `abilities` is removed from an entity that stays, stop its cooldowns |
| First (server) | `abilities/sync` | Declare each ability's action for sync; drop entries for abilities that went |
| First (server) | `abilities/unsync` | When `abilities` is removed from an entity that stays, take off the action sync entries |
| First (client) | `abilities/bind` | Bind each ability's key into `input/game.abilities` on the local player; again when `input` is added, and when the abilities change |
| First (client) | `abilities/unbind` | When `abilities` is removed from an entity that stays, remove the bindings |

## Use

```lua
-- an ability mod registers itself on the player...
commands:entity(player):patch({ abilities = { fireball = { key = "KeyQ", cooldown = 1 } } })

-- ...and fires on its own press while it is not cooling (the cooldown that same press
-- starts shows from the next frame)
app:add_systems(Update, {
    Query[{
        added = { "input/game/abilities/fireball" },
        with = { "abilities/fireball" },
        without = { "abilities/fireball/cooling" },
    }],
    Commands,
}, function(pressed, commands)
    for _, e in ipairs(pressed:iter()) do
        -- fire
    end
end):in_set("abilities/fireball/fire")
```

## Notes

- A press fires once. Holding the key, or pressing another ability while it is held, does not fire it again. A press while it cools starts nothing: `cooldown` never restarts a running timer.
- The action columns come from data: each pass reads every player's ability names, as `input` reads its bindings.
- An ability mod is not a subclass of `abilities` (no `base`). `mod_registry` allows one child per base on an entity, and a player has many abilities. Each one registers its entry by data instead.
- No client prediction yet: what an ability does happens on the server.
