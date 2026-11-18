-- The server half of a portal: it keeps the peer links to each target this process runs, marks a
-- portal whose link is up `scope/portal/hosted`, stands such a portal in its target too, leading
-- back, and hands a player who walks into one to the target's server, unless the player is still
-- cooling from its last crossing.
--
-- scope/portal/return = { entity = <the portal it stands for> }: on a return end
-- scope/portal/returns: a portal's return end, kept by the engine
--
-- The mod's return declares no sync: a portal a scene spawns on each side (a glTF door) is never
-- replicated. A portal a player opens gets its sync where it is spawned (`git/panel`).

local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")

-- A door is a portal with `at` on a named node: it fits this world to the target at the place
-- `at` names there, and has its own link. Every other portal to a target shares the identity
-- link, which places nothing. A door without a target has a link to each world its players came
-- from through it (`to`).
local function door_link(p, portal, to)
    local target = to or portal.target
    if target ~= nil and portal.at ~= nil and p:has("Name") then
        return "peer_to_" .. target .. "@" .. p:get("Name").name
    end
end

-- A door without a target leads a player back where it came from through it.
local function way_back(p, portal, player)
    local from = portal.target == nil and portal.at ~= nil and p:has("Name") and player:get("scope/portal/from") or nil
    if from ~= nil and from.target ~= nil and from.door == p:get("Name").name then return from.target end
end

local function link_at(commands, p, name, target, row, at)
    local t = p.GlobalTransform:compute_transform()
    commands:spawn({
        ["core/net/peer/link"] = {
            name = name,
            port = row.ports.peer,
            scope_key = target,
            server_addr = "127.0.0.1",
            at = at,
            frame = {
                translation = { x = t.translation.x, y = t.translation.y, z = t.translation.z },
                rotation = { x = t.rotation.x, y = t.rotation.y, z = t.rotation.z, w = t.rotation.w },
                scale = { x = t.scale.x, y = t.scale.y, z = t.scale.z },
            },
        },
        ["core/net/sync"] = false,
        ["core/script/owner"] = false,
        ChildOf = p:id(),
    })
end

-- The links to each target a placed portal names that runs as a server in this process: its row,
-- mirrored from the sibling world's VM, is ready with a peer port. One identity link per target,
-- a child of a portal naming it, so the last portal to a target takes its link along, and the
-- next run gives the target's link to another portal still naming it. One link per door, its
-- child, carrying the door's `at` and its world transform (`frame`), which core places what
-- crosses by; a transform read before the door's first propagation is the identity, so the frame
-- follows the door's `GlobalTransform` changes. A door without a target has such a link to each
-- world a player here came from through it (`scope/portal/from`), while one does. A link outlives a
-- reload of this file: one spawned
-- again leaves `hosted` off until it is welcomed, and every return end there and back would go and
-- come back with it, the target's link back here too.
app:add_systems(Update, {
    Query[{
        with = { "scope/portal" },
        without = { "placement" },
        optional = { "Name", "GlobalTransform" },
    }],
    Query[{ with = { "core/world/status" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Query[{ with = { Mut["core/net/peer/link"], "ChildOf" } }],
    Query[{ with = { "player", "scope/portal/from" }, optional = { "core/net/owner", "core/net/peer/mirror" } }],
    Commands,
}, function(portals, rows, mine_rows, links, arrived, commands)
    local me = mine_rows:iter()[1]
    local mine = me and me:get("core/world/status").scope_key
    -- door Name -> the worlds its players came from
    local back = {}
    for _, a in ipairs(arrived:iter()) do
        local from = a:get("scope/portal/from")
        -- A player of this world's just handed back still names it: the link carries the hand-over,
        -- and the player's mirror here, until the world it went to says where it came from.
        local ours = a:has("core/net/owner") and not a:has("core/net/peer/mirror")
            or (a:has("core/net/peer/mirror") and a:get("core/net/peer/mirror").was_source == true)
        if ours and from.target ~= nil and from.target ~= mine and from.door ~= nil then
            back[from.door] = back[from.door] or {}
            back[from.door][from.target] = true
        end
    end
    local running, named = {}, {}
    for _, r in ipairs(rows:iter()) do
        local row = r:get("core/world/status")
        if row.mode == "server" and row.status == "ready" and row.ports and row.ports.peer then
            running[row.scope_key] = row
        end
    end
    for _, p in ipairs(portals:iter()) do
        local portal = p:get("scope/portal")
        if portal.target ~= nil and portal.target ~= mine and door_link(p, portal) == nil then named[portal.target] = true end
    end
    local linked = {}
    for _, l in ipairs(links:iter_mut()) do
        local parent = portals:get(l:get("ChildOf"))
        if parent ~= nil then
            local cfg = l:get("core/net/peer/link")
            local row = running[cfg.scope_key]
            local portal = parent:get("scope/portal")
            local door = door_link(parent, portal)
            local keep
            if cfg.at == nil then
                keep = row ~= nil and named[cfg.scope_key] and not linked[cfg.name]
                    and cfg.port == row.ports.peer
                    and cfg.name == "peer_to_127.0.0.1_" .. tostring(row.ports.world or row.port)
            elseif portal.target ~= nil then
                keep = row ~= nil and portal.target ~= mine and cfg.name == door and not linked[cfg.name]
                    and cfg.at == portal.at and cfg.scope_key == portal.target and cfg.port == row.ports.peer
            else
                local origins = parent:has("Name") and back[parent:get("Name").name] or {}
                keep = row ~= nil and origins[cfg.scope_key] and cfg.name == door_link(parent, portal, cfg.scope_key)
                    and not linked[cfg.name] and cfg.at == portal.at and cfg.port == row.ports.peer
            end
            if keep then
                linked[cfg.name] = true
                if cfg.at ~= nil and parent:has("GlobalTransform") then
                    local t = parent.GlobalTransform:compute_transform()
                    local frame = cfg.frame
                    if not (frame ~= nil and Vec3.abs_diff_eq(frame.translation, t.translation, 1e-4)
                            and Quat.abs_diff_eq(frame.rotation, t.rotation, 1e-4)
                            and Vec3.abs_diff_eq(frame.scale, t.scale, 1e-4)) then
                        l:get_mut("core/net/peer/link").frame = {
                            translation = { x = t.translation.x, y = t.translation.y, z = t.translation.z },
                            rotation = { x = t.rotation.x, y = t.rotation.y, z = t.rotation.z, w = t.rotation.w },
                            scale = { x = t.scale.x, y = t.scale.y, z = t.scale.z },
                        }
                    end
                end
            else
                commands:entity(l:id()):despawn()
            end
        end
    end
    for _, p in ipairs(portals:iter()) do
        local portal = p:get("scope/portal")
        local target = portal.target
        local row = target ~= nil and running[target] or nil
        local door = door_link(p, portal)
        local identity = row and "peer_to_127.0.0.1_" .. tostring(row.ports.world or row.port)
        if row ~= nil and door == nil and named[target] and not linked[identity] then
            linked[identity] = true
            commands:spawn({
                ["core/net/peer/link"] = {
                    name = identity,
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
        elseif row ~= nil and door ~= nil and target ~= mine and not linked[door] and p:has("GlobalTransform") then
            linked[door] = true
            link_at(commands, p, door, target, row, portal.at)
            print(string.format("[SCOPE/PORTAL] %s runs here: linking door %s to its place '%s'", target, door,
                portal.at))
        elseif target == nil and portal.at ~= nil and p:has("Name") and p:has("GlobalTransform") then
            for origin in pairs(back[p:get("Name").name] or {}) do
                local from_row = running[origin]
                local name = door_link(p, portal, origin)
                if from_row ~= nil and not linked[name] then
                    linked[name] = true
                    link_at(commands, p, name, origin, from_row, portal.at)
                    print(string.format("[SCOPE/PORTAL] %s runs here: linking door %s back to its place '%s'", origin,
                        name, portal.at))
                end
            end
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
        Query[{
            changed = { "GlobalTransform" },
            with = { "scope/portal" },
            without = { "placement" },
        }],
        -- a player's way back arriving, going, or leaving with the player
        Query[{
            ["or"] = {
                added = { "scope/portal/from", "core/net/peer/mirror" },
                changed = { "scope/portal/from" },
                removed = { "scope/portal/from", "core/net/owner" },
            },
        }],
    }, function(touched, moved, ways)
        return not (touched:is_empty() and moved:is_empty() and ways:is_empty())
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

-- Hosted means the server can hand a player over on the portal's own join: the identity link to
-- the target, or the door's, was welcomed by a world of that scope. A door's is welcomed only once
-- the target has found its place. A portal a scene spawned is marked too, but it is never synced,
-- so the client's copy of it never hears.
app:add_systems(Update, {
    Query[{
        with = { "scope/portal" },
        without = { "placement" },
        optional = { "scope/portal/hosted", "Name" },
    }],
    Query[{ with = { "core/net/peer/link", "core/net/peer/link/state" } }],
    Commands,
}, function(portals, links, commands)
    local up, doors_up = {}, {}
    for _, l in ipairs(links:iter()) do
        local st = l:get("core/net/peer/link/state")
        local cfg = l:get("core/net/peer/link")
        if st.connected and st.welcomed and not st.gave_up and st.scope_key ~= nil then
            if cfg.at == nil then up[st.scope_key] = true else doors_up[cfg.name] = true end
        end
    end
    for _, p in ipairs(portals:iter()) do
        local portal = p:get("scope/portal")
        local target = portal.target
        local door = door_link(p, portal)
        local hosted = (door == nil and up[target]) or (door ~= nil and doors_up[door]) or false
        if hosted and not p:has("scope/portal/hosted") then
            commands:entity(p:id()):insert({ ["scope/portal/hosted"] = {} })
            print(string.format("[SCOPE/PORTAL] portal to %s is hosted: its link is up", target))
        elseif not hosted and p:has("scope/portal/hosted") then
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
--
-- The return end is what the portal syncs: each component its `core/net/sync` names, copied, under
-- the same sync, with `scope/portal.target` turned back here, so whatever another mod syncs on a
-- dropped portal stands in the target too. `scope/portal/hosted` is this half's mark and is not
-- copied: here the return end is never hosted, and there the target's server marks it. The names
-- come from data, so the copy reads through `with_columns`. A portal that comes to sync a name its
-- return end lacks gets a new one, a run later: the target keeps a mirror's sync as it arrived, and
-- a despawn and spawn of one id sent in one frame would reach it spawn first.
app:add_systems(Update, {
    Query[{
        with = { "scope/portal", "Transform", "core/net/sync" },
        without = { "placement", "scope/portal/return", "core/net/peer/mirror", "WorldMirror" },
        optional = { "scope/portal/hosted", "scope/portal/returns" },
    }],
    Query[{ with = { "scope/portal/return", "core/net/peer/share", "core/net/sync" } }],
    Query[{ with = { "core/net/sync" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(portals, returns, synced, rows, commands)
    local me = rows:iter()[1]
    local mine = me and me:get("core/world/status").scope_key
    local kept, wanting, names, named = {}, {}, {}, {}
    for _, p in ipairs(portals:iter()) do
        local target = p:get("scope/portal").target
        local sync = p:get("core/net/sync")
        local id
        if mine ~= nil and target ~= nil and target ~= mine and p:has("scope/portal/hosted") and type(sync) == "table" then
            local at = p:get("Transform").translation
            id = string.format("scope/portal/return:%s>%s@%.3f,%.3f,%.3f", mine, target, at.x, at.y, at.z)
        end
        local held = false
        for _, r in ipairs(returns:iter_many(p:get("scope/portal/returns") or {})) do
            local ours = id ~= nil and r:get("core/net/peer/share").stable_id == id
            local carried = r:get("core/net/sync")
            local covers = type(carried) == "table"
            for name, entry in pairs(type(sync) == "table" and sync or {}) do
                if type(entry) == "table" and covers and carried[name] == nil then covers = false end
            end
            if ours and covers and not held and not kept[id] then
                held, kept[id] = true, true
            else
                commands:entity(r:id()):despawn()
                if ours and not covers then
                    held, kept[id] = true, true
                    print(string.format("[SCOPE/PORTAL] %s: the portal syncs more, its return end is made again", id))
                end
            end
        end
        if id ~= nil and not held then
            wanting[#wanting + 1] = { portal = p:id(), target = target, id = id }
            for name, entry in pairs(sync) do
                if type(entry) == "table" and not named[name] then
                    named[name] = true
                    names[#names + 1] = name
                end
            end
        end
    end
    local copied = synced:with_columns({ optional = names })
    for _, w in ipairs(wanting) do
        local row = copied:get(w.portal)
        if row ~= nil and not kept[w.id] then
            kept[w.id] = true
            local sync = row:get("core/net/sync")
            local spawn = {}
            for name, entry in pairs(sync) do
                if type(entry) == "table" and name ~= "scope/portal/hosted" then
                    spawn[name] = row:get(name)
                end
            end
            -- A new table: the one `get` answers is the portal's own value, and changing it would
            -- turn the portal itself back here. `at` names a node of the target's map, which means
            -- nothing on the way back.
            local portal = row:get("scope/portal")
            local back = {}
            for field, value in pairs(portal) do
                back[field] = value
            end
            back.target = mine
            back.at = nil
            spawn["scope/portal"] = back
            spawn["scope/portal/return"] = { entity = w.portal }
            spawn["core/net/peer/share"] = { stable_id = w.id, to = { w.target } }
            spawn["core/net/sync"] = sync
            spawn["core/script/owner"] = false
            commands:spawn(spawn)
            print(string.format("[SCOPE/PORTAL] %s: the portal stands in its target too, leading back", w.id))
        end
    end
end):in_set("scope/portal/server")
    :run_if({
        Query[{
            ["or"] = {
                added = { "scope/portal", "scope/portal/hosted", "core/world/status" },
                changed = { "scope/portal", "core/net/sync" },
                removed = { "scope/portal/hosted", "scope/portal/return", "placement" },
            },
        }],
    }, function(touched)
        return not touched:is_empty()
    end)

-- This server decides every crossing, on its own copy of the trigger: walking into any portal or
-- door hands the player over with core's peer switch, on the portal's join (the door's link, else
-- the identity link). The switch is synced to the player's owner, whose client follows it. Linked,
-- core sends the player's state to the target's server and demotes it here to a mirror, which has
-- no `core/net/owner` and matches nothing here again. Not linked, core releases the switch and the
-- player stays, until its client watches here and its spawner takes it away. The player takes a
-- 3 s crossing timer and where it came from (`scope/portal/from`, through a door) with it, in what
-- crosses with it (`transfer_data`, which the target keeps only
-- if it accepts `cooldown`), so it does not bounce straight back through a portal where it
-- arrives; a cooling player is skipped here.
app:add_systems(Update, {
    Query[{
        changed = { "collision_trigger" },
        with = { "scope/portal" },
        without = { "placement" },
        optional = { "Name" },
    }],
    Query[{
        with = { "player", "core/net/owner", "core/net/peer/share" },
        without = { "core/net/peer/mirror", "WorldMirror", "scope/portal/cooling" },
        optional = { "scope/portal/from" },
    }],
    Query[{ with = { "core/net/peer/link" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(portals, players, links, rows, commands)
    local me = rows:iter()[1]
    local mine = me and me:get("core/world/status").scope_key
    local identity = {}
    for _, l in ipairs(links:iter()) do
        local cfg = l:get("core/net/peer/link")
        if cfg.at == nil then identity[cfg.scope_key] = cfg.name end
    end
    for _, p in ipairs(portals:iter()) do
        local portal = p:get("scope/portal")
        local target = portal.target
        local entered = p:get("collision_trigger").entered or {}
        local door = portal.at ~= nil and p:has("Name")
        for _, player in ipairs(players:iter_many(entered)) do
            local to = target or way_back(p, portal, player)
            local link = door_link(p, portal, to) or (to ~= nil and identity[to] or nil)
            if to ~= nil and to ~= mine then
                -- Written on every crossing, an empty one through a portal that is not a door: the share
                -- keeps its `transfer_data`, and a world the player comes back to keeps what it had.
                local from = door and mine ~= nil and { target = mine, door = portal.at } or {}
                commands:entity(player:id()):insert({
                    ["core/net/peer/switch"] = { target_scope = to, link = link },
                })
                commands:entity(player:id()):entry("core/net/peer/share"):and_modify(function(share)
                    local carried = share.transfer_data or {}
                    local timers = carried.cooldown or {}
                    timers["scope/portal/cooling"] = { remaining = 3 }
                    carried.cooldown = timers
                    carried["scope/portal/from"] = from
                    share.transfer_data = carried
                end)
                print(string.format("[SCOPE/PORTAL] client %s walks into %s: handing the player over on %s",
                    tostring(player:get("player").client_id), to, tostring(link)))
            end
        end
    end
end):in_set("scope/portal/server")

-- A player spawned from a hand-over (`player/spawner`, from its connection's `synced_state`) gets
-- where it came from. One a returning player's mirror took back has it set by core.
app:add_systems(Update, {
    Query[{ added = { "player" }, with = { "core/net/owner" }, without = { "core/net/peer/mirror" } }],
    Query[{ with = { "core/net/connection" } }],
    Commands,
}, function(arrived, connections, commands)
    for _, p in ipairs(arrived:iter()) do
        local c = connections:get(p:get("core/net/owner"))
        local state = c and c:get("core/net/connection").synced_state
        local from = state and state["scope/portal/from"]
        if type(from) == "table" and from.target ~= nil then
            commands:entity(p:id()):insert({ ["scope/portal/from"] = { target = from.target, door = from.door } })
        end
    end
end):in_set("scope/portal/from"):before("scope/portal/server")

-- `scope/portal/from` reaches the player's owner, whose client predicts the way back; an empty one
-- (the player came another way) goes.
app:add_systems(Update, {
    Query[{
        ["or"] = { added = { "scope/portal/from" }, changed = { "scope/portal/from" } },
        with = { "player", "core/net/owner" },
        optional = { "core/net/sync" },
    }],
    Commands,
}, function(players, commands)
    for _, p in ipairs(players:iter()) do
        local empty = p:get("scope/portal/from").target == nil
        local entity = commands:entity(p:id())
        if empty then entity:remove("scope/portal/from") end
        if type(p:get("core/net/sync")) == "table" then
            entity:entry("core/net/sync"):and_modify(function(sync)
                sync["scope/portal/from"] = (not empty) and { authority = "server", target = "owner" } or nil
            end)
        end
    end
end):in_set("scope/portal/from"):before("scope/portal/server")

return {
    relationships = {
        -- A return end goes with the portal it stands for.
        ["scope/portal/return"] = { target = "scope/portal/returns", linked_spawn = true },
    },
}
