-- The server decides which camera mod an entity carries.
return {
    base = "camera/3d",
    ["core/net/sync"] = {
        authority = "server",
    },
}
