-- The server half of a portal: it keeps a peer link to each world a portal names, which core finds
-- wherever that world runs, marks a portal `scope/portal/hosted` once that world is linked with this
-- one, stands such a portal in its target too, leading back, and hands a player who walks into one
-- to the target's server, unless the player is still cooling from its last crossing.
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

-- A mirrored portal is another world's return end, which stands here once this world holds its
-- placer's connection (`core/net/peer/mirror.owner.connection`): until then it links, hosts and
-- hands over nothing. Once hosted it stays when the placer leaves, as this world's own portals stay
-- when their owner does.
local function waiting(p)
    local m = p:has("core/net/peer/mirror") and p:get("core/net/peer/mirror") or nil
    return m ~= nil and (type(m.owner) ~= "table" or m.owner.connection == nil) and not p:has("scope/portal/hosted")
end

local function link_at(commands, p, name, target, at)
    local t = p.GlobalTransform:compute_transform()
    commands:spawn({
        ["core/net/peer/link"] = {
            name = name,
            scope_key = target,
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

-- The links to each target a placed portal names, wherever it runs: each names only the world, and
-- core finds where it takes peers through that world's Gateway. One identity link per target,
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
        optional = { "Name", "GlobalTransform", "core/net/peer/mirror", "scope/portal/hosted" },
    }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Query[{ with = { Mut["core/net/peer/link"], "ChildOf" } }],
    Query[{ with = { "player", "scope/portal/from" }, optional = { "core/net/owner", "core/net/peer/mirror" } }],
    Commands,
}, function(portals, mine_rows, links, arrived, commands)
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
    local named = {}
    for _, p in ipairs(portals:iter()) do
        local portal = p:get("scope/portal")
        if portal.target ~= nil and portal.target ~= mine and door_link(p, portal) == nil and not waiting(p) then
            named[portal.target] = true
        end
    end
    local linked = {}
    for _, l in ipairs(links:iter_mut()) do
        local parent = portals:get(l:get("ChildOf"))
        if parent ~= nil then
            local cfg = l:get("core/net/peer/link")
            local portal = parent:get("scope/portal")
            local door = door_link(parent, portal)
            -- A link that names an address is an older one's, made before links found their world.
            local keep = cfg.port == nil and cfg.server_addr == nil and not waiting(parent)
            if cfg.at == nil then
                keep = keep and named[cfg.scope_key] and not linked[cfg.name] and cfg.name == "peer_to_" .. cfg.scope_key
            elseif portal.target ~= nil then
                keep = keep and portal.target ~= mine and cfg.name == door and not linked[cfg.name]
                    and cfg.at == portal.at and cfg.scope_key == portal.target
            else
                local origins = parent:has("Name") and back[parent:get("Name").name] or {}
                keep = keep and origins[cfg.scope_key] and cfg.name == door_link(parent, portal, cfg.scope_key)
                    and not linked[cfg.name] and cfg.at == portal.at
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
        local door = door_link(p, portal)
        local identity = target ~= nil and "peer_to_" .. target or nil
        if waiting(p) then
            -- Nothing yet: it links once its placer's connection is here.
        elseif identity ~= nil and door == nil and named[target] and not linked[identity] then
            linked[identity] = true
            commands:spawn({
                ["core/net/peer/link"] = { name = identity, scope_key = target },
                ["core/net/sync"] = false,
                ["core/script/owner"] = false,
                ChildOf = p:id(),
            })
            print(string.format("[SCOPE/PORTAL] linking to %s", target))
        elseif target ~= nil and door ~= nil and target ~= mine and not linked[door] and p:has("GlobalTransform") then
            linked[door] = true
            link_at(commands, p, door, target, portal.at)
            print(string.format("[SCOPE/PORTAL] linking door %s to its place '%s' in %s", door, portal.at, target))
        elseif target == nil and portal.at ~= nil and p:has("Name") and p:has("GlobalTransform") then
            for origin in pairs(back[p:get("Name").name] or {}) do
                local name = door_link(p, portal, origin)
                if not linked[name] then
                    linked[name] = true
                    link_at(commands, p, name, origin, portal.at)
                    print(string.format("[SCOPE/PORTAL] linking door %s back to its place '%s' in %s", name, portal.at,
                        origin))
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
        -- a return end's placer arriving or leaving here
        Query[{ changed = { "core/net/peer/mirror" }, with = { "scope/portal" } }],
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
    }, function(touched, placers, moved, ways)
        return not (touched:is_empty() and placers:is_empty() and moved:is_empty() and ways:is_empty())
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
-- the target, or the door's, was welcomed by a world of that scope, or, for the identity join, a
-- world of that scope dialled this one and proved itself (core hands a player over on any identity
-- connection of the target's scope). A door's is welcomed only once the target has found its
-- place. A portal a scene spawned is marked too, but it is never synced, so the client's copy of it
-- never hears. A return end still waiting for its placer here is never hosted.
app:add_systems(Update, {
    Query[{
        with = { "scope/portal" },
        without = { "placement" },
        optional = { "scope/portal/hosted", "Name", "core/net/peer/mirror" },
    }],
    Query[{ with = { "core/net/peer/link", "core/net/peer/link/state" } }],
    Query[{ with = { "core/net/peer/state" } }],
    Commands,
}, function(portals, links, listeners, commands)
    local up, doors_up = {}, {}
    for _, l in ipairs(links:iter()) do
        local st = l:get("core/net/peer/link/state")
        local cfg = l:get("core/net/peer/link")
        if st.connected and st.welcomed and not st.gave_up and st.scope_key ~= nil then
            if cfg.at == nil then up[st.scope_key] = true else doors_up[cfg.name] = true end
        end
    end
    for _, e in ipairs(listeners:iter()) do
        for _, peer in pairs(e:get("core/net/peer/state").inbound or {}) do
            if peer.ready and peer.scope_key ~= nil and peer.at == nil and not peer.find then up[peer.scope_key] = true end
        end
    end
    for _, p in ipairs(portals:iter()) do
        local portal = p:get("scope/portal")
        local target = portal.target
        local door = door_link(p, portal)
        local hosted = not waiting(p) and ((door == nil and up[target]) or (door ~= nil and doors_up[door])) or false
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
                added = { "scope/portal", "core/net/peer/link/state", "core/net/peer/state" },
                changed = { "scope/portal", "core/net/peer/link/state", "core/net/peer/state", "core/net/peer/mirror" },
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
-- the same sync, with `scope/portal.target` turned back here, and the portal's owner, which core
-- names to the target as the person (it gives the placer's client authority only over what the
-- sync makes the client's, as on the portal; a placed portal's is the server's), so whatever another mod syncs on a
-- dropped portal stands in the target too. `scope/portal/hosted` is this half's mark and is not
-- copied: here the return end is never hosted, and there the target's server marks it. The names
-- come from data, so the copy reads through `with_columns`. A portal that comes to sync a name its
-- return end lacks gets a new one, a run later: the target keeps a mirror's sync as it arrived, and
-- a despawn and spawn of one id sent in one frame would reach it spawn first.
-- Left out of the copy and its sync: `placement` is the placer's while placing, synced from their
-- client, and on a return end it would let that client write it there and into the target's mirror.
local LEFT_OUT = { placement = true }

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
                if type(entry) == "table" and not LEFT_OUT[name] and covers and carried[name] == nil then covers = false end
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
                if type(entry) == "table" and not LEFT_OUT[name] and not named[name] then
                    named[name] = true
                    names[#names + 1] = name
                end
            end
        end
    end
    names[#names + 1] = "core/net/owner"
    local copied = synced:with_columns({ optional = names })
    for _, w in ipairs(wanting) do
        local row = copied:get(w.portal)
        if row ~= nil and not kept[w.id] then
            kept[w.id] = true
            local sync = row:get("core/net/sync")
            local spawn, carried = {}, {}
            for name, entry in pairs(sync) do
                if not LEFT_OUT[name] then carried[name] = entry end
                if type(entry) == "table" and name ~= "scope/portal/hosted" and not LEFT_OUT[name] then
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
            spawn["core/net/sync"] = carried
            spawn["core/net/owner"] = row:get("core/net/owner")
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
        optional = { "Name", "core/net/peer/mirror", "scope/portal/hosted" },
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
        -- Not a find link core opened under a link: it names no world, only the one it asks about.
        if cfg.at == nil and cfg.scope_key ~= nil and cfg.find == nil then identity[cfg.scope_key] = cfg.name end
    end
    for _, p in ipairs(portals:iter()) do
        local portal = p:get("scope/portal")
        local target = portal.target
        local entered = waiting(p) and {} or p:get("collision_trigger").entered or {}
        local door = portal.at ~= nil and p:has("Name")
        for _, player in ipairs(players:iter_many(entered)) do
            local to = target or way_back(p, portal, player)
            local link = door_link(p, portal, to) or (to ~= nil and identity[to] or nil)
            if to ~= nil and to ~= mine then
                -- Only through a door to a target: a world the player comes back to, by the way back
                -- or through a portal that is not a door, keeps where the player came to it from,
                -- which this one would replace. Cleared on every other crossing, as the share keeps
                -- its `transfer_data`.
                local from = door and target ~= nil and mine ~= nil and { target = mine, door = portal.at } or nil
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

-- A return end follows its portal's owner: core tells the target who owns it now.
app:add_systems(Update, {
    Query[{
        ["or"] = { added = { "core/net/owner" }, changed = { "core/net/owner" }, removed = { "core/net/owner" } },
        with = { "scope/portal", "scope/portal/returns" },
        optional = { "core/net/owner" },
    }],
    Commands,
}, function(portals, commands)
    for _, p in ipairs(portals:iter()) do
        local owner = p:get("core/net/owner")
        for _, r in ipairs(p:get("scope/portal/returns") or {}) do
            if owner ~= nil then
                commands:entity(r):insert({ ["core/net/owner"] = owner })
            else
                commands:entity(r):remove("core/net/owner")
            end
        end
    end
end):in_set("scope/portal/server")

-- A PORTAL ANOTHER WORLD STANDS HERE (a mirrored portal: its return end) stays only if it leads
-- back to the world that sent it (`core/net/peer/mirror.source_peer`, the proved scope, so a world
-- can stand here only a way back to itself), names no place (`at`: a return end never does) and
-- names its placer; it stands once this world holds the placer's connection (`waiting`, above). One
-- refused is despawned with one line, before it is linked or hosted. The source's later re-send is
-- refused the same way.
app:add_systems(Update, {
    Query[{
        ["or"] = { added = { "core/net/peer/mirror" }, changed = { "core/net/peer/mirror", "scope/portal" } },
        with = { "scope/portal", "core/net/peer/mirror" },
    }],
    Commands,
}, function(mirrored, commands)
    for _, p in ipairs(mirrored:iter()) do
        local portal, m = p:get("scope/portal"), p:get("core/net/peer/mirror")
        local why = (portal.target ~= m.source_peer and "leads-elsewhere")
            or (portal.at ~= nil and "at-on-return")
            or ((type(m.owner) ~= "table" or m.owner.client == nil) and "no-owner")
            or nil
        if why ~= nil then
            commands:entity(p:id()):despawn()
            print(string.format("[SCOPE/PORTAL] a portal %s stood here refused: %s", tostring(m.source_peer), why))
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
