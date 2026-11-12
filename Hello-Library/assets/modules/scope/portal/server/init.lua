-- The server half of a portal: it keeps one peer link to each target this process runs, marks a
-- portal whose target's link is up `scope/portal/hosted`, stands such a portal in its target too,
-- leading back, and hands a player who walks into one to the target's server, unless the player is
-- still cooling from its last crossing.
--
-- scope/portal/return = { entity = <the portal it stands for> }: on a return end
-- scope/portal/returns: a portal's return end, kept by the engine
--
-- The mod's return declares no sync: a portal a scene spawns on each side (a glTF door) is never
-- replicated. A portal a player opens gets its sync where it is spawned (`git/panel`).

-- One peer link to each target a placed portal names that runs as a server in this process: its
-- row, mirrored from the sibling world's VM, is ready with a peer port. Links are children of a
-- portal naming their target, so the last portal to a target takes its link along, and the
-- next run gives the target's link to another portal still naming it. A link outlives a reload of
-- this file: one spawned again leaves `hosted` off until it is welcomed, and every return end there
-- and back would go and come back with it, the target's link back here too.
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
                ["core/script/owner"] = false,
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

-- `scope/portal` was taken off an entity that stays: its links and its return end go. A despawned
-- portal takes them.
app:add_systems(Update, {
    Query[{
        removed = { "scope/portal" },
        optional = { "Children", "scope/portal/returns" },
    }],
    Query[{ with = { "core/net/peer/link" } }],
    Commands,
}, function(removed, links, commands)
    for _, e in ipairs(removed:iter()) do
        for _, l in ipairs(links:iter_many(e:get("Children") or {})) do
            commands:entity(l:id()):despawn()
        end
        for _, r in ipairs(e:get("scope/portal/returns") or {}) do
            commands:entity(r):try_despawn()
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

-- A hosted portal a player dropped (one this world replicates; a scene's door is each side's own)
-- stands in its target too: a return end at its place, leading here, which core's peer layer
-- mirrors there, and only there (`to`), as an ordinary portal back to this world: every other world
-- linked with this one would take it for a portal here too. Here it leads to this world itself,
-- which every half ignores. Its stable id names the two worlds and the place, as no entity may be
-- named in data: two portals at one place to one target share one return end, and a portal
-- retargeted or moved gets a new one. It outlives a reload of this file. A mirror is another
-- world's portal, and its return end is that world's to make.
app:add_systems(Update, {
    Query[{
        with = { "scope/portal", "Transform", "core/net/sync" },
        without = { "placement", "scope/portal/return", "core/net/peer/mirror", "WorldMirror" },
        optional = { "scope/portal/hosted", "scope/portal/returns", "scope/portal/view" },
    }],
    Query[{ with = { "scope/portal/return", "core/net/peer/share" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(portals, returns, rows, commands)
    local me = rows:iter()[1]
    local mine = me and me:get("core/world/status").scope_key
    local kept, wanting = {}, {}
    for _, p in ipairs(portals:iter()) do
        local target = p:get("scope/portal").target
        local sync = p:get("core/net/sync")
        local place = p:get("Transform")
        local id
        if mine ~= nil and target ~= mine and p:has("scope/portal/hosted") and type(sync) == "table" then
            local at = place.translation
            id = string.format("scope/portal/return:%s>%s@%.3f,%.3f,%.3f", mine, target, at.x, at.y, at.z)
        end
        local held = false
        for _, r in ipairs(returns:iter_many(p:get("scope/portal/returns") or {})) do
            local share = r:get("core/net/peer/share")
            if id ~= nil and not held and not kept[id] and share.stable_id == id then
                held, kept[id] = true, true
            else
                commands:entity(r:id()):despawn()
            end
        end
        if id ~= nil and not held then
            wanting[#wanting + 1] = {
                portal = p:id(), target = target, id = id, place = place, view = p:get("scope/portal/view"),
            }
        end
    end
    for _, w in ipairs(wanting) do
        if not kept[w.id] then
            kept[w.id] = true
            commands:spawn({
                ["scope/portal"] = { target = mine },
                ["scope/portal/return"] = { entity = w.portal },
                ["scope/portal/view"] = w.view,
                Transform = w.place,
                ["core/net/peer/share"] = { stable_id = w.id, to = { w.target } },
                ["core/net/sync"] = {
                    Transform = { authority = "server" },
                    ["scope/portal"] = { authority = "server" },
                    ["scope/portal/view"] = { authority = "server" },
                    ["scope/portal/hosted"] = { authority = "server" },
                },
                ["core/script/owner"] = false,
            })
            print(string.format("[SCOPE/PORTAL] %s: the portal stands in its target too, leading back", w.id))
        end
    end
end):in_set("scope/portal/server")
    :run_if({
        Query[{
            ["or"] = {
                added = { "scope/portal", "scope/portal/hosted", "core/world/status" },
                changed = { "scope/portal" },
                removed = { "scope/portal/hosted", "scope/portal/return", "placement" },
            },
        }],
    }, function(touched)
        return not touched:is_empty()
    end)

-- Walking into a portal whose target's link is up hands the player over: core's peer switch sends
-- its synced state to the target's server and demotes it here to a mirror. A demoted player has no
-- `core/net/owner`, so it matches nothing here again. The player takes a 3 s crossing timer with it,
-- in what crosses with it (`transfer_data`, which the target keeps only if it accepts `cooldown`), so
-- it does not bounce straight back through a portal where it arrives; a cooling player is skipped here.
app:add_systems(Update, {
    Query[{
        changed = { "collision_trigger" },
        with = { "scope/portal" },
        without = { "placement" },
    }],
    Query[{
        with = { "player", "core/net/owner", "core/net/peer/share" },
        without = { "core/net/peer/mirror", "WorldMirror", "scope/portal/cooling" },
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
                commands:entity(player:id()):entry("core/net/peer/share"):and_modify(function(share)
                    local carried = share.transfer_data or {}
                    local timers = carried.cooldown or {}
                    timers["scope/portal/cooling"] = { remaining = 3 }
                    carried.cooldown = timers
                    share.transfer_data = carried
                end)
                print(string.format("[SCOPE/PORTAL] client %s walks into %s: handing the player over",
                    tostring(player:get("core/net/owner").client_id), target))
            end
        end
    end
end):in_set("scope/portal/server")

return {
    relationships = {
        -- A return end goes with the portal it stands for.
        ["scope/portal/return"] = { target = "scope/portal/returns", linked_spawn = true },
    },
}
