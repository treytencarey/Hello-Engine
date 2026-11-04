---
depends_on: [core/net, sidebar, sidebar/panel, ui/style]
conflicts_with: []
exposes: [sidebar/file_browser, sidebar/file_browser/state, sidebar/file_browser/request, sidebar/file_browser/answer, sidebar/file_browser/button, sidebar/file_browser/view, sidebar/file_browser/row]
---

# sidebar/file_browser

A sidebar panel showing the files of the world's server, read-only: a tree with folders first, opened and closed by a click, a page at a time. The server half answers; a client asks and sees only what comes back. Nobody changes a file through it.

**Listing isn't available yet.** Reading a folder waits for the engine's redesign of file access through requests. Until then `Listing.read` answers `nil, "not available"`, every path that passes answers `error = "not available"`, and the panel shows "Listing isn't available yet" in the tree. All the rest is real: the requests, the refusals, the bounds, paging and order over a list of entries, expanding, collapsing, and staying open through a reload.

## Components

- `sidebar/file_browser` on a player, added and removed by `player/server` and synced to its owner only (`target = "owner"`): a client never adds it. Its fields, declared in `shared/` because the value crosses whole:

  | Field | Meaning | Default |
  |-------|---------|---------|
  | `width` | the panel's width in pixels | 280 |
  | `page_size` | entries the client asks for at once | 50 |
  | `max_limit` | entries the server answers at once, whatever is asked | 200 |
  | `max_requests` | asks one request may hold; the server refuses a request holding more, whole, with no answer | 16 |
  | `max_path` | longest path the server takes, in bytes | 1024 |

- `sidebar/file_browser/request = { [key] = { op = "list", path, offset, limit } }` on the player: client authority, the owner only. `path` is relative to the world's files, `""` for the top. The client's key is `<offset>:<path>`. The client takes a key out once it has read the answer.
- `sidebar/file_browser/answer = { [key] = ... }` on the player: server authority, the owner only, replaced whole. Each ask has one of:
  - a page: `{ op = "list", path, offset, files = { { name, path, is_directory, size } }, has_more, total_count }`;
  - `{ op = "list", path, offset, error = "not available" }`, for a path that passes while a folder cannot be read;
  - `{ error = "refused" }`, for anything else.
- `sidebar/file_browser/state = { open, expanded = { [path] = true } }` on the carrier, on the client: what the panel keeps through a reload. It goes with the carrier, and with `sidebar`, as a part of that name.
- `sidebar/file_browser/button`: marks this mod's `sidebar/button`, in the bar.
- `sidebar/file_browser/view = { folders = { [path] = { files, has_more, next, unavailable } } }`: on the panel, a plain `sidebar/panel` in the container, there only while the panel is open.
- `sidebar/file_browser/row = { index, kind, path, depth }`: a row's slot. `kind` is `folder`, `file`, `more` or `note`.
- `sidebar/file_browser/rows`, `refresh`, `mark`, `name`, `size`: mark the rest of the content, in the panel's `sidebar/panel/scroll`.

## Systems

| Side | Schedule | Set | Purpose |
|------|----------|-------|---------|
| server | First | `sidebar/file_browser/init` | On a new carrier, list the request and answer in its `core/net/sync` |
| server | Update | `sidebar/file_browser/removed` | When the component goes from an entity that stays, take those entries out |
| server | Update | `sidebar/file_browser/forget` | When the owner took its whole request away, no answer stands |
| server | Update, after `forget` | `sidebar/file_browser/serve` | Refuse, or read and answer, each new ask |
| client | First | `sidebar/file_browser/init` | Give a new carrier its state, if it has none, and a new one if `sidebar` going took it |
| client | Update | `sidebar/file_browser/add_button` | On a new bar or a new local carrier, spawn the button in the bar, if there is none |
| client | Update | `sidebar/file_browser/restore` | When the sidebar has made a new button an icon, open it if the state says the panel was open |
| client | Update | `sidebar/file_browser/open` | When the button is opened, spawn the panel and save it open |
| client | Update | `sidebar/file_browser/close` | When a button still here is closed, despawn the panel and save it closed |
| client | Update, after `close` | `sidebar/file_browser/receive` | Read each answer once into the view, and take its key out of the request |
| client | Update, after `receive` | `sidebar/file_browser/ask` | Ask for what the view lacks, within `max_requests` |
| client | Update, after `receive` | `sidebar/file_browser/render` | Write the rows into their slots, only what changed |

## Use

```lua
-- the player's server half, for every player
commands:entity(player):patch({ ["sidebar/file_browser"] = {} })
```

## Notes

- The file `server/listing.lua` holds `Listing.read` and the stateless functions that need no disk: `is_private`, `visible`, `sorted`, `page`, taking entries `{ name, is_dir, size }`. The mod's files call no file access; a suite checks that.
- The root is this world's `core/world/files`, read by query in the server half and handed to `Listing.read`. It never crosses: every path on the net is relative to it.
- A path is refused if it is not a string or is too long; if it holds a backslash, a colon (a drive, an NTFS stream) or a control character; if a name in it is empty (an absolute path, `a//b`, `a/`); or if a name in it is private. Private, compared as Windows opens a name, in any case and with trailing dots and spaces removed, at any depth: `.` and `..`, `config`, `deploy_keys`, `gateways`, hidden names, and NTFS short names such as `DEPLOY~1`.
- A request that is not a table, an entry that is not a table, an `op` other than `list`, or an `offset` or `limit` that is not a number in range is refused. `limit` is held to `max_limit`.
- There is no bound on how often a client's requests are served: the standard has no form for one. A client can write a new request each frame, and each new ask costs a read.
- Asks are keyed, so two in quick succession both land. A key is asked again only once its old answer has gone from the client's copy: asked sooner, the old answer would read as the new one.
- The server half keeps nothing about a player but the answers it has not taken, on the player, so a reload of it loses nothing. A reload of the client half keeps `state`, the request and the answer on the carrier; the view is its own spawn and goes, and the new one asks again.
- Only a button still here closing saves `open = false`, as in `sidebar/profiler`: a reload's despawn brings the same `removed` edge.
- A folder opened again, and everything on Refresh, is asked for again. A folder emptied on the server stays open and shows nothing. A click on a file or the note does nothing.
- The panel cannot be had by a client adding the component: its write stays on that client, a spawn request stops at a payload nothing approves, and a forged update names a component the server does not list. Suites: `test_listing.lua` for the functions and the file-access rule, `test_file_browser_net.lua` and `test_file_browser_client_cannot_add.lua` over a real connection, `test_file_browser_windowed.lua` for layout and a real pointer.
