# Mod standard

DRAFT. Only agreed rules are listed. Open questions are at the end.

## Goal: a mod is an isolated unit

A mod's Lua memory is private. Everything it shares with other mods goes through the engine: components that hold plain data, and events. Mods written this way can be hot reloaded safely, reviewed on their own, and later run in parallel inside one world.

## Components

- A component's name is the mod's path. A mod's own data lives in sub-components named `<mod>/<data>`, which are removed with the mod: `mod_registry` removes them when the mod's component leaves an entity that stays.
- Component values are plain data: tables, strings, numbers, booleans. Never functions or userdata.
- An entity is stored only as an entity value (what `id()` gives), never as a number (`bits()`). A link with a reverse side is `ChildOf` or a declared relationship; a single shared entity is found with `limit = 1`. See Links between entities.
- Nothing syncs unless the mod's return value declares `core/net/sync`.
- The mod that reads another mod's data across the network declares that data's sync, in its server half, on the entity: `abilities` adds `["input/game/abilities/<name>"] = { authority = "client", target = "owner" }` to the player's `core/net/sync`. The mod that produces the data stays unaware of the network. `target = "owner"` lets only the owner learn the entry and only the server receive the value.
  - One exception: data a mod writes onto an entity it spawns, which clients need from that entity's first frame, is declared in the spawn itself, so it rides the first spawn: `abilities/fireball` spawns its projectile with `["core/net/sync"] = { ["projectile/caster"] = { authority = "server" } }`. A sync added later by a system can reach clients a frame or two after the entity.
- A sub-component (`<mod>/<data>`, no directory of its own) is data and is never synced: only a mod's own component carries its sync declaration. Data other mods write for the client to use, such as input bindings, is written in their client half.
- A state that is on or off (an action held, a mode in use) is a component that exists while it is on. Consumers read it with `with`, `added` and `removed`, never through a boolean field.

## Ownership

- The mod that adds a component removes it, and its design says when: the owning entity removed, the entity despawned, the request served or cancelled.
  - One exception, Bevy's required components: an engine component a mod's `<Mod>Init` adds because the mod needs it and the entity has none (`MovementInit` adds `Velocity3d`) stays when the mod's component goes. Another mod may have added it on another side (the spawner gives the server's player its `Velocity3d`), so removing it would take what another mod added.
- To use another mod, write a request entry into that mod's component (`cooldown = { [name] = { remaining = 3 } }`). The owning mod does the work and removes the entry.
- A provider gives its component its full shape when it sets up. Consumers tolerate fields a provider has not filled yet (`ct.entered or {}`).
- A write must never recreate something its owner removed.
- Ownership follows the hierarchy: children go with their parent, whoever spawned them. A mod that puts its entity inside another mod's UI spawns it there when that UI appears (`added = { "sidebar/bar" }`, the parent found with `limit = 1`), and spawns it again when a new one appears (a reload of the other mod). An entity moved under another mod's entity after its spawn frame becomes that mod's (a notification moved under its overlay).

## Links between entities

A link between entities must survive crossing to another world or over the network, and must be cleaned up when either side goes. The engine enforces this; a mod never builds a link itself.

### Entity values

In the engine, not yet in a release. Ported from Bevy's `Entity` type and its `MapEntities`.

- `id()`, a spawn builder's `:id()`, `world:resolve_id()`, `ChildOf` and `Children` reads, raycast hits, event fields and engine-written lists (`collision_trigger.entered`, a relationship's target list) give an **entity value**, never a number.
  - It compares with `==`, and works as a table key: the same entity is always the same value.
  - It prints as `12v3` (`tostring`, `..`, `%s`). `%d`, arithmetic, `<` and `tonumber` raise an error.
  - `bits()` gives the number, for a log line or a name an outside system needs (a socket name, a request id). A number is never a link: never store `bits()` to find the entity again.
  - A spawn builder's `:id()` is the real entity at once, as Bevy's `Commands::spawn` reserves one.
- An entity value may be stored in a component: `projectile/caster = { entity = player:id() }`.
  - When the entity it names despawns, the engine takes it out of every component that holds it: the field becomes absent, a list closes up, with an ordinary `changed` edge.
  - In a `WorldShared` component it crosses to another world as the same entity (its source or mirror there). One whose entity is not shared arrives without it, and arrives with it once that entity is shared.
  - Over the network it crosses by the entity's net id and arrives as the receiver's replica of that entity. One whose entity is not replicated arrives without it, and arrives with it once that entity replicates; one whose entity has not reached the receiver yet lands once it has.
- Every API that takes an entity (`get_entity`, `despawn`, `with_parent`, `ChildOf = ...`, `iter_many = { ... }`, the hierarchy walks) takes an entity value. It also takes a number for now, while old mods move.
- Bevy's `ChildOf` (with `Children`) is the relationship for a child that belongs to its parent and goes with it: an eye and its carrier, a card and its overlay, a button and its bar. A child follows its parent's transform and, for UI, its camera.
- A physics body that moves on its own is never a child of something that moves. Rapier writes the body's pose back relative to its parent, and a moving parent drags it along (measured: a projectile 10 m off course in 1 s). A projectile is a root.
- Any other link that needs a reverse side or a rule for when its target goes (a projectile and its caster, an agent and its target) is a declared relationship.

### Relationships

In the engine, not yet in a release. Ported from Bevy's `#[relationship]` and `#[relationship_target]`. A relationship is two components, each named in full, never derived:

```lua
-- in the owning mod's return value, beside its sync
return {
    relationships = {
        ["projectile/caster"] = { target = "projectile/casts", linked_spawn = false },
    },
}
```

- **The source** holds its target in `entity`, an entity value. Other fields may carry data about the link:

  ```lua
  spawn({ projectile = { ... }, ["projectile/caster"] = { entity = player:id() } })
  ```

- **The target** (`projectile/casts`) lists its sources as entity values, in the order they linked.
  - The engine keeps it: it is added with the first source and removed with the last, with ordinary `added`, `changed` and `removed` edges.
  - Mods read it and never write it. A write or removal from a mod is refused, with a warning in the log.
- **Queries are ordinary,** on either side: `with`, `added`, `changed`, `removed`. To join, read the source's `entity` and look the other side up, as a Rust system does with a second query.
- **When the target despawns,** however it despawns, its sources lose the source component (the default), or are despawned (`linked_spawn = true`). A source that changes its `entity`, loses the component or despawns leaves its old target's list.
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
- A base's fields can be missing for the first frames after it appears: the registry learns of the base when the child loads, adds it as `{}`, and the base's own mod fills its defaults once it loads. A child that reads them skips until they are there (`if cam.distance ~= nil then`); the base filling them is a change, which runs the child again. A system that must act at once starts from a neutral value instead (an eye spawns level).
- Variants of one thing (input modes) are data components, not sub-mods that duplicate code. A field names the variant that applies, the code names none of them, and the query columns come from that data.
- A mod that depends on a mod not yet rewritten waits for it.

## State

- Per-entity state lives on the entity, in the mod's components.
- Tunable numbers (sensitivity, limits, distances) are configuration fields on the mod's own component, with defaults filled in for missing fields when it is added. Not module constants.
- Defaults are filled by one system per mod, `<Mod>Init`, on the mod's component's `added` edge, in `First`: the missing fields of its own component, and any engine component the mod needs that the entity has none of (`MovementInit` adds `Velocity3d`, with the value it starts from). What a mod takes off when its component goes is `<Mod>Removed`.
- No `define_resource`, no globals, and no state in a module that another mod requires.
- State that belongs to no entity is a Bevy resource the mod declares with `commands:init_resource("<mod>/<name>", defaults)` in a system on its component's `added` edge, used through `Res["<mod>/<name>"]` or `ResMut[...]`. It survives a hot reload and goes when the mod unloads.
- A data file (colours, key bindings) is an asset: a Lua asset type the mod declares (`app:init_asset`, `app:register_asset_loader`), read through `Assets[...]`, refilled in place when the file changes.
- A mod may `require` its own stateless function file from its halves. Never another mod's file, and never one that holds state.
- Mods never read the environment (`get_env`, `os.getenv`). Configuration arrives as component data: `core/config` gives a mod its own `<mod>/config` from the host's files.
- Nothing a hot reload would empty: no module-level locals that hold state between runs.

## Systems

- `register_system` is called at the top level of the file, never inside a function.
- Systems react to `added`, `changed` and `removed`. Only timed work polls (retries, cooldowns, timeouts, camera follow).
- A system with an edge query runs that query on every run. Returning early before it (on a timer, a budget or a flag) consumes the edges. Timed or budgeted work goes in its own system.
- Each edge is seen exactly once by every system, whatever its order relative to the writer. A system that errors re-sees everything since its last successful run, so reactions should be safe to repeat.
- Schedules: set up and deliver in `First` or `PreUpdate`, consume another mod's output in `Update` or `PostUpdate`, clear delivered values in `Last`. A consumer never reads another mod's output in the schedule that mod writes it in.
- Per-frame output (input actions) is delivered in `PreUpdate`, so a mod reading it in `Update` needs no `before` or `after` edge to the provider.
- Within a schedule, the only ordering is what `before` and `after` declare. Systems with no declared order may run at the same time; each sees the other's writes on its next run.
- A system that must see other systems' writes in the same frame names every one of them in `after`, even when one name already puts it in the right order today. The list is the contract; the order the scheduler happens to pick is not. A system that can read them a frame later names none.
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
- An entity spawned without a parent (a UI root such as `sidebar/container`) lives until something despawns it, so the mod names that moment: its own `removed` edge (`SidebarRemoved`), or, for one entity that serves every carrier (`notification/overlay`), the mod unloading with its last carrier. A root nobody despawns stays for the life of the world, and an invisible UI root keeps taking the pointer. A UI root that only holds other nodes lets the pointer through (`Pickable = { should_block_lower = false, is_hoverable = false }`).

## Queries and writes

- Setup happens on an `added` edge: one query, with `optional` columns for what the setup reads. Setup that a later change must redo reacts to `changed` (which also fires on add) in the same system. Fill missing config fields only when one is missing: the fill is itself a change, and an unconditional one would run every frame.
- No early-return gates (`if #q == 0 then return end`). The loop over the edge query is the gate.
- Combine `changed` and `removed` handling in one query with `["or"]` where you can. `changed` also fires on add.
- A query answers only the columns it names. Read another entity's data through the query, not `world:get_entity`.
- Read each column into a local first, then use the local (`local entered = e:get("collision_trigger").entered or {}`). Never iterate, index or compare through an inline `e:get(...)`.
- Check presence with `has`, never `get(...) ~= nil`.
- `get()` is read-only. Write with `patch` or `set`; changing a table that `get()` returned is not a write.
- To replace a value that holds nested tables, `set` it. A `patch` merges nested tables, so a key the new value leaves out stays (a clip taken out of a graph's list stayed listed).
- To change a table component bit by bit, patch one key at a time (`patch({ ["input/held"] = { keys = { KeyW = 1 } } })`). `get()` reads pending patches back, so the system sees its own writes without copying anything.
- No general helper functions (`copy`, deep compare). Compare the fields you need directly. Tell kinds of data apart by the fields a value has (`b.key`, `b.motion`), not by comparing strings or checking value types.
- Removing an engine component, reflected or not (`Collider3d`), is `patch({ Collider3d = null })` in the same literal patch as the rest.
- Patch literally: the components a mod needs go in one literal `e:patch({ ... })`, not assembled in a local table.
- Write a constant value where it is used (`rotation = { x = 0, y = 0, z = 0, w = 1 }`), as with component names. No named constants (`local LEVEL = ...`).
- Geometry goes through Bevy's math, written as in Rust. Import a type by its Bevy path at the top of the file, as Rust's `use` (`local Quat = require("bevy::math::Quat")`, or `local bevy = require("bevy::prelude")` for `bevy.Quat`), and call its methods on it (`Quat.from_rotation_y(yaw)`, `Quat.mul_vec3(q, v)` for Rust's `q.mul_vec3(v)`, `Quat.mul_quat`, `Quat.look_to_rh`, `Vec3.normalize`, `Vec3.lerp`). Add vectors with `Vec3.add`. `world:call_static_method` is deprecated. Never rebuild any of it from `math.sin`, `math.cos` or `math.atan`, or component by component; scalar arithmetic is fine. If Bevy has the operation and Lua cannot reach it, ask for it to be exposed.
- Patch the mods an entity needs onto it in the `added` pass, in `First`. Spawn a new entity only when necessary, and then usually `:with_parent` the spawner.
- An entity a mod spawns for another entity is its child (`:with_parent`) and carries the mod's own marker (`camera/first_person/eye`). Find it with the marker among the parent's children (`iter_many = parent:get("Children")`) or descendants (`iter_many = world:descendants(parent)`); never store its id. It then despawns with its parent, and the marker keeps the mod from touching another mod's entities under the same parent.
- Never poll to place one entity relative to another. Parent it; to follow a parent's position without its rotation, use `transform/follow`.
- Move an existing entity with `patch({ ChildOf = parent })`, and make it a root with `patch({ ChildOf = null })`. `patch({ Children = { ... } })` sets exactly those children, in that order (the order UI lays them out in). Both run Bevy's own reparenting.
- One shared entity of a kind (an overlay, a bar) is found with `world:query({ with = { "<mod>/root" }, limit = 1 })[1]`.
- Never move a UI root. Bevy gives every UI node without a parent its own camera source and keeps it after the node gets a parent. Spawn a UI node with its parent, or give an existing entity `Node` in the same patch as its `ChildOf`.
- A mod binds input in a group named after itself (`input/game.first_person`) and unbinds it when its component is removed. Never write into a group another mod also uses. Bindings are `input's` sub-components, so they go when `input` is removed: bind on `added = { "input" }` too, so they come back with it.
- No signal components: never add a component only to say "do X next frame".
- The hierarchy is walked with Bevy's walks (`RelationshipQuery`), over `ChildOf`. Each takes an entity and returns a list of entity values, without the entity it starts from:
  - `world:ancestors(e)`: its parent, grandparent, and so on to the root, nearest first;
  - `world:root_ancestor(e)`: the root (one entity value; `e` itself when it has no parent);
  - `world:descendants(e)`: everything below it, breadth first;
  - `world:descendants_depth_first(e)`: everything below it, each child's subtree before its next sibling;
  - `world:leaves(e)`: the descendants with no children;
  - `world:siblings(e)`: its parent's other children.
- A query reads rows for a list of entities with `iter_many = { ... }` (Bevy's `Query::iter_many`): the rows of the listed entities that match, in the list's order, each once. `limit = 1` keeps the first, so the nearest owner up the tree is `world:query({ with = { "animation/graph" }, iter_many = world:ancestors(e), limit = 1 })[1]`. Walks compose: a walk's list is a list of entities like any other. An empty list matches nothing.
- `entities = { ... }` is deprecated and goes in a cleanup: it matched the listed entities and all their descendants, and `entities = {}` matched every entity. Write `iter_many` with a walk instead.
- An asset (a scene, a clip, a mesh, an image) is a handle from `load_asset`, put on its component by the system reacting to the data (`SceneRoot = load_asset(scene)`). As in Bevy, a changed file re-runs nothing: its handle is refilled in place, so a scene respawns under the same entity, an image redraws and a graph plays the new clip. A file not here yet still gives its handle, which fills in when it lands.
- What a mod computes from an asset's contents (a UI sized from an image, values read from a file) does not update by itself when the file changes: the mod reacts to the change. The Bevy-shaped way to react (asset loaders declared in Lua, an `asset_changed` query filter) is being designed; until it lands, `load_asset_async`'s callback is how a mod reads a raw file and follows its changes (`core/config`). A callback can fire after the entity it was for has gone, and Bevy keeps a child whose parent is gone as a root (it removes the `ChildOf` with a warning).
- Events are allowed, named `<mod>:<event>`. They are local to a world and do not persist the way components do.

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

- Every mod has `agent-docs/manifest.md`: front matter (`depends_on`, `conflicts_with`, `exposes`), then sections Components, Systems (a table of schedule, label and purpose), Use (short examples) and Notes. It describes the mod as it is now, and changes with the code.

## Tests

- Suites use the embedded test helper with phases and `suite.finish`. Never copy the helper into a repository.
- A test proves the real effect (the map built, the answer delivered), not just that a component is present. A mutation of the code under test must turn it red.
- Drive an observer in a suite with `entity:invoke_observer(event_type, event)`: it delivers `event` to that entity's Lua observers at the next queue drain, as a real event would.
- A suite marks its own entities under `zz/` (`zz/zone`), never under the mod's name: `mod_registry` treats `<mod>/<data>` as the mod's parts and removes them with it.
- A suite is green only if its log also has zero Lua errors. A windowed suite exits 0 even when it fails; read the verdict line.
- A mod that renders (meshes, materials, cameras) runs a windowed suite: a headless server has no rendering.
- An engine effect Lua cannot read back (an asset's contents) is tested by recording the call that causes it, with the real call still made.
- To prove a value is written once, count `added` and `changed` edges in a consumer system in the suite.
- To prove where something is, read its world transform after propagation (`call_component_method(id, "GlobalTransform", "compute_transform")`), not its local `Transform`.
- A suite about ownership (a reload or stop, an entity moved between mods) needs no stand-in: every scope, the suite's own root included, links what it spawns. An entity another mod would spawn is linked to that mod's file, `["core/script/owner"] = Instances.script_entity("<path>")`, with that path marked by `Instances.mark_mod_script`. A real reload rewrites the mod's file with the same bytes (`write_file_bytes(path, read_file_bytes(path))`) under an immediate watcher.
- A mod's suite tests its hot reload when the mod builds on what its earlier run left behind, because a reload re-runs its file while the world keeps everything the old run built. That is a mod that spawns or adds components on an edge, loads assets, or keeps its own markers or derived data (`animation/loading`).
  - Edit the mod's own file (a real reload, as above) and check that what it built still works, exactly once: nothing lost, nothing doubled.
  - A mod that loads assets also changes one asset file, and checks that only what used that file is rebuilt.
  - A mod that only reads, or transforms data each frame, needs no reload test.
- A mutation that survives means one of two things: the suite is missing a case (add it), or the mutated code is not needed (delete it). Never leave a survivor unexplained.

## Engine notes

- A reflected enum reads back as a table naming its variant: `RigidBody3d` reads as `{ KinematicPositionBased = true }`.
- Some numeric engine fields read back as strings (`Camera.order`). Convert with `tonumber` before comparing.
- A row a `removed` edge brought in still answers `get()` with the removed value, so a query combining `added` and `removed` cannot tell from `get()` which happened. React to each edge in its own system (`SidebarShow` on `added`, `SidebarHide` on `removed`).
- `Text` reads back as its string, and `ScrollPosition` as `{ x, y }`.
- An engine component without reflection reads back as its bare name (`Collider3d` reads as `"Collider3d"`). Test what it does instead (a ball of radius r rests r above a floor).
- Asset contents cannot be read from Lua; `modify_asset(id, fields)` changes an asset in place.
- After a hot reload, the mod's systems see their own component as `added` again on every carrier, but a state sub-component (`sidebar/open`, `sidebar/button/open`) gets no new edge. What a rebuild draws from such a state, it reads in the setup (`optional = { "sidebar/open" }`).
- Lua sees no `removed` edge for `ChildOf`. React to the edge of the entity that went instead.
- `any_of` columns are readable: `get()` answers them like `optional` ones, so do not list them twice.
- The walks leave out the entity they start from, as Bevy's do; `entities` included it. `root_ancestor` alone answers the entity itself, for a root.
- `load_asset` called from a script's body runs in a coroutine, so a file not here yet waits there; from a system it returns the handle at once. Load from the system that reacts to the data.
- Bevy's own file watcher sees only `assets/`. A library's files land outside it (`../.hello/libraries/<library>/assets`), which is why core reloads a Bevy asset's file itself; a suite whose asset lives in `assets/` passes without core's reload.
- A Bevy generic component is written with its type argument: `["MeshMaterial3d<StandardMaterial>"] = mat`. The bare `MeshMaterial3d` is an alias for whichever instantiation the type registry listed first, which may be another material type. The mesh then draws nothing, and a suite reading the same bare name passes.
- `cooldown` never restarts a running timer: writing its entry again while it runs does nothing. A press while an ability cools starts nothing without a check of its own.
- Bevy has no per-child switch for transform inheritance. A system can run at a Bevy system set by naming it (`before = { "TransformSystems::Propagate" }`); see `transform/follow`.

## Common mistakes

Each was written by an agent and rejected. The wrong form is what to look for; the right form is what to write.

- **Checking presence with `get`.** Wrong: `if e:get("sidebar/open") == nil then`. Right: `if not e:has("sidebar/open") then`.
- **Linking by a field you scan for.** Wrong: `sidebar/container = { player = <id> }`, `notification/card = { owner = <id> }`, then scanning every container for the one whose field names you. Stored as a number (`bits()`) it arrives as a different entity in another world and stays after its entity goes; even as an entity value, the scan is the reverse side a relationship keeps for you. Right: link with `ChildOf` and find it by marker among the parent's children (`iter_many = parent:get("Children")`); make the entity itself the UI node where it can be (a notification is its own card); spawn into another mod's UI where it is (a panel's button into the bar); a single shared entity is found with `limit = 1`. A link that is not parent and child is a declared relationship (Links between entities).
- **Deciding a visible event only on the server.** Wrong: `projectile/explode` checks `collision_trigger` in its `server/` half and spawns a synced `explosion`; clients see the ball pass through the wall until the despawn arrives, and the blast a round trip late. Right: detect the hit in the `shared/` half; every side hides the ball and spawns its own local explosion at once; the server alone despawns the ball and applies what the hit decides.
- **Parenting a moving body to its shooter.** Wrong: `spawn({ projectile = { ... } }):with_parent(player)`. The ball is dragged along as the player moves. Right: a root projectile, linked to its caster through a declared relationship (`["projectile/caster"] = { entity = player:id() }`).
- **A Bevy generic component by its bare name.** Wrong: `MeshMaterial3d = mat`. Right: `["MeshMaterial3d<StandardMaterial>"] = mat`, in the mod and in its suite.
- **One base for many of a kind on an entity.** Wrong: `abilities/fireball` and `abilities/grenade` both with `base = "abilities"` (the second replaces the first). Right: no `base`; each registers its entry in `abilities` by data.
- **Walking up the hierarchy by hand.** Wrong: a loop that reads `ChildOf` through `world:get_entity` until it finds the owner (`carrier_of`). Right: `world:query({ with = { "<the owner's columns>" }, iter_many = world:ancestors(e), limit = 1 })[1]`.
- **One reaction called from several paths.** Wrong: a local `play(world, carrier, fresh)` called from three edge loops, the `fresh` flag telling them apart. Right: gather the edges' entities into one list, then one loop over `iter_many = list` that decides from data (what the player last started is kept on it).
- **Looping a query to pick one entity.** Wrong: `for _, r in ipairs(world:query({ with = { "notification/root" } })) do root = r:id() end`. Right: `world:query({ with = { "notification/root" }, limit = 1 })[1]`.
- **A flag to run a loop body once.** Wrong: `local done = false` ... `if not done then done = true`. Right: `break` after the work.
- **A local function used once.** Wrong: `local function apply(...)` called from one place. Right: write it where it is used.
- **Spawning a default entity, then filling it in another system.** Wrong: `ui/style` spawning `ui/theme = {}` and a second system filling its colors. Right: a mod extends a base and fills it (`ui/theme/dark` with `base = "ui/theme"`), and the world adds the mod it wants.
- **Counters an observer fills for a system.** Wrong: an observer adding to `clicks` or `wheel` and a system acting on them. Right: act in the observer; a suite drives it with `entity:invoke_observer`.
- **Cleaning up what `mod_registry` already removes.** Wrong: despawning your own marked children, or patching your own sub-components to `null`, on your `removed` edge. Right: mark the children with your sub-component and let the registry take them (it also runs when your mod stops with its last carrier, when your own systems do not).
- **Telling `added` from `removed` with `get`.** Wrong: one query over both edges, then `get()` to decide. Right: one system per edge (a removed row still answers `get()`).

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
14. Assets are handles from `load_asset`, refilled in place when their file changes; nothing re-runs, and what the mod computes from an asset's contents reacts to the change itself.
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
25. Every system whose writes a system needs in the same frame is named in its `after`.
26. Rotations and directions use Bevy's math, and constant values are written where they are used.
27. A mod that reads another mod's data across the network declares that data's sync in its server half.
28. Bevy generic components carry their type argument (`MeshMaterial3d<StandardMaterial>`), in the mod and in its suite.
29. An event a client can detect for itself is reacted to on every side in the `shared/` half; the `server/` half holds only what the server alone decides.
30. A mod that spawns or adds on an edge, loads assets, or keeps its own markers has a suite case for its hot reload (and for a changed asset file), checking nothing is lost or doubled.
31. Hierarchy lookups use Bevy's walks and `iter_many`; no hand walk through `ChildOf`, and no new `entities = { ... }`.
32. Defaults are filled in `<Mod>Init`, including any engine component the mod needs that is missing, and what goes with the component in `<Mod>Removed`.

