# Auditing a mod

How to check a mod against the mod standard, and how to rate what you find. The rules are in `mod-standard.md`; this page is the procedure. Use it before a mod moves into the library, after the engine or the standard changes, and when reviewing someone's mod.

## What you need

- `mod-standard.md`, read in full, its Common mistakes and its Design review checklist included.
- The engine's Lua API reference, for what each name and method is today.
- The mod: every file, its `agent-docs/manifest.md`, and its suites.
- If you can run the engine: its log (stdout), from a run that loads the mod.

Nothing private is needed. Quote what you read; never report a finding you did not see in a file or a log.

## The ratings

- **Must fix:** the mod breaks a rule of the standard, uses a removed form, or does the wrong thing at run time. Examples:
  - a call the engine no longer has;
  - a Lua error in the log;
  - a system that never runs;
  - a value in the wrong shape;
  - a stored entity id;
  - a function in a component;
  - a credential in the mod's world.

  A suite that cannot fail is a must-fix too: it passes whether or not the rule holds.
- **Should fix:** the mod works and breaks no rule, but drifts from the standard's form. Examples:
  - a header or comment out of style;
  - a require out of place;
  - a deprecated query option;
  - a manifest that no longer matches the code;
  - a name the standard would spell another way.
- **Note:** worth knowing; no change needed now.
- **Unsure:** you cannot tell from what you read. Say what would settle it: a run, a measurement, or a question for the mod's owner.

When two ratings fit, take the higher one.

## The steps

1. **Read the standard first.** Rate against what it says today, not against habits from other engines or older Hello code.
2. **Each file against the Design review checklist,** item by item. For each item, either it holds, or there is a finding with its line. Pay most attention to these:
   - the forms the standard lists as gone;
   - where requires sit;
   - component names as literals;
   - change detection rather than polling;
   - nothing stored that names an entity;
   - no other mod's path required to call its API;
   - no environment reads;
   - static defaults declared in the mod's return value (`defaults`, State), not filled by a `<mod>/init` system, which is only for a fill computed from the world or an engine component the mod adds;
   - a cleanup on a `removed` edge, or anything that edge sets off, writes into another mod's component only while what owns that component stays, read from a column it declares on the row: a write landing after the owner has gone brings the component back, a `null` patch included;
   - no guard in the mod for a field it declares a default for (`if m.speed ~= nil then`). A child reading its base's fields keeps its guard: the base's mod may not have loaded yet.
3. **Engine values in their real shape.** Read any engine component, resource or message the mod reads in the shape the standard's Engine notes give. For example, an enum's unit variant is its name, and a patch changes only what it names. A comparison against another shape is a must-fix: it fails silently.
4. **The suites.**
   - Each case must fail when the rule it checks is removed. To prove it, put the bug back, see the case fail, and restore the fix.
   - Each fixture must match production in the dimension the case tests. A case that sends only a mod's synthetic input proves nothing about the engine's own.
   - Suites use the engine's test helper, never a copy.
5. **The manifest against the code:** every component, message and setting it names, and nothing it omits.
6. **A run, if you can make one.** Read the log for:
   - load errors (`Error loading '<path>'`);
   - Lua system errors (`ERROR bevy_lua_ecs::lua_systems`);
   - the mod's own output.

   A mod that fails to load is often silent on screen. A copy of the library cached from an older version runs first, so check which file actually loaded.

## The report

One table per mod, then the findings:

| Mod | Must fix | Should fix | Notes | Unsure | Suites affected |
|---|---|---|---|---|---|

Each finding gives:
- the file and line;
- a short quote;
- the rule, as the standard's section or checklist item;
- the rating;
- the fix.

Mark anything you inferred rather than read.

## After fixing

Run the mod's suites, and prove each fix the same way as in step 4: put the bug back, see the case fail, restore the fix. A fix without a case that can fail is not done.
