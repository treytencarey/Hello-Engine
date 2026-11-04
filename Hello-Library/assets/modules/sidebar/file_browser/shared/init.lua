-- What both halves read of `sidebar/file_browser`: the server's value crosses whole, so its defaults
-- are declared here. The mod is described in its other halves.
--
-- sidebar/file_browser = {
--     width = <panel pixels>,
--     page_size = <entries a client asks for at once>,
--     max_limit = <entries the server answers at once, whatever is asked>,
--     max_requests = <asks one request may hold; a request holding more is refused whole>,
--     max_path = <longest path the server takes, in bytes>,
-- }

return {
    defaults = {
        ["sidebar/file_browser"] = {
            width = 280,
            page_size = 50,
            max_limit = 200,
            max_requests = 16,
            max_path = 1024,
        },
    },
}
