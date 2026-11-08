---
depends_on: [vault/git]
conflicts_with: []
exposes: [checkout/github, checkout/answer]
---

# checkout/github

The GitHub checkout provider: a branch of a GitHub repository brought onto disk, for the Gateway world to host. Root clones it, chooses its folder and holds the deploy key; this world runs no git and holds no key. It runs in the Gateway world, on a local entity, and never crosses the network.

Every checkout provider answers the same way, so the Gateway reads `checkout/answer` whichever provider served it. A provider is the mod named by its request, `checkout/<provider>`, which the request loads.

## Components

- `checkout/github = { repo, ref, path }`: the request, spawned by the Gateway. `repo` is `owner/name`, `ref` a branch. `path` is part of the contract every provider takes, and this provider ignores it: root chooses the folder, `.hello/worktrees/<owner>/<name>/<ref, / as __>`, and refuses a checkout that names one.
- `checkout/answer = { status, path, reason, detail }`: the answer, on the request's entity, added and removed by the provider.
  - `status`: `"ready"` or `"failed"`;
  - `path`: the checkout as an asset root, with `ready`: root's folder, never the asked `path`;
  - `reason`: why, with `failed`: `"needs-deploy-key"` (the repository is private and root's key is not registered on it), `"ref-not-found"`, `"checkout-failed"`, or why root refused;
  - `detail`: with `needs-deploy-key`, the deploy key's public half, which the Gateway hands on to be registered (`vault/github/keys`). Never a private key.
- The provider's ask is a child of the request, so it goes with it: `{ ["vault/git/checkout"] = {}, ["vault/git"] = { repo, ref }, Request = {} }`. Root answers it on `vault/git/checkout/reply`; the provider then closes it.

## Systems

| Schedule | Set | Purpose |
|----------|-----|---------|
| Update | `checkout/github` | On an added `checkout/github` with no answer: asks root for the checkout |
| Update | `checkout/github` | On root's reply under a `checkout/github`: writes `checkout/answer`, and closes the ask. Runs on the reply's edge, and twice a second while a reply waits |
| Update | `checkout/github` | On a removed `checkout/github`: closes its ask, which stops root's job, and removes its answer |

## Use

```lua
-- in the Gateway world: ask, and read the answer on the same entity
commands:spawn({ ["checkout/github"] = { repo = "owner/name", ref = "main" } })

app:add_systems(Update, {
    Query[{ added = { "checkout/answer" }, with = { "checkout/github" } }],
}, function(answers)
    for _, e in ipairs(answers:iter()) do
        local answer = e:get("checkout/answer")
        -- answer.status, answer.path, answer.reason, answer.detail
    end
end)
```

## Notes

- Removing `checkout/github`, or despawning its entity, cancels: the ask closes and root stops its git process.
- One request is answered once. To ask again, after a key is registered, despawn the request and spawn a new one.
- Only the Gateway world root started may ask for a checkout; from anywhere else root answers nothing, or refuses.
- A reply crosses from root's VM, and an edge that crosses VMs can be missed, so a reply still waiting is looked at again twice a second.
- A hot reload asks again for a request still waiting, and nothing for one answered.
- The suite stands in for root, answering each ask on its request entity.
