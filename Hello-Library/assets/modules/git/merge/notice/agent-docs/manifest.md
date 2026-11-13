---
depends_on: [notification, ui/style]
conflicts_with: []
exposes: [git/merge/notice, git/merge/notice/row]
---

# git/merge/notice

What happened to an edit, said to the person who made it: a plain-text `notification` with a title and a line. The git mods use it for a checkout behind its world, a world asked to pull, edits that stay local while the player is signed out, and an edit the world refused. A file both the player and the world changed is said by `edit/notice`, since that outcome is core's and needs no git. Local UI: never synced.

## Components

- `git/merge/notice = { title, text }` on the notification's entity. `title` defaults to `"EDIT"`, `text` to `""`.
- `git/merge/notice/row`: each line, a `Text` child of the notice, the title styled `accent` and the line `text` through `ui/style`.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| First | `git/merge/notice` | On a notice's `changed` edge (which an add is too): its old lines go, and its title and line are spawned as its children |

## Use

```lua
commands:spawn({
    ["git/merge/notice"] = { title = "REFUSED", text = "This world refused your edit of a.txt. It stays in your copy only." },
    notification = { timeout = 20 },
    ["core/script/owner"] = false,
})
```

## Notes

- `return { base = "notification" }`: the base makes the entity a card, runs `timeout` and fades it out.
- A notice spawned with `["core/script/owner"] = false` outlives the mod that spawned it, until its timeout.
- Its suite runs headless: it reads the lines' `Text` and roles, not their layout.
