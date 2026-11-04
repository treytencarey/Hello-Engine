-- The server decides which camera mod an entity carries.
return {
    base = "camera",
    ["core/net/sync"] = {
        authority = "server",
    },
}
