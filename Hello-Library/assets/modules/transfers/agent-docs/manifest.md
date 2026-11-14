---
depends_on: [ui/style]
conflicts_with: []
exposes: [transfers, transfers/icon, transfers/list]
---

# transfers

This VM's files in transit, in a screen corner. Core states each as a child row of its library, local and never synced: `core/library/download { path, total, got }` (bytes: the file's size and what has arrived) for a served file of more than one chunk, from its header until it lands, fails or is abandoned; and `core/library/upload { path, bytes, total, got, state = "waiting" | "sending" }` (`total` and `got` in chunks, `bytes` the file's size) for an edit going up, `waiting` while the world's write policy decides. While any such row of more than one chunk is here, an icon sits in the bottom-right corner; hovering it shows one line per transfer. Local UI: never synced. It needs no version control.

## Components

- `transfers = {}`: the carrier. A world's client boot, or a mod it uses, adds it to an entity of its own; the icon goes with the mod. `git/world/served` adds it, with `edit/notice`, while the world's own content library is the player's checkout.
- `transfers/icon = {}`: the icon, spawned by this mod while a carrier and a transfer are here, despawned when the last transfer goes. A `Button` (so it has `Interaction`), `Node` absolute at 16 px from the right and bottom edges, padding 10/6 px, a 1 px border and 6 px corners, `GlobalZIndex` 610 (above the notifications' 600 on the same edge), styled `icon_bg`, hover `icon_hover`, border `border`. Its children: its count (`Text`, font 12, styled `text`), "<n> down" and "<n> up" joined by two spaces, each part only when non-zero; and the list.
- `transfers/list = {}`: the icon's child, `Node` absolute above it (`bottom` 100%, a 6 px margin, right-aligned), 320 px wide, a column with 6 px gaps, styled `bg` with border `border`. `display = "None"` and no children unless the icon's `Interaction` is `"Hovered"` or `"Pressed"`; then `"Flex"`, with one line per transfer, downloads first, each direction by path. A line is a `Node` column holding its `Text` (font 11) and a 4 px track (styled `border`) whose child, the fill (styled `accent`), is as wide as the share arrived. The text is `"<down|up>  <path>  x / y MB"` (one decimal, MB = 1024 × 1024 bytes; an upload's x is `bytes * got / total`), and an upload still `waiting` adds `", waiting for the world"`, is styled `text_dim` and has an empty bar.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update | `transfers` | On an upload or download row's `added`, `changed` or `removed` edge, a carrier's `added` edge, or the icon's `Interaction` changing: with no carrier or no transfer, the icon despawns; otherwise the icon is spawned (with its count and a hidden list) or its count rewritten, and the list's lines are despawned and drawn again while hovered, or the list hidden |

Rows from a mirror (`WorldMirror`) are not counted.

## Notes

- A row of one chunk counts for nothing: it is answered within a frame or two, and the icon would only flash.
- Rows live in the VM of the library's connection, so a world shows its own content library's transfers (the world's tree, a checkout's included). The shared library's files land in its own `library@` VM, whose rows no world sees.
- A world without `git/world/served` gets no icon unless its boot, or another mod it uses, adds `transfers`.
- The hover is Bevy's `Interaction`, as `ui/style` reads it; with no window it never changes, so the suite sets it.
- Its suite runs headless: it reads the count's and the lines' `Text`, the list's `Node` display and the fills' `Node` width, not the layout.
