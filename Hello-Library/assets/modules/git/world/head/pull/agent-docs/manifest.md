---
depends_on: [git/world/head]
conflicts_with: []
exposes: [git/world/head/pull]
---

# git/world/head/pull

A player asks the world to pull. A declaration only: `git/world/head`'s client half raises it when the player's upstream holds commits the world's commit lacks, and its server half answers it by asking root to pull the world's own tree.

## Components

- `git/world/head/pull = { sha }`, client authority, to the server only (`target = "owner"`): the world's commit the player compared with. The server pulls only while it is still on that commit.

## Systems

None.

## Use

```lua
-- in git/world/head's client half
commands:spawn({ ["git/world/head/pull"] = { sha = reply.sha }, ["core/script/owner"] = false })
```

## Notes

- On the server it never becomes a component: the transport delivers it inside `core/net/predict` (`requested["git/world/head/pull"]`), and `git/world/head` despawns that.
- The file exists so the name resolves, and to declare its sync.
- It is the one way a player asks the world to pull: any client half that wants one, a Pull button included, raises it with the world's `git/world/head.sha`. The answer is that commit moving.
