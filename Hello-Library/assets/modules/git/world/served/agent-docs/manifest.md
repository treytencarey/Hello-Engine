---
depends_on: [git/collaborators/authorize, git/world/head, git/merge/notice, edit/notice, vault/git, core/process]
conflicts_with: []
exposes: [git/world/served, git/world/served/status, git/world/served/merge]
---

# git/world/served

A world served from git says so in its own boot, and this mod is what that statement brings. Core names no git: who may edit a world's files is the world's policy, so the world states it.

## Components

- `git/world/served = {}`: on the world's boot entity, put there by the boot's `base`. It never crosses the network; each side's boot brings its own half.
  - On a server, its base is `git/collaborators/authorize`, the world's write policy. It also spawns one `git/world/head = {}` as a child of the carrier, which states the world's commit to its players. The child goes with the carrier, or when `git/world/served` leaves an entity that stays.
  - On a client, it adds its two sub-mods to its own entity, `git/world/served/status = {}` and `git/world/served/merge = {}`, and `edit/notice = {}` (the uploads on screen), while this world's own content library is the player's checkout. It removes them when the library stops being one, or when `git/world/served` leaves an entity that stays. The checkout is this world's when the `core/library` whose `ref` is the world's scope (its own `core/world/status`) has `edits = true`, which core sets from the home fact.
  - As it adds them, while the player is signed in, not in both-mode, and root's join record for this world (`core/world/join`) is bound to them, it asks the player's root for the writer proof: `{ ["vault/git/proof"] = {}, ["vault/git"] = {}, Request = {} }`, a child of the carrier. The request owns the ref: root deletes the ref when the request goes, so it stays open while the checkout is this world's, goes when the sub-mods go, and is replaced when root's join record for the world changes (a new ticket names a new ref). Root pushes the ref named by the nonce of the ticket it joined this world on, to the repository it joined, both from its own record; the request names neither. The world's host checks for that ref before it takes the player's first write (`git/collaborators/authorize`).
  - The record is bound to the player when its `requester` is root's `core/player/identity.site_user_id`. A world joined anonymously holds an anonymous ticket until root has the Site sign a new one after the sign-in (`core/world/resolve`), and a push before then would name a ticket the world's host never sees again.
  - As it adds them while the player is signed out, it says once that edits stay local, since `git/world/served/status` then sends nothing. It prints "this world uses your checkout, but you are not signed in — edits stay local until you connect your account", and spawns a `git/merge/notice` with the text "This world uses your checkout, but you are not signed in — edits stay local until you connect your account" (the notice's default title, `EDIT`), `notification = { timeout = 20 }` and `["core/script/owner"] = false`. Signed out means root's `core/player/identity` is here without a `site_user_id`, outside both-mode. With no identity from root yet it says nothing, and a sign-out while the sub-mods are on says nothing either.

## Sub-mods

- `git/world/served/status`: the player's edits to the checkout, read from git.
- `git/world/served/merge`: the world's versions of those files, merged into the checkout.

Each has its own folder and manifest. Neither declares this mod as its `base`: a base has one child per entity, and both ride the same carrier.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update (server) | `git/world/served` | On an added `git/world/served`: spawns its `git/world/head` child |
| Update (server) | `git/world/served` | When `git/world/served` is taken off an entity that stays, despawns that entity's `git/world/head` |
| Update (client) | `git/world/served` | When a carrier, a `core/library` or the world's status row changes: add both sub-mods and `edit/notice` to each carrier while the world's own library is the checkout, and ask for the proof as it adds them, signed in, outside both-mode and with root's join record bound to the player, or say that edits stay local, signed out; remove them otherwise |
| Update (client) | none | When `git/world/served` is taken off an entity that stays, remove both sub-mods and `edit/notice`, and close the proof request |
| Update (client) | `git/world/served` | On a changed root `core/player/identity`, or an added or changed root `core/world/join`, while signed in, outside both-mode and with the join record bound to the player: asks for the proof on each carrier carrying both sub-mods and no open proof request; a changed join record replaces the open request. Runs on those edges |
| Update (client) | `git/world/served` | On a proof reply under a carrier: says it in the log; the request stays. Runs on the reply's edge |

## Use

```lua
-- in a world's world/boot halves
return { base = "git/world/served" }
```

## Notes

- A world whose boot doesn't declare it plays normally, and the asset layer refuses every edit to it.
- Nothing here watches files or reads git: its sub-mods do, and only on the carrier this mod gave them. The one thing this mod asks root for is the proof push.
- The proof is asked each time the sub-mods are added, so a checkout that moves away and back in one join asks again; root pushes the same ref. Signed in and both-mode are read as `git/world/served/status` reads them: root's `core/player/identity` with a `site_user_id`, and root's `core/process` `mode`, from root's own rows only. Signing in while the sub-mods are on asks too: at once when the join record is already bound to the player (a launch signed in, its identity arriving after the sub-mods), else when root's renewed record arrives. Root's identity also changes while signed in for other reasons (a linked account), so each such change asks again unless a request is open; root pushes the same ref. A reload of this mod asks once, as its first run sees root's identity as changed. The request it spawned survives a reload, since closing it would stop root's push.
- Suites run headless. `test_served_server` checks the head child with two carriers: the last carrier leaving unloads the mod, which reaps what it spawned whatever its own cleanup does. `test_served` checks when the carrier carries its sub-mods, not what they do, that the proof is asked once as they are added and stays open once answered, closed when the checkout moves away, that it is not asked signed out or in both-mode, that a sign-in with an anonymous join record asks only once the record is bound to the player, and that the edits-stay-local notice shows once signed out and never signed in.
