-- The client owns its camera: the owner's client writes it, and only that client receives it.
return {
    ["core/net/sync"] = {
        authority = "client",
        target = "owner",
    },
}
