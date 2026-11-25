# Starting a new world

A world is a repository whose content starts from `world/boot`. The engine puts `world/boot` on the world's net entity, on the server and on each client, and the world's own `modules/world/boot/server/init.lua` and `modules/world/boot/client/init.lua` spawn its content as children of that entity.

Two declarations look optional, because a world without them still starts and plays. Both are needed, and leaving either out fails quietly.

## Checklist

1. **Both boot halves return `base = "git/world/served"`.** That base lets the world be served from git: a player who can push to the repository edits its files live, and every client gets the edit. Without it the world plays normally, but the asset layer refuses every edit to it, and nothing on screen says so.
2. **The server half declares `core/net/peer/expose` and `core/net/peer/accept`.** `expose` is what an observer looking in through a portal is sent. `accept` is what the world admits from another world, including the parts a player crossing in brings with them. Nothing declared is nothing: a portal into an undeclared world shows an empty view, because the observer is never sent the world's library or map, and a player crossing in arrives without their synced parts.
3. **The server half spawns the libraries it uses**, such as `core/world/library/hello` for the engine library's mods. Spawn them before the mods that come from them.

## Example

```lua
-- modules/world/boot/server/init.lua
app:add_systems(First, { Query[{ added = { "world/boot" } }], Commands }, function(boots, commands)
    for _, e in ipairs(boots:iter()) do
        commands:spawn({ ["core/world/library/hello"] = { order = 1 }, ChildOf = e:id() })
        commands:spawn({ ["player/spawner"] = {}, ChildOf = e:id() })
        -- What a portal shows of this world, and what it admits from others.
        commands:spawn({
            ["core/net/peer/expose"] = { components = "all" },
            ["core/net/peer/accept"] = { components = "all" },
            ["core/net/sync"] = false,
            ChildOf = e:id(),
        })
    end
end):in_set("world/boot")

return { base = "git/world/served" }
```

```lua
-- modules/world/boot/client/init.lua
app:add_systems(First, { Query[{ added = { "world/boot" } }], Commands }, function(boots, commands)
    for _, e in ipairs(boots:iter()) do
        -- Client-only content: UI theme, HUD, anything the server does not send.
    end
end):in_set("world/boot/client")

return { base = "git/world/served" }
```

## Choosing the lists

`components` is `"all"` or a list of component names, such as `{ "map/default", "player" }`. A world's lists are the union of every declaration in it.

- `"all"` exposes every component that has a `core/net/sync` entry to anyone looking in through a portal, and admits every such component from any world. Per-component audiences still apply, so a component synced only to its owner stays with its owner.
- A list shows and admits only the named components. Use one when the world holds something other worlds shouldn't see, or shouldn't be able to bring in.
- `{ components = {} }` declares nothing on purpose.

Only components with a `core/net/sync` entry are filtered. Replication's own components always travel. `core/net`'s manifest has the full rules.
