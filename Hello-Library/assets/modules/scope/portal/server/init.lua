-- The server half of a portal: it approves a portal a client places, keeps one peer link to each
-- target this process runs, marks a portal whose target's link is up `scope/portal/hosted`, and
-- hands a player who walks into such a portal to the target's server.
--
-- The mod's return declares no sync: a portal a scene spawns on each side (a glTF door) is never
-- replicated. A placed portal gets its sync from the approval.

local Canonical = require("modules/core/world/canonical.lua")

-- A client asks for a portal by predicting it. Only the target is taken from the ask, after its
-- checks; the cap counts what the owner holds here, and what this run approved.
app:add_systems(Update, {
    Query[{ added = { "core/net/predict" } }],
    Query[{ with = { "scope/portal", "core/net/owner" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(asks, owned, rows, commands)
    local me = rows:iter()[1]
    local mine = me and me:get("core/world/status").scope_key
    local held = {}
    for _, p in ipairs(owned:iter()) do
        local client_id = p:get("core/net/owner").client_id
        held[client_id] = (held[client_id] or 0) + 1
    end
    for _, ask in ipairs(asks:iter()) do
        local predict = ask:get("core/net/predict")
        local requested = predict.requested or {}
        local portal = requested["scope/portal"]
        if portal ~= nil then
            local target = portal.target
            local parts = type(target) == "string" and Canonical.parse(target) or nil
            local refused
            if not (parts and parts.provider == "github" and not parts.reserved
                and Canonical.canonical(parts) == target) then
                refused = "not a canonical github scope key"
            elseif target == mine then
                refused = "this world's own scope"
            elseif (held[predict.client_id] or 0) >= 8 then
                refused = "8 portals already"
            end
            if refused then
                commands:entity(ask:id()):despawn()
                print(string.format("[SCOPE/PORTAL] client %s's portal to %s refused: %s",
                    tostring(predict.client_id), tostring(target), refused))
            else
                held[predict.client_id] = (held[predict.client_id] or 0) + 1
                local view = requested["scope/portal/view"]
                local mode = view and (view.mode == "none" or view.mode == "3d") and view.mode or "3d"
                local placing = requested.placement ~= nil
                local t = requested.Transform
                local at = type(t) == "table" and type(t.translation) == "table" and t.translation or {}
                local entity = commands:entity(ask:id())
                entity:insert({
                    ["scope/portal"] = { target = target },
                    ["scope/portal/view"] = { mode = mode },
                    placement = placing and {} or nil,
                    Transform = {
                        translation = {
                            x = tonumber(at.x) or 0,
                            y = tonumber(at.y) or 0,
                            z = tonumber(at.z) or 0,
                        },
                    },
                    ["core/net/sync"] = {
                        placement = placing and { authority = "client" } or nil,
                        Transform = placing and { authority = "client", reliable = false } or { authority = "server" },
                        ["scope/portal"] = { authority = "server" },
                        ["scope/portal/view"] = { authority = "server" },
                        ["scope/portal/hosted"] = { authority = "server" },
                    },
                    ["core/script/owner"] = false,
                })
                entity:remove("core/net/predict")
                print(string.format("[SCOPE/PORTAL] client %s placed a portal to %s",
                    tostring(predict.client_id), target))
            end
        end
    end
end):in_set("scope/portal/server")

-- One peer link to each target a placed portal names that runs as a server in this process: its
-- row, mirrored from the sibling world's VM, is ready with a peer port. Links are children of a
-- portal naming their target, so the last portal to a target takes its link along, and the
-- next run gives the target's link to another portal still naming it.
app:add_systems(Update, {
    Query[{
        with = { "scope/portal" },
        without = { "placement" },
    }],
    Query[{ with = { "core/world/status" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Query[{ with = { "core/net/peer/link", "ChildOf" } }],
    Commands,
}, function(portals, rows, mine_rows, links, commands)
    local me = mine_rows:iter()[1]
    local mine = me and me:get("core/world/status").scope_key
    local running, named = {}, {}
    for _, r in ipairs(rows:iter()) do
        local row = r:get("core/world/status")
        if row.mode == "server" and row.status == "ready" and row.ports and row.ports.peer then
            running[row.scope_key] = row
        end
    end
    for _, p in ipairs(portals:iter()) do
        local target = p:get("scope/portal").target
        if target ~= mine then named[target] = true end
    end
    local linked = {}
    for _, l in ipairs(links:iter()) do
        if portals:contains(l:get("ChildOf")) then
            local cfg = l:get("core/net/peer/link")
            local row = running[cfg.scope_key]
            local keep = row ~= nil and named[cfg.scope_key] and not linked[cfg.scope_key]
                and cfg.port == row.ports.peer
                and cfg.name == "peer_to_127.0.0.1_" .. tostring(row.ports.world or row.port)
            if keep then
                linked[cfg.scope_key] = true
            else
                commands:entity(l:id()):despawn()
            end
        end
    end
    for _, p in ipairs(portals:iter()) do
        local target = p:get("scope/portal").target
        local row = running[target]
        if row ~= nil and named[target] and not linked[target] then
            linked[target] = true
            commands:spawn({
                ["core/net/peer/link"] = {
                    name = "peer_to_127.0.0.1_" .. tostring(row.ports.world or row.port),
                    port = row.ports.peer,
                    scope_key = target,
                    server_addr = "127.0.0.1",
                },
                ["core/net/sync"] = false,
                ChildOf = p:id(),
            })
            print(string.format("[SCOPE/PORTAL] %s runs here: linking to its peer port %s", target,
                tostring(row.ports.peer)))
        end
    end
end):in_set("scope/portal/server")
    :run_if({
        Query[{
            ["or"] = {
                added = { "scope/portal", "core/world/status" },
                changed = { "scope/portal", "core/world/status" },
                removed = { "scope/portal", "placement", "core/world/status", "core/net/peer/link" },
            },
        }],
    }, function(touched)
        return not touched:is_empty()
    end)

-- `scope/portal` was taken off an entity that stays: its links go. A despawned portal takes them.
app:add_systems(Update, {
    Query[{
        removed = { "scope/portal" },
        optional = { "Children" },
    }],
    Query[{ with = { "core/net/peer/link" } }],
    Commands,
}, function(removed, links, commands)
    for _, e in ipairs(removed:iter()) do
        for _, l in ipairs(links:iter_many(e:get("Children") or {})) do
            commands:entity(l:id()):despawn()
        end
    end
end):in_set("scope/portal/server")

-- Hosted means the server can hand a player over: the link to the target was welcomed by a world
-- of that scope. A portal a scene spawned is marked too, but it is never synced, so the client's
-- copy of it never hears.
app:add_systems(Update, {
    Query[{
        with = { "scope/portal" },
        without = { "placement" },
        optional = { "scope/portal/hosted" },
    }],
    Query[{ with = { "core/net/peer/link", "core/net/peer/link/state" } }],
    Commands,
}, function(portals, links, commands)
    local up = {}
    for _, l in ipairs(links:iter()) do
        local st = l:get("core/net/peer/link/state")
        if st.connected and st.welcomed and not st.gave_up and st.scope_key ~= nil then
            up[st.scope_key] = true
        end
    end
    for _, p in ipairs(portals:iter()) do
        local target = p:get("scope/portal").target
        if up[target] and not p:has("scope/portal/hosted") then
            commands:entity(p:id()):insert({ ["scope/portal/hosted"] = {} })
            print(string.format("[SCOPE/PORTAL] portal to %s is hosted: its link is up", target))
        elseif not up[target] and p:has("scope/portal/hosted") then
            commands:entity(p:id()):remove("scope/portal/hosted")
        end
    end
end):in_set("scope/portal/server")
    :run_if({
        Query[{
            ["or"] = {
                added = { "scope/portal", "core/net/peer/link/state" },
                changed = { "scope/portal", "core/net/peer/link/state" },
                removed = { "placement", "core/net/peer/link", "core/net/peer/link/state" },
            },
        }],
    }, function(touched)
        return not touched:is_empty()
    end)

-- Walking into a portal whose target's link is up hands the player over: core's peer switch sends
-- its synced state to the target's server and demotes it here to a mirror. A demoted player has no
-- `core/net/owner`, so it matches nothing here again.
app:add_systems(Update, {
    Query[{
        changed = { "collision_trigger" },
        with = { "scope/portal" },
        without = { "placement" },
    }],
    Query[{
        with = { "player", "core/net/owner", "core/net/peer/share" },
        without = { "core/net/peer/mirror", "WorldMirror" },
    }],
    Query[{ with = { "core/net/peer/link", "core/net/peer/link/state" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(portals, players, links, rows, commands)
    local me = rows:iter()[1]
    local mine = me and me:get("core/world/status").scope_key
    local up = {}
    for _, l in ipairs(links:iter()) do
        local st = l:get("core/net/peer/link/state")
        if st.connected and st.welcomed and not st.gave_up and st.scope_key ~= nil then
            up[st.scope_key] = true
        end
    end
    for _, p in ipairs(portals:iter()) do
        local target = p:get("scope/portal").target
        local entered = p:get("collision_trigger").entered or {}
        if up[target] and target ~= mine then
            for _, player in ipairs(players:iter_many(entered)) do
                commands:entity(player:id()):insert({ ["core/net/peer/switch"] = { target_scope = target } })
                print(string.format("[SCOPE/PORTAL] client %s walks into %s: handing the player over",
                    tostring(player:get("core/net/owner").client_id), target))
            end
        end
    end
end):in_set("scope/portal/server")

return {}
