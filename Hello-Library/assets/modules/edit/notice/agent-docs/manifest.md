---
depends_on: [notification, ui/style, cooldown]
conflicts_with: []
exposes: [edit/notice, edit/notice/card, edit/notice/wait, edit/notice/bar]
---

# edit/notice

What is happening to this player's edits, said on screen. Core states each of this VM's uploads in flight as `core/library/upload { path, bytes, total, got, state }`, a child of its library: `"waiting"` while the world's write policy decides, then `"sending"`, with `got` the chunks the world holds. This mod shows a card for each upload of more than one chunk. Local UI: never synced. It needs no version control.

## Components

- `edit/notice = {}`: the carrier. A world's client boot, or a mod it uses (`git/world/served` adds it with its sub-mods), adds it to an entity of its own; the cards go with the mod.
- `edit/notice/card = { path }`: one card for the upload of `path`. An upload still waiting gets its card with the `cooldown` timer `edit/notice/wait` (10 s) and nothing on screen; the card is shown when the timer ends, or at once when the upload starts streaming. Shown, it is a `notification` 320 px wide, and its children are its line (`Text`, styled `text`) and the bar's track (styled `border`).
- `edit/notice/wait`: the timer, while it runs (`cooldown`).
- `edit/notice/bar = {}`: the track's child, the fill (styled `accent`), its width the share of the file the world holds.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update | `edit/notice` | On an upload row's `added` or `changed` edge: a card for it (waiting: with its timer; streaming: shown), or its line and bar redrawn. "Waiting for the world to accept <path>…", then "Sending <path> — x / y MB" |
| Update | `edit/notice` | When a card's `edit/notice/wait` ends: shows it, if its upload is still there and it is not shown yet |
| Update | `edit/notice` | On an upload row's `removed` edge: each card whose upload is gone fades out (`notification.dismiss`), or goes if it was never shown |

## Notes

- An upload of one chunk shows nothing: it is answered within a frame or two. One the world allows within 10 s shows only its progress.
- The bar follows the world's acknowledgements (one every 8 chunks, about 240 KB), not what left this machine.
- Its suite runs headless: it reads the line's `Text` and the bar's `Node` width, not the layout.
