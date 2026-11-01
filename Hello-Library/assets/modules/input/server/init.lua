-- `input` syncs from the server, so an `input` the server adds reaches the client. Bindings
-- are client data: each mod writes its own in its client half, and they never sync.
return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
