# Hello

Hello is a game engine written in Rust on [Bevy](https://bevyengine.org). Game logic is written in Lua, as mods. A mod's file is a plugin in Bevy's shape: it adds systems that declare their parameters, and it works on entities and components.

This repository holds:

- **The Hello Library** (`Hello-Library/`): public Lua mods for worlds, such as players, cameras, movement, abilities, AI agents and UI.
- **The docs for writing mods** (`agent-docs/`).
- **The engine's releases**, which the engine's updater and installers download from.

The engine's source is in a private repository and is not here.

## The library's mods

Mods live in `Hello-Library/assets/modules/`, and a mod's name is its path. Families nest: `camera/first_person` extends `camera/3d`, which extends `camera`. A sample:

| Family | Mods | What they do |
|---|---|---|
| `player` | `player`, `player/spawner`, `player/2d`, `player/vr` | What every player has, and a player for each client that joins |
| `movement` | `movement`, `movement/2d` | Walking and jumping; top-down 2D walking |
| `camera` | `camera/first_person`, `camera/third_person`, `camera/2d`, `camera/vr` | A camera's view state and the mods that drive it |
| `abilities` | `abilities/fireball`, `abilities/grenade` | Abilities with a key and a cooldown, each its own mod |
| `projectile` | `projectile`, `projectile/explode` | A ball launched at a velocity, and what happens when it hits |
| `ai` | `ai/agent`, `ai/nav`, `ai/perception`, `ai/steering`, `ai/behavior/chase` | Agents that run on the server and walk, look, listen and choose what to do |
| `animation` | `animation`, `animation/sprite` | Skeletal animation and 2D sprite animation |
| `ui` | `ui/style`, `ui/theme`, `ui/theme/dark` | UI colors by role, and themes that set them |
| `sidebar` | `sidebar`, `sidebar/profiler`, `sidebar/file_browser` | An icon bar and the panels it opens |
| Single jobs | `input`, `cooldown`, `collision_trigger`, `notification`, `transform/follow`, `map/default` | Input actions, named timers, overlap triggers, toasts, following a parent's position, a flat lit ground |

## How a mod is laid out

A mod is a folder. This is `movement`:

```
movement/
  agent-docs/manifest.md   what the mod is and how to use it
  client/init.lua          runs on clients
  shared/init.lua          runs on the server and on clients
  tests/                   its test suites
  2d/                      a sub-mod, movement/2d, with its own folder
```

A mod with work on the server also has `server/init.lua`. A mod whose components never cross the network has a single root `init.lua` instead of halves (`transform/follow`).

A mod's file adds its systems at its top level. This one is from `cooldown`, with its body shortened:

```lua
local Time = require("bevy::time::Time")

app:add_systems(First, {
    Res[Time],
    Query[{
        with = { "cooldown/left" },
        optional = { "cooldown" },
    }],
    Commands,
}, function(time, running_timers, commands)
    local dt = time:delta_secs()
    for _, e in ipairs(running_timers:iter()) do
        ...
    end
end):in_set("cooldown/tick")
```

## How a project uses a mod

A component's name is a mod's path. A project uses a mod by putting the component with that name on an entity, from a system in its own code. If the mod's folder is in the project or in a library the world reads, the engine's mod registry loads the half for that entity's side, plus `shared/` and a root `init.lua`. The mod unloads after its last carrier has gone.

For example, `ui/theme/dark` goes on any one entity to give a world the dark theme, and `player/spawner` goes on an entity on the server to spawn a player for each client that joins.

A mod is configured through fields on its component. Mods don't require each other's files: they use each other by writing and reading components. Each mod's `agent-docs/manifest.md` lists its components, their fields and defaults, what it depends on, and its systems.

Mods build on core, a Lua layer embedded in the engine. Core is not in this repository, so a manifest can name a dependency under `core/` that has no folder here.

## Getting the engine

Builds are on the [Releases](../../releases) page. The latest, v0.6.7, has:

| Platform | Installer | Zip |
|---|---|---|
| Windows x86_64 | `HelloSetup.exe` | `hello-x86_64-pc-windows-msvc.zip` |
| Linux x86_64 | `install.sh` (the command is in the release notes) | `hello-x86_64-unknown-linux-gnu.zip` |

An installed engine checks this repository's releases when it starts and updates itself to a newer build. Pass `--skip-update` to skip the check. Third-party licenses are in `THIRD_PARTY_LICENSES.html`, next to the executable.

## Docs

- [`agent-docs/mod-standard.md`](agent-docs/mod-standard.md): the rules a mod follows, with common mistakes and a design review checklist.
- [`agent-docs/mod-audit.md`](agent-docs/mod-audit.md): how to check a mod against the standard.
- `agent-docs/manifest.md` in each mod's folder: what that mod does and how to use it.

The engine's Lua API reference and core's own docs are not in this repository.

## Licence

The mods and docs in this repository are licensed under `MIT OR Apache-2.0`, at your option: see [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE). This licence does not cover the engine or its builds, which are proprietary.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
