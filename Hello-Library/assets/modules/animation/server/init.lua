-- The server half: the server states a character's model, and every client draws it.

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
