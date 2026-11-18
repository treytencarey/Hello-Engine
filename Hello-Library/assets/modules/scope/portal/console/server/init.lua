-- The server half of a console: the world's server decides a re-point. It takes a player's request
-- only for a door this scene has, a console naming that door, and a target in this world's own
-- repository; then it sets its own copy of the door, keeps one record per re-pointed door, which
-- reaches every client, and answers the player. A door pointed back at its authored target is no
-- longer re-pointed: its record goes, and it keeps its authored `at`. A pick, of any branch, also
-- closes the door, on its rig (the nearest node at or above the door carrying `animation/clip`),
-- from where it stands, and once it is shut opens it again; `animation/clip` publishes the rig to
-- every client.

local Door = require("modules/scope/portal/console/shared/door.lua")

--- The node carrying the door's clip: the door's own, or its nearest ancestor's. Its query's
--- `animation/clip` column is `Mut`.
local function rig_of(rigs, door)
    return rigs:iter_many_mut({ door })[1] or rigs:iter_many_mut(rigs:iter_ancestors(door))[1]
end

-- `scope/portal/console/user` is on the player, which everyone sees: the request and its answer
-- reach the owner alone.
app:add_systems(First, {
    Query[{
        added = { "scope/portal/console/user" },
        with = { "core/net/sync" },
    }],
    Commands,
}, function(users, commands)
    for _, e in ipairs(users:iter()) do
        if type(e:get("core/net/sync")) == "table" then
            commands:entity(e:id()):entry("core/net/sync"):and_modify(function(sync)
                sync["scope/portal/console/request"] = { authority = "client", target = "owner" }
                sync["scope/portal/console/response"] = { authority = "server", target = "owner" }
            end)
        end
    end
end):in_set("scope/portal/console/server")

-- `scope/portal/console/user` taken off an entity that stays: the sync this half added goes. A
-- despawned player has no row in `synced`.
app:add_systems(First, {
    Query[{ removed = { "scope/portal/console/user" } }],
    Query[{ with = { "core/net/sync" } }],
    Commands,
}, function(removed, synced, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(synced:iter_many(gone)) do
        if type(e:get("core/net/sync")) == "table" then
            commands:entity(e:id()):entry("core/net/sync"):and_modify(function(sync)
                sync["scope/portal/console/request"] = nil
                sync["scope/portal/console/response"] = nil
            end)
        end
    end
end):in_set("scope/portal/console/server")

-- The request is the owner's word: only a door's name and a target are taken from it, each checked
-- against what this side holds. A record outlives this mod's reload and the console's scene being
-- written again, so a re-point lasts while the server runs.
app:add_systems(Update, {
    Query[{
        changed = { "scope/portal/console/request" },
        with = { "scope/portal/console/user" },
        without = { "WorldMirror", "core/net/peer/mirror" },
    }],
    Query[{
        with = { Mut["scope/portal"], "Name" },
        without = { "placement" },
        optional = { "GltfExtras" },
    }],
    Query[{ with = { "scope/portal/console" } }],
    Query[{ with = { Mut["scope/portal/console/target"] } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Query[{ with = { Mut["animation/clip"] } }],
    Commands,
}, function(asking, doors, consoles, records, rows, rigs, commands)
    local me = rows:iter()[1]
    local root = me and me:get("core/world/status").scope_root
    for _, e in ipairs(asking:iter()) do
        local ask = e:get("scope/portal/console/request")
        local name = type(ask) == "table" and ask.door or nil
        local target = type(ask) == "table" and ask.target or nil
        local door, console, record = nil, nil, nil
        for _, d in ipairs(doors:iter_mut()) do
            if d:get("Name").name == name then door = d end
        end
        for _, c in ipairs(consoles:iter()) do
            if c:get("scope/portal/console").door == name then console = c end
        end
        for _, r in ipairs(records:iter_mut()) do
            if r:get("scope/portal/console/target").door == name then record = r end
        end
        local ours = type(target) == "string" and root ~= nil and #target <= 512
            and #target > #root + 1 and target:sub(1, #root + 1) == root .. ":"
        local reason = ((type(name) ~= "string" or door == nil or console == nil) and "no-such-door")
            or (not ours and "not-this-repository")
            or nil
        if reason ~= nil then
            commands:entity(e:id()):insert({
                ["scope/portal/console/response"] = { status = "refused", reason = reason },
            })
            print(string.format("[SCOPE/PORTAL/CONSOLE] re-point of %s refused: %s", tostring(name), reason))
        else
            local authored = Door.authored(door)
            local portal = door:get_mut("scope/portal")
            if authored ~= nil and authored.target == target then
                portal.target, portal.at = authored.target, authored.at
                if record ~= nil then
                    commands:entity(record:id()):despawn()
                end
            else
                local at = console:get("scope/portal/console").at
                portal.target, portal.at = target, at
                if record ~= nil then
                    local kept = record:get_mut("scope/portal/console/target")
                    kept.target, kept.at = target, at
                else
                    commands:spawn({
                        ["scope/portal/console/target"] = { door = name, target = target, at = at },
                        ["core/net/sync"] = { ["scope/portal/console/target"] = { authority = "server" } },
                        ["core/script/owner"] = false,
                    })
                end
            end
            local rig = rig_of(rigs, door:id())
            if rig then rig:get_mut("animation/clip").speed = -1 end
            commands:entity(e:id()):insert({ ["scope/portal/console/response"] = { status = "done" } })
            print(string.format("[SCOPE/PORTAL/CONSOLE] %s now leads to %s", name, target))
        end
    end
end):in_set("scope/portal/console/server")

-- A door closed for a pick, shut: it opens again. Where the rig stands is what `animation/clip`
-- published of it (`animation/clip/node`, by the rig's `Name`).
app:add_systems(Update, {
    Query[{
        ["or"] = { added = { "animation/clip/node" }, changed = { "animation/clip/node" } },
    }],
    Query[{ with = { "scope/portal/console" } }],
    Query[{ with = { "scope/portal", "Name" }, without = { "placement" } }],
    Query[{ with = { Mut["animation/clip"] }, optional = { "Name" } }],
}, function(published, consoles, doors, rigs)
    local shut = {}
    for _, r in ipairs(published:iter()) do
        local node = r:get("animation/clip/node")
        if node.speed < 0 and type(node.time) == "number" and node.time <= 0 then shut[node.name] = true end
    end
    if next(shut) == nil then return end
    local named = {}
    for _, c in ipairs(consoles:iter()) do named[c:get("scope/portal/console").door] = true end
    for _, d in ipairs(doors:iter()) do
        if named[d:get("Name").name] then
            local rig = rig_of(rigs, d:id())
            if rig and rig:has("Name") and shut[rig:get("Name").name] then rig:get_mut("animation/clip").speed = 1 end
        end
    end
end):in_set("scope/portal/console/server")

-- A door's scene written again spawns it with its authored target: a record for it sets it again.
app:add_systems(Update, {
    Query[{
        added = { "scope/portal" },
        with = { "Name" },
        without = { "placement" },
    }],
    Query[{ with = { Mut["scope/portal"], "Name" } }],
    Query[{ with = { "scope/portal/console/target" } }],
}, function(added, doors, records)
    local ids = {}
    for _, e in ipairs(added:iter()) do
        ids[#ids + 1] = e:id()
    end
    for _, d in ipairs(doors:iter_many_mut(ids)) do
        local name = d:get("Name").name
        for _, r in ipairs(records:iter()) do
            local record = r:get("scope/portal/console/target")
            local portal = d:get("scope/portal")
            if record.door == name and (portal.target ~= record.target or portal.at ~= record.at) then
                local p = d:get_mut("scope/portal")
                p.target, p.at = record.target, record.at
            end
        end
    end
end):in_set("scope/portal/console/server")
