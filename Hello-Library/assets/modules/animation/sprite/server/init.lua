-- The server half: the server states a character's sheet, and every client draws it.

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
