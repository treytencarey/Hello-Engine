-- The server half's stateless functions: what reading a folder will answer, and all that a listing
-- does without touching the disk. An entry is `{ name, is_dir, size }`.

local Listing = {}

-- Waits for the engine's redesign of file access through requests.
function Listing.read(root, path)
    return nil, "not available"
end

-- A name never listed and never opened, compared the way Windows opens it: `CONFIG` and `config.`
-- are `config`, and `..` followed by dots or spaces is still `..`. So is no name at all.
function Listing.is_private(name)
    local plain = name:lower():gsub("[%. ]+$", "")
    if plain == "" then return true end
    if plain:sub(1, 1) == "." then return true end
    if plain == "config" then return true end
    if plain == "deploy_keys" then return true end
    if plain == "gateways" then return true end
    -- An NTFS short name opens the long name's folder: `DEPLOY~1` is `deploy_keys`.
    if plain:find("~%d") then return true end
    return false
end

function Listing.visible(entries)
    local kept = {}
    for _, entry in ipairs(entries) do
        if not Listing.is_private(entry.name) then
            kept[#kept + 1] = entry
        end
    end
    return kept
end

-- Folders first, then by name ignoring case. Sorts the list it is given.
function Listing.sorted(entries)
    table.sort(entries, function(a, b)
        if a.is_dir ~= b.is_dir then return a.is_dir end
        local first, second = a.name:lower(), b.name:lower()
        if first ~= second then return first < second end
        return a.name < b.name
    end)
    return entries
end

-- One page of `entries`, as an answer gives it.
function Listing.page(entries, path, offset, limit)
    local files = {}
    for i = offset + 1, math.min(offset + limit, #entries) do
        local entry = entries[i]
        files[#files + 1] = {
            name = entry.name,
            path = path == "" and entry.name or path .. "/" .. entry.name,
            is_directory = entry.is_dir,
            size = entry.size or 0,
        }
    end
    return {
        op = "list",
        path = path,
        offset = offset,
        files = files,
        has_more = offset + limit < #entries,
        total_count = #entries,
    }
end

return Listing
