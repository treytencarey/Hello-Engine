-- Bindings are written on the server and sent to every client. Each mod declares the
-- sync of its own output, `input/<group>`, as client authority.
return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
