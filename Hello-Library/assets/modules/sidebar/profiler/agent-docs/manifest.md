---
depends_on: [sidebar, sidebar/panel, ui/style]
conflicts_with: []
exposes: [sidebar/profiler, sidebar/profiler/state, sidebar/profiler/button, sidebar/profiler/view, sidebar/profiler/row]
---

# sidebar/profiler

A sidebar panel showing what this VM's frames cost: FPS, frame time and Lua memory, a line saying what the numbers cover, then a row per Lua system, the costliest first, with its average and its max. A click on a row shows that system's query rows, each with its average.

It reads this VM's `DiagnosticsStore`, which is per VM: it shows the systems of the VM it runs in, and no other VM's.

## Components

- `sidebar/profiler` on the local player, beside `sidebar`. `player/client` adds and removes it. Its fields, with their defaults:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `interval` | seconds between refreshes, by `Time` | 1 |
  | `max_rows` | system rows shown; the rest are counted as "+N more" | 40 |
  | `width` | the panel's width in pixels | 320 |
  | `good_below` | a cost below this, in ms, reads `text_good` | 0.5 |
  | `warn_from` | from this, in ms, a cost reads `text_warn`; between the two, `text` | 2 |
  | `bad_from` | from this, in ms, a cost reads `text_bad` | 8 |

- `sidebar/profiler/state = { open, expanded }` on the carrier, added by this mod when the carrier arrives, if it has none: what the panel keeps through a reload. `open` says whether the panel is open, and `expanded` is the system whose query rows show, by name, absent when none does. It goes with the carrier, and with `sidebar`, as a part of that name.
- `sidebar/profiler/button`: marks this mod's `sidebar/button`, in the bar.
- `sidebar/profiler/view = { next }`: on the panel, a plain `sidebar/panel` in the container, there only while the panel is open. `next` is when the next refresh is due, in seconds of `Time`.
- `sidebar/profiler/row = { rank, name }`: a row's slot, at most `max_rows` of them. A refresh rewrites a slot in place when another system takes its rank; slots are spawned or despawned only when the number of rows shown changes.
- `sidebar/profiler/summary`, `span`, `rows`, `more`, `line`, `name`, `cost`, `query`: mark the rest of the content, in the panel's `sidebar/panel/scroll`.

## Systems

| Schedule | Set | Purpose |
|----------|-------|---------|
| First | `sidebar/profiler/init` | Give a new carrier its state, if it has none, and give it a new one if `sidebar` going took it |
| Update | `sidebar/profiler/add_button` | On a new bar or a new local carrier, spawn the button in the bar, if there is none. A run condition over those edges skips it otherwise |
| Update | `sidebar/profiler/restore` | When the sidebar has made a new button an icon, open it if the state says the panel was open |
| Update | `sidebar/profiler/open` | When the button is opened, spawn the panel in the container and save it open |
| Update | `sidebar/profiler/close` | When a button still here is closed, despawn the panel and save it closed |
| Update, after `sidebar/profiler/close` | `sidebar/profiler/refresh` | Read the store and write the content. A run condition over `Time` and the view skips it until `next`, and while the panel is closed or has no scroll area yet |

## Use

```lua
-- the player's client half, for its local player
commands:entity(player):patch({ sidebar = {}, ["sidebar/profiler"] = {} })

-- a tighter panel, refreshed less often
commands:entity(player):patch({ ["sidebar/profiler"] = { interval = 2, max_rows = 15 } })
```

## Notes

- The numbers are milliseconds per frame over the row's history, which is Bevy's 120 frames: about 2 s at 60 FPS, and a minute at 2 FPS. The line under the summary reads that span from `frame_time` at each refresh, so a number is never mislabelled at a low frame rate. A system that did not run in a frame counts `0.0` for it.
- Rows are read afresh at each refresh and none is kept: a query row leaves the store after 120 idle frames, and a row held past that raises. Reading every row takes a couple of ms, which is why the refresh is timed and does not run while the panel is closed.
- `interval` follows `Time`, whose clock takes at most 250 ms from one frame, so a VM below 4 FPS refreshes less often.
- A click writes `expanded` and brings the refresh forward, so a row opens at once. `expanded` follows the system by name through refreshes as its rank changes. A system that goes shows nothing, and its name stays, so a system that a reload brings back is expanded again. It also stays while the panel is closed.
- A reload keeps the panel. A reload of this mod takes everything it spawned, the button with its `sidebar/button/open` included, and the state on the carrier stays: the new button opens again by the path a click takes, and a change to this mod's UI shows in the open panel. A reload of `sidebar` does the same in its new container. A reload of `sidebar/panel` takes the scroll area, and the next refresh fills the new one.
- Only a button still here closing saves `open = false`: someone closed it, by a click, by Escape or by closing the sidebar. A reload's despawn brings the same `removed` edge, and saves nothing. Another panel opening or closing does not touch this one: the sidebar closes a panel only by Escape on the newest, or all of them when it closes.
- `sidebar` taken off the carrier and added back gives a closed panel: the sidebar closes with it, and its going takes `sidebar/profiler/state`, whose name is under its own.
- It writes no cleanup on the carrier's `removed` edge: the button and the panel are this mod's own spawns, and go with it when it stops with its last carrier. A second local carrier leaving takes nothing.
- Suites: `test_profiler.lua` runs headless, on a real player, with real rows and real clicks on the button and the row. `test_profiler_windowed.lua` covers what needs a window: layout, a click or wheel step landing on a row's text reaching the row or the scroll area, what hover reads, and the panel laid out after a reload.
