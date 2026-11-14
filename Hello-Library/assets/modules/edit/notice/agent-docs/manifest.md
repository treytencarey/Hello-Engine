---
depends_on: [notification, ui/style]
conflicts_with: []
exposes: [edit/notice]
---

# edit/notice

What happened to this player's edits, said on screen. Core records each copy it replaced as `core/library/replaced { path, by = "world" | "me", kept?, both? }`, a child of its library; this mod shows a card for each. Local UI: never synced. It needs no version control. Uploads in flight are not shown here: the `transfers` mod lists them, with downloads.

## Components

- `edit/notice = {}`: the carrier. A world's client boot, or a mod it uses (`git/world/served` adds it with its sub-mods), adds it to an entity of its own.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update | `edit/notice` | On an added `core/library/replaced` (not a mirror), while a carrier is here: a `notification` 320 px wide with a 20 s timeout, owned by no mod (`core/script/owner = false`) so it outlives this one, holding a title (`Text`, font 9, styled `accent`) and a line (font 11, styled `text`). `BOTH CHANGED` says whose newer copy is kept and that the other is in `.hello/held/<kept>`; `MERGED` (`both`, `by = "me"`, no `kept`), that both sides' changes were merged; `REPLACED` (`by = "world"`, no `both`), that the world's newer copy replaced this one (yours in `.hello/held/<kept>` when kept); `WENT UP` (otherwise), that this newer copy went up |

## Notes

- Its suite runs headless: it reads the cards' `Text`, not the layout.
