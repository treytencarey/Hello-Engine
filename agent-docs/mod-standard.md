# Mod standard

DRAFT. Only agreed rules are listed.

## Goal: a mod is an isolated unit

A mod's Lua memory is private. Everything it shares with other mods goes through the engine: components that hold plain data, and events. Mods written this way can be hot reloaded safely, reviewed on their own, and later run in parallel inside one world.

## A mod file

A mod's file is a plugin, as in Bevy: it is handed its `App` and adds its systems to it at its top level.

```lua
local app = ...
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

- `app:add_systems(Schedule, { parameters }, function(...) end)` adds a system. The function is handed its declared parameters, in order, and no world.
- Always there, with no `require`: `Res`, `ResMut`, `Query`, `Commands`, `Mut`, and the schedules `Startup`, `First`, `PreUpdate`, `Update`, `PostUpdate`, `Last`. Every other type is imported at its Bevy path, as Rust's `use` (`local AssetServer = require("bevy::asset::AssetServer")`), or all at once from `require("bevy::prelude")` (`bevy.MessageReader`).
- The parameters:
  - `Query[{ ... }]`, a query over the columns it names, with Bevy's methods: `iter`, `iter_mut`, `get(e)`, `get_mut(e)`, `single`, `single_mut`, `iter_many(list)`, `iter_many_mut(list)`, `contains(e)`, `is_empty`, `count`, and Bevy's hierarchy walks (Queries and writes). `get` and `single` answer as Bevy's `Result`: the row, or nil and why.
  - `Mut["name"]` marks a column the system writes, in any list (`with = { Mut["camera"] }`, `optional = { Mut["Node"] }`).
  - `Res[T]` and `ResMut[T]`: a resource imported at its Bevy path, with its own methods (`time:delta_secs()`). A `&mut self` method needs `ResMut`. `Res["<mod>/<name>"]` is a Lua resource (State).
  - `Commands`: spawning, adding, removing, despawning and parenting (Queries and writes).
  - `MessageReader[T]` and `MessageWriter[T]`, T a message type at its Bevy path (`bevy.MessageReader[KeyboardInput]`, `KeyboardInput` from `require("bevy::input::keyboard::KeyboardInput")`), or `LuaCustomEvent` for a Lua message (Queries and writes).
  - A Bevy system parameter that is neither a resource nor one of these is imported and declared as itself: `local ReadRapierContext = require("bevy_rapier3d::plugin::ReadRapierContext")`, then `{ ..., ReadRapierContext }` and `rapier:cast_ray(...)`.
- A parameter works only during its own system's run, as a Bevy parameter cannot outlive it. Never keep one in a local for later.
- A mod's systems declare their parameters. `World`, Bevy's exclusive world, is for the engine's own internals and for suites.
- The `register_system`, `spawn`, `despawn` and `load_asset` globals and the `world:call_*` methods are gone.
- Besides the parameters, a mod uses `require` of its own stateless function file, `null` (a nested key taken out), and `world_id` (this VM's id). Forbidden in mods: `World`, `require_async`, `_raw_fns`, `_exec_ctx`, `__shared_*`, `vm.*`, `get_env`, `os.getenv`, `define_resource`, `create_asset`, and new globals. If a mod needs one, ask for the missing word instead of reaching in.

## Components

- A component's name is the mod's path. A mod's own data lives in sub-components named `<mod>/<data>`, which are removed with the mod: `mod_registry` removes them when the mod's component leaves an entity that stays.
- Component values are plain data: tables, strings, numbers, booleans, entity values and handle values. Never functions or other userdata.
- A component name, and a set name, is written as its string literal at every use: `Query[{ with = { "cooldown/left" } }]`, never `with = { LEFT }` or a table of names. A name in a variable cannot be found by searching for it.
- An entity is stored only as an entity value (what `id()` gives), never as a number (`bits()`). A link with a reverse side is `ChildOf` or a declared relationship; a single shared entity is the first row of a declared query (`overlays:iter()[1]`). See Links between entities.
- Nothing syncs unless the mod's return value declares `core/net/sync`.
- The mod that reads another mod's data across the network declares that data's sync, in its server half, on the entity: `abilities` adds `["input/game/abilities/<name>"] = { authority = "client", target = "owner" }` to the player's `core/net/sync`. The mod that produces the data stays unaware of the network. `target = "owner"` lets only the owner learn the entry and only the server receive the value.
  - One exception: data a mod writes onto an entity it spawns, which clients need from that entity's first frame, is declared in the spawn itself, so it rides the first spawn: `abilities/fireball` spawns its projectile with `["core/net/sync"] = { ["projectile/caster"] = { authority = "server" } }`. A sync added later by a system can reach clients a frame or two after the entity.
- A sub-component (`<mod>/<data>`, no directory of its own) is data and is never synced: only a mod's own component carries its sync declaration. Data other mods write for the client to use, such as input bindings, is written in their client half.
- A state that is on or off (an action held, a mode in use) is a component that exists while it is on. Consumers read it with `with`, `added` and `removed`, never through a boolean field.

## Ownership

- The mod that adds a component removes it, and its design says when: the owning entity removed, the entity despawned, the request served or cancelled.
  - One exception, Bevy's required components: an engine component a mod's `<mod>/init` system adds because the mod needs it and the entity has none (`movement/init` adds `Velocity3d`) stays when the mod's component goes. Another mod may have added it on another side (the spawner gives the server's player its `Velocity3d`), so removing it would take what another mod added.
- To use another mod, write a request entry into that mod's component (`cooldown = { [name] = { remaining = 3 } }`). The owning mod does the work and removes the entry.
- A provider gives its component its full shape when it sets up. Consumers tolerate fields a provider has not filled yet (`ct.entered or {}`).
- A write must never recreate something its owner removed.
- Ownership follows the hierarchy: children go with their parent, whoever spawned them. A mod that puts its entity inside another mod's UI spawns it there when that UI appears (`Query[{ added = { "sidebar/bar" } }]`, the new entity spawned with `ChildOf` set to the bar), and spawns it again when a new one appears (a reload of the other mod). An entity moved under another mod's entity after its spawn frame becomes that mod's (a notification moved under its overlay).

## Links between entities

A link between entities must survive crossing to another world or over the network, and must be cleaned up when either side goes. The engine enforces this; a mod never builds a link itself.

### Entity values

In the engine, not yet in a release. Ported from Bevy's `Entity` type and its `MapEntities`.

- `id()`, a spawn's `:id()`, `ChildOf` and `Children` reads, raycast hits, event fields and engine-written lists (`collision_trigger.entered`, a relationship's target list) give an **entity value**, never a number.
  - It compares with `==`, and works as a table key: the same entity is always the same value.
  - It prints as `12v3` (`tostring`, `..`, `%s`). `%d`, arithmetic, `<` and `tonumber` raise an error.
  - `bits()` gives the number, for a log line or a name an outside system needs (a socket name, a request id). A number is never a link: never store `bits()` to find the entity again.
  - `commands:spawn({ ... }):id()` is the real entity at once, as Bevy's `Commands::spawn` reserves one; its components land when the commands apply.
- An entity value may be stored in a component: `["projectile/caster"] = { entity = e:id() }`.
  - When the entity it names despawns, the engine takes it out of every component that holds it: the field becomes absent, a list closes up, with an ordinary `changed` edge.
  - In a `WorldShared` component it crosses to another world as the same entity (its source or mirror there). One whose entity is not shared arrives without it, and arrives with it once that entity is shared.
  - Over the network it crosses by the entity's net id and arrives as the receiver's replica of that entity. One whose entity is not replicated arrives without it, and arrives with it once that entity replicates; one whose entity has not reached the receiver yet lands once it has.
- Every API that takes an entity (`commands:entity(e)`, `commands:get_entity(e)`, `add_child(e)`, `ChildOf = e`, `q:get(e)`, `q:contains(e)`, `q:iter_many({ ... })`, the hierarchy walks) takes an entity value, never a number.
- Bevy's `ChildOf` (with `Children`) is the relationship for a child that belongs to its parent and goes with it: an eye and its carrier, a card and its overlay, a button and its bar. A child follows its parent's transform and, for UI, its camera.
- A physics body that moves on its own is never a child of something that moves. Rapier writes the body's pose back relative to its parent, and a moving parent drags it along (measured: a projectile 10 m off course in 1 s). A projectile is a root.
- Any other link that needs a reverse side or a rule for when its target goes (a projectile and its caster, an agent and its target) is a declared relationship.

### Relationships

In the engine, not yet in a release. Ported from Bevy's `#[relationship]` and `#[relationship_target]`. A relationship is two components, each named in full, never derived:

```lua
-- in the owning mod's return value, beside its sync
return {
    ["core/net/sync"] = {
        authority = "server",
    },
    relationships = {
        ["projectile/caster"] = { target = "projectile/casts" },
    },
}
```

- **The source** holds its target in `entity`, an entity value. Other fields may carry data about the link:

  ```lua
  commands:spawn({
      ["abilities/projectile"] = { ... },
      ["projectile/caster"] = { entity = e:id() },
  })
  ```

- **The target** (`projectile/casts`) lists its sources as entity values, in the order they linked.
  - The engine keeps it: it is added with the first source and removed with the last, with ordinary `added`, `changed` and `removed` edges.
  - Mods read it and never write it. A write or removal from a mod is refused, with a warning in the log.
- **Queries are ordinary,** on either side: `with`, `added`, `changed`, `removed`. To join, read the source's `entity` and look the other side up with a second declared query (`q:get(entity)`), as a Rust system does.
- **When the target despawns,** however it despawns, its sources lose the source component (the default, `linked_spawn = false`), or are despawned (`linked_spawn = true`). A source that changes its `entity`, loses the component or despawns leaves its old target's list.
- A source whose `entity` names itself, or an entity that does not exist, loses the component, with a warning.
- One target per source component per entity, as in Bevy. An entity can hold many different relationships.
- `ChildOf` stays the relationship that carries the transform. A declared relationship never does.
- Only the source crosses to another world or over the network, mapped like any entity value; each side keeps its own target list from the sources it holds. To reach clients, the source is synced like any component.
- A declaration with the same source and another target, or a name already used by another relationship, is refused, and the mod registry prints it.

## Mod boundaries

- A mod does one job and is named for it. A display mod does not also build physics; that job goes to the mod that owns it.
- A parent mod never names its child mods. A child may name its parent.
- Mods never couple through each other's components in a filter (`without = { "<other mod>/active" }`). Each mod reacts to its own marker.
- A base's systems process only the base's own component. A child configures the base by writing the base's fields. It never writes its own state into the base under its name, and a base is never told which child it serves.
- A base has one child per entity: a second child of the same base replaces the first. Several of one kind on an entity (a player's abilities) are separate mods with no `base`. Each registers its own entry in a shared data component (`abilities = { fireball = { key, cooldown } }`), removes the entry when it goes, and does its own work on its own input action (`added = { "input/game/abilities/fireball" }`, `without = { "abilities/fireball/cooling" }`). Never on its cooldown starting: anything that starts the cooldown (a debuff) would fire it.
- A child writes its base only once the base is there (`with = { "<base>" }`, and react to `added = { "<base>" }`). Writing it first puts the base on the entity directly, and it then stays when the child is removed. Two children of one base replace each other and the base stays, so a mode switch (first to third person) keeps what the base owns.
- A base's fields can be missing for the first frames after it appears: the registry learns of the base when the child loads, adds it as `{}`, and the base's own mod fills its defaults once it loads. A child that reads them skips until they are there (`if cam.pitch ~= nil then`); the base filling them is a change, which runs the child again. A system that must act at once starts from a neutral value instead (an eye spawns level).
- Variants of one thing (input modes) are data components, not sub-mods that duplicate code. A field names the variant that applies, the code names none of them, and the query columns come from that data (`q:with_columns({ optional = columns })`).
- A mod that depends on a mod not yet rewritten waits for it.

## State

- Per-entity state lives on the entity, in the mod's components.
- Tunable numbers (sensitivity, limits, distances) are configuration fields on the mod's own component, with defaults filled in for missing fields when it is added. Not module constants.
- Defaults are filled by one system per mod, in the set `<mod>/init`, on the mod's component's `added` edge, in `First`: the missing fields of its own component, and any engine component the mod needs that the entity has none of (`movement/init` adds `Velocity3d`, with the value it starts from). What a mod takes off when its component goes is in the set `<mod>/removed`.
- No `define_resource`, no globals, and no state in a module that another mod requires.
- Never mirror a component into a resource. A value that lives on a component is read there: a copy keyed by entity drifts from the component after the next `patch`. The same goes for links: find which buttons have a panel by querying the panels, not from a map kept beside them.
- State that belongs to no entity is a Lua resource the mod declares with Bevy's `Commands::init_resource`, in a system on its component's `added` edge: `commands:init_resource("<mod>/<name>", defaults)`. Systems read it through `Res["<mod>/<name>"]` (`:get()`, `:is_changed()`, `:is_added()`) and write it through `ResMut["<mod>/<name>"]` (`:set(value)`, `:patch(fields)`). Plain data only. It survives a hot reload and goes when the mod unloads.
- A data file (colours, key bindings) is an asset: a Lua asset type and loader the mod registers on its `app`, as Bevy's `App::init_asset` and `register_asset_loader` (`app:init_asset("<mod>/file"):register_asset_loader("<mod>/file", { extensions = { "json" } }, function(bytes, path) return json.decode(bytes) end)`). `asset_server:load(path)` gives its handle, `Res[Assets["<mod>/file"]]:get(handle)` the loader's value, and a component holding the handle sees `asset_changed` when the file loads or changes (`core/config`).
- A mod may `require` its own stateless function file from its halves. Never another mod's file, and never one that holds state.
- Mods never read the environment (`get_env`, `os.getenv`). Configuration arrives as component data: `core/config` gives a mod its own `<mod>/config` from the host's files.
- Nothing a hot reload would empty: no module-level locals that hold state between runs.

## Systems

- `app:add_systems` is called at the top level of the file, never inside a function or a system.
- A mod spawns nothing at its top level. It spawns from a system: on its component's `added` edge, or in `Startup`. A mod's `Startup` system runs once when the module loads and once more after each hot reload, never otherwise.
- A system's first run sees every existing component as `added` and `changed`, so a mod's setup on its own component's `added` edge also covers carriers that existed before the mod loaded. Every `added` handler is safe to run again.
- Systems react to `added`, `changed` and `removed`. Only timed work polls (retries, cooldowns, timeouts, camera follow).
- A system's edge queries answer what changed since its last run, whether or not the run reads them. Returning early before reading one (on a timer, a budget or a flag) consumes its edges. Timed or budgeted work goes in its own system. A `:run_if` condition that is false skips the run and consumes nothing.
- Each edge is seen exactly once by every system, whatever its order relative to the writer. A system that errors re-sees everything since its last successful run, so reactions should be safe to repeat.
- Schedules: set up and deliver in `First` or `PreUpdate`, consume another mod's output in `Update` or `PostUpdate`, clear delivered values in `Last`. A consumer never reads another mod's output in the schedule that mod writes it in.
- Per-frame output (input actions) is delivered in `PreUpdate`, so a mod reading it in `Update` needs no ordering against the provider.
- Ordering is Bevy's, chained on what `app:add_systems` answers. Each system is in one set, named like a component and listed in the manifest: `:in_set("animation/link")`. It orders against other sets with `:after("animation/graph")` and `:before("camera/3d/aim")`, and against a Bevy set imported at its path: `local TransformSystems = require("bevy::transform::TransformSystems")`, then `:before(TransformSystems.Propagate)`. A mod's own sets can be ordered once for all their systems with `app:configure_sets(Update, "animation/play"):after("animation/state")`.
- Within a schedule, the only ordering is what `:after`, `:before` and `app:configure_sets` declare. Systems with no declared order may run at the same time; each sees the other's writes on its next run.
- Commands apply as Bevy applies them, at sync points: a system's writes are seen by every system ordered after it in the same schedule, and by the others once the schedule ends. A system that must see other systems' writes in the same frame names every one of them in `:after`, even when one already puts it in the right order today. The list is the contract; the order the scheduler happens to pick is not. A system that can read them a frame later names none.
- A `shared/` half runs on both the server and the client on purpose: the client runs its own copy for display and prediction, and the server stays the authority through sync.
- A timer the client needs (time left on screen, prediction) starts in the `shared/` half from synced data (`projectile.lifetime`), so it runs on both sides at once; `cooldown` never syncs.
- **Every side reacts at once to what it can see for itself.** An event a side can detect from its own copy (a hit through `collision_trigger`, a timer ending) is handled in the `shared/` half, so the server and every client react in the same frame: the ball stops and hides, its explosion shows. Deciding it only on the server makes every client, the shooter included, watch the ball fly on for a round trip.
  - The server stays the authority for what the event decides beyond the picture: the despawn, damage, score. Only that goes in the `server/` half.
  - A client's reaction is local and reversible: it hides or stops its copy of a synced entity, and never despawns or rewrites it. The server's despawn ends it.
  - A purely visual result (an explosion) is spawned on each side from that side's own detection, and is never synced.
- Halves are for a world's game state: `client/` and `server/` for code that differs by side, `shared/` for code that runs on both sides, whether or not it syncs (`cooldown`, `collision_trigger`). A root `init.lua` is for mods whose components never cross the network: infrastructure (`transform/follow`) and local UI the client adds for itself (`ui/style`, `notification`, `sidebar`, a panel with no server work). It runs wherever its component exists, and never declares sync.
- A mod whose component the server adds needs a `server/init.lua`, even one that only declares sync: the server learns a mod's sync only by loading one of its halves, and without it the client never receives the component. Its UI goes in `client/init.lua` (a panel with server work). If the server has no reason to decide, let the client add the component and make the mod a root `init.lua`.
- A child entity a mod spawns despawns with its parent entity. When the mod's component is removed from a parent that stays, `mod_registry` despawns the parent's descendants marked with one of the mod's sub-components (`map/default/sun`, `camera/3d/eye`) and removes the mod's sub-components on the parent, even when the mod stops with its last carrier. So mark every child you spawn for an entity with your own sub-component, and write no cleanup for them; remove engine components you added to the entity (`Node`, `Mesh3d`) yourself.
- An entity a mod spawns that must outlive the entity spawning it (an explosion spawned from the projectile it ends) is spawned with `["core/script/owner"] = false`. Otherwise it is reaped with the mod when that projectile, the mod's last carrier, despawns. It then despawns itself (its own timer).
- The script is the UI. A UI mod builds its UI on its own component's `added` edge, with no `show`, `hide` or `new` API: adding the component shows it, its removal or the mod's stop takes everything, and a reload rebuilds it. A controller that must outlive the UI (an Escape handler) is its own mod.
- An entity spawned without a parent (a UI root such as `sidebar/container`) lives until something despawns it, so the mod names that moment: its own `removed` edge (`sidebar/removed`), or, for one entity that serves every carrier (`notification/overlay`), the mod unloading with its last carrier. A root nobody despawns stays for the life of the world, and an invisible UI root keeps taking the pointer. A UI root that only holds other nodes lets the pointer through (`Pickable = { should_block_lower = false, is_hoverable = false }`).

## Queries and writes

- Setup happens on an `added` edge: one query, with `optional` columns for what the setup reads. Setup that a later change must redo reacts to `changed` (which also fires on add) in the same system. Fill missing config fields only when one is missing: the fill is itself a change, and an unconditional one would run every frame.
- No early-return gates (`if q:is_empty() then return end`). The loop over the edge query is the gate.
- Combine `changed` and `removed` handling in one query with `["or"]` where you can. `changed` also fires on add.
- A query answers only the columns it names. `get()` and `has()` read the row, so a component the query did not list in `with`, `optional`, `any_of`, `added` or `changed` reads as absent even when the entity has it, and the failure is silent. Name what you read, even when it may be missing (`Query[{ changed = { "animation" }, optional = { "Children" } }]`). Read another entity's data through a declared query (`parents:get(e:get("ChildOf"))`); a mod has no world to read it from.
- Read each column into a local first, then use the local (`local entered = e:get("collision_trigger").entered or {}`). Never iterate, index or compare through an inline `e:get(...)`.
- Check presence with `has`, never `get(...) ~= nil`.
- `get()` is read-only; changing a table that `get()` returned is not a write. Writing is Bevy's `&mut`:
  - A component the entity already has is written through its row: the column is `Mut["name"]`, the row comes from `iter_mut`, `get_mut`, `single_mut` or `iter_many_mut`, and `row:patch({ ... })` or `row:set({ ... })` writes that column and nothing else. A row from `iter` and the rest refuses writes.
  - Everything else is `Commands`: `commands:spawn({ ... })`, and on `commands:entity(e)`: `insert({ ... })` (replaces each component given), `patch({ ... })` (merged when it applies; a nested `null` takes a key out of a component, `patch({ ["cooldown/left"] = { [name] = null } })`), `remove("C")`, `despawn()`, `add_child(child)`, `insert_child(index, child)`, `observe(...)`. A row refuses these, naming the `Commands` call.
- A system never sees its own writes: they apply when its commands apply (Systems). Never read back in the same run what it just wrote.
- To change a component that another system may also write in the same frame, patch it key by key (`commands:entity(e):patch({ ["cooldown/left"] = { [name] = secs - dt } })`). Never replace the whole component (`insert`, `set`): it erases a key the other system patched in the same frame.
- To replace a value that holds nested tables, `insert` it (or `set` it on its row). A `patch` merges nested tables, so a key the new value leaves out stays (a clip taken out of a graph's list stayed listed).
- A command on an entity that is gone warns and is skipped. On an edge where the entity may have despawned (`removed` also fires on despawn), use Bevy's `try_` forms (`try_remove`, `try_despawn`, `try_insert`), or `commands:get_entity(e)`, which answers nil for an entity that is gone.
- No general helper functions (`copy`, deep compare). Compare the fields you need directly. Tell kinds of data apart by the fields a value has (`b.key`, `b.motion`), not by comparing strings or checking value types.
- Removing a component, as in Bevy, is `remove` or `try_remove`, for an engine component too, reflected or not: `commands:entity(e):remove("Collider3d")`, several in one call (`try_remove("Mesh3d", "MeshMaterial3d<StandardMaterial>")`). A component is never removed by patching it to `null`.
- Compare before writing: every write is a `changed` edge and possibly a network send. `insert` or `set` of part of a component erases the rest: `insert({ Transform = { scale = ... } })` loses the translation and rotation.
- Patch literally: the components a mod needs go in one literal `patch({ ... })` or spawn bundle, not assembled in a local table.
- Write a constant value where it is used (`rotation = { x = 0, y = 0, z = 0, w = 1 }`), as with component names. No named constants (`local LEVEL = ...`).
- Geometry goes through Bevy's math, written as in Rust. Import a type by its Bevy path at the top of the file, as Rust's `use` (`local Quat = require("bevy::math::Quat")`, or `local bevy = require("bevy::prelude")` for `bevy.Quat`), and call its methods on it (`Quat.from_rotation_y(yaw)`, `Quat.mul_vec3(q, v)` for Rust's `q.mul_vec3(v)`, `Quat.mul_quat`, `Quat.inverse`, `Quat.slerp`, `Vec3.normalize`, `Vec3.lerp`). Add vectors with `Vec3.add`. Never rebuild any of it from `math.sin`, `math.cos` or `math.atan`, or component by component; scalar arithmetic is fine. If Bevy has the operation and Lua cannot reach it, ask for it to be exposed.
- An engine component's methods are called through its row, on a column the query names: `e.GlobalTransform:compute_transform()`, `player.AnimationPlayer:play(node, options)`. A `&mut self` method needs the column `Mut[...]` on a row from a `_mut` method.
- Patch the mods an entity needs onto it in the `added` pass, in `First`. Spawn a new entity only when necessary, and then usually as a child of the spawner.
- An entity a mod spawns for another entity is its child and carries the mod's own marker (`camera/3d/eye`). Find it with the marker among the parent's children (`suns:iter_many_mut(e:get("Children") or {})[1]`) or descendants (`players:iter_many(players:iter_descendants(e:id()))[1]`); never store its id. It then despawns with its parent, and the marker keeps the mod from touching another mod's entities under the same parent.
- A parent is `ChildOf` in the spawn's bundle, `commands:entity(child):insert({ ChildOf = parent })`, or `commands:entity(parent):add_child(child)`. Each builds Bevy's hierarchy, camera sync included. `commands:entity(parent):insert_child(index, child)` puts a child at a place in the order (the order UI lays children out in). A child is detached with `commands:entity(child):remove("ChildOf")` or `commands:entity(parent):remove_child(child)`; Bevy 0.17 has no `remove_parent`, and `remove_children` is not available in Lua yet.
- Never poll to place one entity relative to another. Parent it; to follow a parent's position without its rotation, use `transform/follow`.
- One shared entity of a kind (an overlay, a bar) is the first row of a declared query: `overlays:iter()[1]` on `Query[{ with = { "notification/overlay" } }]`.
- Never move a UI root. Bevy gives every UI node without a parent its own camera source and keeps it after the node gets a parent. Spawn a UI node and give it its parent in the same system (`container:add_child(commands:spawn({ ... }):id())`), so the parent lands in the flush that spawns it, or give an existing entity `Node` in the same command as its `ChildOf`.
- A mod binds input in a group named after itself (`["input/game"] = { first_person = { ... } }`) and unbinds it when its component is removed. Never write into a group another mod also uses. Bindings are `input's` sub-components, so they go when `input` is removed: bind on `added = { "input" }` too, so they come back with it.
- No signal components: never add a component only to say "do X next frame".
- The hierarchy is walked with Bevy's walks (`RelationshipQuery`), over `ChildOf`, as methods of any declared query. Each takes an entity and returns a list of entity values, without the entity it starts from:
  - `q:iter_ancestors(e)`: its parent, grandparent, and so on to the root, nearest first;
  - `q:root_ancestor(e)`: the root (one entity value; `e` itself when it has no parent);
  - `q:iter_descendants(e)`: everything below it, breadth first;
  - `q:iter_descendants_depth_first(e)`: everything below it, each child's subtree before its next sibling;
  - `q:iter_leaves(e)`: the descendants with no children;
  - `q:iter_siblings(e)`: its parent's other children.
- `q:iter_many(list)` (Bevy's `Query::iter_many`) reads the rows of the listed entities that match, in the list's order, each once. An empty list matches nothing. The nearest owner up the tree is `carriers:iter_many(carriers:iter_ancestors(e:id()))[1]` on `Query[{ with = { "animation", "animation/graph" } }]`. Walks compose: a walk's list is a list of entities like any other, and a list built from edges is one too (`live:iter_many(gone)`).
- An asset (a scene, a clip, a mesh, an image) is a handle from `asset_server:load(path)` on a `Res[AssetServer]` parameter (`local AssetServer = require("bevy::asset::AssetServer")`), put on its component by the system reacting to the data (`SceneRoot = asset_server:load(scene)`). The handle comes back at once, typed by the file's loader. As in Bevy, a changed file re-runs nothing: its handle is refilled in place, so a scene respawns under the same entity, an image redraws and a graph plays the new clip. A file not here yet still gives its handle, which fills in when it lands.
- An asset built in Lua is a Bevy value moved into `Assets<A>` on a `ResMut[Assets[T]]` parameter, which answers its handle: `meshes:add(Cuboid.new(x, y, z))`, `materials:add({ base_color = ... })`, `local graph = AnimationGraph.new()`, `graph:add_clip(clip, 1.0, graph.root)`, `graphs:add(graph)`. A handle is a typed value: put it in a component field, and holding it keeps the asset alive.
- What a mod computes from an asset's contents (a UI sized from an image, values read from a file) does not update by itself when the file changes: the mod reacts to the change, with `asset_changed = { "<the component holding the handle>" }` in a query. It takes an engine component that holds an asset (`Mesh3d`, `Sprite`, `ImageNode`, ...) or a Lua component holding a handle in any field.
- Messages and events are Bevy's, each for its role, and both are named like components, `<mod>/<name>`:
  - A **message** is a buffered stream that systems read: `MessageWriter[T]:write({ ... })`, `MessageReader[T]:read()` (what arrived since this system last read, each message once however far apart its runs). An engine message is read by its type (`MessageReader[KeyboardInput]`). A Lua message is `LuaCustomEvent` (`require("bevy_lua_ecs::custom_events::LuaCustomEvent")`): `w:write({ name = "<mod>/<name>", data = data })`, and a reader filters `m.name`, because every Lua message is that one type.
  - An **event** is a moment a mod tells others about, observed as it happens: `commands:trigger("<mod>/<name>", { entity = e, ... })`, observed with `On["<mod>/<name>"]`.
  - Neither persists the way components do, and both are local to a world. Anything that spawns reacts to a component edge instead: an entity survives a reload, and an `added` query is its reader.
- An observer is Bevy's, declared with `On[...]` like a parameter: `commands:entity(e):observe(On[Pointer[Click]], { params }, function(event, ...) end)` for one entity's events (`On`, `Pointer`, `Click` imported at their Bevy paths), `app:add_observer(On[...], { params }, fn)` for every entity's. The callback gets the event (`event.entity`, its fields) and then its declared parameters. Component lifecycle is `On[Add]["<component>"]`.

## Formatting

- The file opens with a short description, then the component's data laid out one field per line:

  ```lua
  -- cooldown = {
  --     <component> = {
  --         remaining = <seconds>,
  --     },
  -- }
  ```

- A query's table spans lines, one filter per line, unless it names a single component.
- No long comment blocks, no em dashes, no emoji or decorative characters.
- No dates in comments, such as `(owner, <date>)` or `measured <date>`: a comment says why, not when or who decided.
- A comment explains what the code cannot: a reason, a constraint, an engine fact, a non-obvious consequence. Never what the next line does, history, or section banners. What the mod is and how to use it is in `agent-docs/manifest.md`.
- Extend another mod with `return { base = "<mod>" }`.
- A provider tells a consumer about lasting state with a sub-component it adds and removes, `<provider>/<name>`, named from the consumer's entry; the consumer reacts to its `added` and `removed` edges. A moment is an entity event the consumer observes with `On[...]`.
- A sub-mod is a path with its own module folder (`init.lua` or halves). Any other `<mod>/<x>` is a sub-component of `<mod>`, removed with it.

## Docs

- Every mod has `agent-docs/manifest.md`: front matter (`depends_on`, `conflicts_with`, `exposes`), then sections Components, Systems (a table of schedule, set and purpose), Use (short examples) and Notes. It describes the mod as it is now, and changes with the code.

## Tests

- Suites use the embedded test helper with phases and `suite.finish`. Never copy the helper into a repository.
- A suite is an entry script: it takes its `App` from core (`local app = require("modules/core/init.lua")`), spawns its fixtures in `app:add_systems(Startup, { Commands }, function(commands) ... end)`, and inspects the world from systems that take `{ World, Commands }`. A variable a `Startup` system assigns is nil to the suite's top-level code at load.
- A suite waits for a state, not a fixed frame: a command's write lands when the commands apply.
- A test proves the real effect (the map built, the answer delivered), not just that a component is present. A mutation of the code under test must turn it red.
- Drive an observer in a suite with `entity:invoke_observer(event_type, event)` (`scroll:invoke_observer("Pointer<Scroll>", { entity = scroll:id(), event = { y = 3 } })`): it delivers `event` to that entity's Lua observers at the next queue drain, as a real event would.
- A suite marks its own entities under `zz/` (`zz/zone`), never under the mod's name: `mod_registry` treats `<mod>/<data>` as the mod's parts and removes them with it.
- A suite is green only if its log also has zero Lua errors. A windowed suite exits 0 even when it fails; read the verdict line.
- A mod that renders (meshes, materials, cameras) runs a windowed suite: a headless server has no rendering.
- An engine effect Lua cannot read back (an asset's contents) is tested by recording the call that causes it, with the real call still made.
- To prove a value is written once, count `added` and `changed` edges in a consumer system in the suite.
- To prove where something is, read its world transform after propagation (`world:get_entity(id).GlobalTransform:compute_transform()`), not its local `Transform`.
- A suite about ownership (a reload or stop, an entity moved between mods) needs no stand-in: every scope, the suite's own root included, links what it spawns. An entity another mod would spawn is linked to that mod's file, `["core/script/owner"] = Instances.script_entity("<path>")`, with that path marked by `Instances.mark_mod_script`. A real reload rewrites the mod's file with the same bytes (`write_file_bytes(path, read_file_bytes(path))`) under an immediate watcher.
- A mod's suite tests its hot reload when the mod builds on what its earlier run left behind, because a reload re-runs its file while the world keeps everything the old run built. That is a mod that spawns or adds components on an edge, loads assets, or keeps its own markers or derived data.
  - Edit the mod's own file (a real reload, as above) and check that what it built still works, exactly once: nothing lost, nothing doubled.
  - A mod that loads assets also changes one asset file, and checks that only what used that file is rebuilt.
  - A mod that only reads, or transforms data each frame, needs no reload test.
- A mutation that survives means one of two things: the suite is missing a case (add it), or the mutated code is not needed (delete it). Never leave a survivor unexplained.

## Engine notes

- A reflected enum reads back as a table naming its variant: `RigidBody3d` reads as `{ KinematicPositionBased = true }`.
- Some numeric engine fields read back as strings (`Camera.order`). Convert with `tonumber` before comparing.
- A `removed` edge brings its row in the frame after the removal, exactly once, in every query form, whether the entity despawned or the component was removed from an entity that stays. The old value is readable only from `Query[{ ["or"] = { removed = { "X" } }, optional = { "X" } }]`; a plain `removed = { "X" }`, with or without `optional = { "X" }`, reads nil for X. In that `["or"]` form a query that also takes `added = { "X" }` answers a value on both edges, so `get()` cannot tell which happened: react to each edge in its own system (`sidebar/show` on `added`, `sidebar/hide` on `removed`).
- `Text` reads back as its string, and `ScrollPosition` as `{ x, y }`.
- An engine component without reflection reads back as its bare name (`Collider3d` reads as `"Collider3d"`). Test what it does instead (a ball of radius r rests r above a floor).
- An asset is read in Lua as a copy, `Res[Assets[T]]:get(handle)`, and changed in place through `ResMut[Assets[T]]:get_mut(handle)`.
- After a hot reload, the mod's systems see their own component as `added` again on every carrier, but a state sub-component (`sidebar/open`, `sidebar/button/open`) gets no new edge. What a rebuild draws from such a state, it reads in the setup (`optional = { "sidebar/open" }`).
- A `removed` edge for `ChildOf` is seen (after `remove("ChildOf")`, Bevy's `remove_child`, or the parent despawning, which despawns the child too), but `get("ChildOf")` reads nil in every form: the old parent cannot be read back. A reaction that needs the parent reacts to the parent's own edge.
- `any_of` columns are readable: `get()` answers them like `optional` ones, so do not list them twice.
- The walks leave out the entity they start from, as Bevy's do. `root_ancestor` alone answers the entity itself, for a root.
- `asset_server:load` never waits, from a system or anywhere else: a file not here yet answers its handle at once and fills it when it lands. Load from the system that reacts to the data.
- Bevy records asset changes in `PostUpdate`, so an `Update` system sees `asset_changed` the next frame. A component switched to another handle is `changed`, not `asset_changed`.
- Bevy's own file watcher sees only `assets/`. A library's files land outside it (`../.hello/libraries/<library>/assets`), which is why core reloads a Bevy asset's file itself; a suite whose asset lives in `assets/` passes without core's reload.
- A Bevy generic component is written with its type argument: `["MeshMaterial3d<StandardMaterial>"] = mat`. The bare `MeshMaterial3d` is an alias for whichever instantiation the type registry listed first, which may be another material type. The mesh then draws nothing, and a suite reading the same bare name passes.
- `cooldown` never restarts a running timer: writing its entry again while it runs does nothing. A press while an ability cools starts nothing without a check of its own.
- Bevy has no per-child switch for transform inheritance. A system can run before or after a Bevy system set by naming it: `:before(TransformSystems.Propagate)`; see `transform/follow`.

## Common mistakes

Each was written by an agent and rejected. The wrong form is what to look for; the right form is what to write.

- **Checking presence with `get`.** Wrong: `if e:get("sidebar/open") == nil then`. Right: `if not e:has("sidebar/open") then`.
- **Linking by a field you scan for.** Wrong: `sidebar/container = { player = <id> }`, `notification/card = { owner = <id> }`, then scanning every container for the one whose field names you. Stored as a number (`bits()`) it arrives as a different entity in another world and stays after its entity goes; even as an entity value, the scan is the reverse side a relationship keeps for you. Right: link with `ChildOf` and find it by marker among the parent's children (`q:iter_many(parent:get("Children") or {})`); make the entity itself the UI node where it can be (a notification is its own card); spawn into another mod's UI where it is (a panel's button into the bar); a single shared entity is the first row of a declared query. A link that is not parent and child is a declared relationship (Links between entities).
- **Deciding a visible event only on the server.** Wrong: `projectile/explode` checks `collision_trigger` in its `server/` half and spawns a synced `explosion`; clients see the ball pass through the wall until the despawn arrives, and the blast a round trip late. Right: detect the hit in the `shared/` half; every side hides the ball and spawns its own local explosion at once; the server alone despawns the ball and applies what the hit decides.
- **Parenting a moving body to its shooter.** Wrong: `commands:spawn({ ["abilities/projectile"] = { ... }, ChildOf = e:id() })`. The ball is dragged along as the player moves. Right: a root projectile, linked to its caster through a declared relationship (`["projectile/caster"] = { entity = e:id() }`).
- **A Bevy generic component by its bare name.** Wrong: `MeshMaterial3d = mat`. Right: `["MeshMaterial3d<StandardMaterial>"] = mat`, in the mod and in its suite.
- **One base for many of a kind on an entity.** Wrong: `abilities/fireball` and `abilities/grenade` both with `base = "abilities"` (the second replaces the first). Right: no `base`; each registers its entry in `abilities` by data.
- **Walking up the hierarchy by hand.** Wrong: a loop that reads `ChildOf` row by row until it finds the owner (`carrier_of`). Right: `carriers:iter_many(carriers:iter_ancestors(e:id()))[1]` on a query naming the owner's columns.
- **One reaction called from several paths.** Wrong: a local `play(carrier, fresh)` called from three edge loops, the `fresh` flag telling them apart. Right: gather the edges' entities into one list, then one loop over `characters:iter_many(list)` that decides from data (what the player last started is kept on it).
- **Looping a query to pick one entity.** Wrong: `for _, r in ipairs(overlays:iter()) do overlay = r:id() end`. Right: `overlays:iter()[1]`.
- **A flag to run a loop body once.** Wrong: `local done = false` ... `if not done then done = true`. Right: `break` after the work.
- **A local function used once.** Wrong: `local function apply(...)` called from one place. Right: write it where it is used.
- **Spawning a default entity, then filling it in another system.** Wrong: `ui/style` spawning `ui/theme = {}` and a second system filling its colors. Right: a mod extends a base and fills it (`ui/theme/dark` with `base = "ui/theme"`), and the world adds the mod it wants.
- **Counters an observer fills for a system.** Wrong: an observer adding to `clicks` or `wheel` and a system acting on them. Right: act in the observer; a suite drives it with `entity:invoke_observer`.
- **Cleaning up what `mod_registry` already removes.** Wrong: despawning your own marked children, or removing your own sub-components, on your `removed` edge. Right: mark the children with your sub-component and let the registry take them (it also runs when your mod stops with its last carrier, when your own systems do not).
- **Telling `added` from `removed` with `get`.** Wrong: one query over both edges, then `get()` to decide. Right: one system per edge (in the form that reads a removed value, both edges answer one).

## Design review checklist

Before a design is shown, check it against every item, and list the earlier rulings that apply:

1. Several consumers of the same kind on one target (two portals, one player).
2. Several different consumers on one entity.
3. Either side of a relationship despawning.
4. Respawn, reload, or crossing to another world.
5. Both sides: the server's state and the client's copy.
6. Edges: a run that returns early, `removed` also firing on despawn, a re-run after an error.
7. Hot reload of the mod.
8. Cost with many entities.
9. Entities in data are entity values, never `bits()`. Links with a reverse side are `ChildOf` or a declared relationship (Links between entities).
10. Every component the mod adds has a named remover and a moment of removal, and every entity it spawns without a parent has a named despawn.
11. No write recreates something its owner removed.
12. Latest value or every value: a component holds only the latest, so two writes between a consumer's runs lose one.
13. Which processes have the plugin, loader or asset this needs (a headless server has no rendering).
14. Assets are handles from `asset_server:load` or `Assets[T]:add` (never `create_asset`), refilled in place when their file changes; nothing re-runs, and what the mod computes from an asset's contents reacts to the change itself (`asset_changed`).
15. The test proves the real effect, and a mutation turns it red.
16. No component is only a signal.
17. The design lists the earlier rulings that apply and follows each.
18. Green means zero Lua errors in the log.
19. Nothing is shared through Lua memory, and no component holds a function.
20. No mod names its children or filters on another mod's marker, and each mod does one job.
21. The mod has its `agent-docs/manifest.md`, matching the code.
22. Entities the mod spawns are children of what they belong to and carry the mod's own marker; no stored ids. An entity inside another mod's UI is spawned there on that UI's `added` edge, and again for a new one. A body that moves on its own is a root, never a child of something that moves. An entity that must outlive the entity spawning it is `["core/script/owner"] = false`.
23. Tunable numbers are configuration on the mod's component, and query columns are read into locals first.
24. A child reading its base's fields allows for them being missing until the base fills them.
25. Every system whose writes a system needs in the same frame is named in its `:after`.
26. Rotations and directions use Bevy's math, and constant values are written where they are used.
27. A mod that reads another mod's data across the network declares that data's sync in its server half.
28. Bevy generic components carry their type argument (`MeshMaterial3d<StandardMaterial>`), in the mod and in its suite.
29. An event a client can detect for itself is reacted to on every side in the `shared/` half; the `server/` half holds only what the server alone decides.
30. A mod that spawns or adds on an edge, loads assets, or keeps its own markers has a suite case for its hot reload (and for a changed asset file), checking nothing is lost or doubled.
31. Hierarchy lookups use Bevy's walks and `iter_many` on a declared query; no hand walk through `ChildOf`.
32. Defaults are filled in the `<mod>/init` set, including any engine component the mod needs that is missing, and what goes with the component in the `<mod>/removed` set.
33. Every system declares its parameters (no `World` in a mod), and is added at the file's top level; the mod spawns from an `added` edge or `Startup`, never at its top level, and uses nothing on the forbidden list (`require_async`, `create_asset`, `define_resource`).
34. A component two systems write in the same frame is patched key by key, never replaced whole; no system reads back its own writes in the same run.
