-- voip, the server's half: voice chat in a world whose boot spawns `voip`. Each of this world's
-- players is a participant. The server relays a participant's voice frames to the others on the
-- world net's `voip/frame` channel, says who is speaking, and applies a silence only from a user
-- whose `core/permission/grants` name "writer". Frames are base64 text the server never decodes.
--
-- voip = {}
-- voip/participant = {
--     client_id = <the client id of the connection that owns the player>,
--     login = <the GitHub login the connection's join ticket links; absent when it has none>,
--     speaking = <a frame of theirs was relayed in the last 300 ms>,
--     silenced = <their connection carries voip/silenced>,
-- }
-- voip/silence = {
--     [<a participant's client id, as a string>] = <true to silence them, false to unsilence>,
-- }
-- voip/silence/applied = {
--     [<client id, as a string>] = <that user's entry as last applied>,
-- }
-- voip/silenced = {}
-- voip/heard = {
--     at = <this world's clock, in seconds, when a frame of theirs was last stamped>,
-- }

local Time = require("bevy::time::Time")
local bevy = require("bevy::prelude")

-- The world net's channel, on its Unreliable lane. The client half declares it on its side too:
-- a name one side has not declared is dropped there.
app:add_systems(First, {
    Query[{
        with = { "core/net", "core/world/net" },
        without = { "WorldMirror" },
        optional = { "core/net/channels" },
    }],
    Commands,
}, function(nets, commands)
    for _, net in ipairs(nets:iter()) do
        local channels = net:has("core/net/channels") and net:get("core/net/channels") or {}
        if net:get("core/net").mode == "server" and (channels.Unreliable or {})["voip/frame"] == nil then
            commands:entity(net:id()):entry("core/net/channels"):or_default():and_modify(function(declared)
                declared.Unreliable = declared.Unreliable or {}
                declared.Unreliable["voip/frame"] = {}
            end)
        end
    end
end):in_set("voip/server"):run_if({
    Query[{ added = { "voip" }, without = { "WorldMirror" } }],
    Query[{ added = { "core/net" }, with = { "core/world/net" }, without = { "WorldMirror" } }],
}, function(carried, started)
    return not carried:is_empty() or not started:is_empty()
end)

-- The last carrier left: the channel and the players' sync entries this half declared go. The
-- registry takes the mod's own components off every entity as it unloads.
app:add_systems(First, {
    Query[{ removed = { "voip" } }],
    Query[{ with = { "voip" }, without = { "WorldMirror" } }],
    Query[{ with = { "core/net", "core/world/net", "core/net/channels" }, without = { "WorldMirror" } }],
    Query[{ with = { "player", "core/net/sync" }, without = { "WorldMirror" } }],
    Commands,
}, function(removed, carriers, nets, players, commands)
    for _, _ in ipairs(removed:iter()) do
        for _, net in ipairs(carriers:is_empty() and nets:iter() or {}) do
            if (net:get("core/net/channels").Unreliable or {})["voip/frame"] ~= nil then
                commands:entity(net:id()):entry("core/net/channels"):and_modify(function(declared)
                    declared.Unreliable["voip/frame"] = nil
                end)
            end
        end
        for _, p in ipairs(carriers:is_empty() and players:iter() or {}) do
            local sync = p:get("core/net/sync")
            if type(sync) == "table" and (sync["voip/participant"] ~= nil or sync["voip/silence"] ~= nil) then
                commands:entity(p:id()):entry("core/net/sync"):and_modify(function(entries)
                    entries["voip/participant"] = nil
                    entries["voip/silence"] = nil
                end)
            end
        end
        break
    end
end):in_set("voip/server")

-- Each of this world's players is a participant, written from the connection that owns it: who
-- it is, from the attestation, and whether it is silenced. A player another world shares here
-- (`core/net/peer/mirror`) is that world's.
app:add_systems(Update, {
    Query[{ ["or"] = { added = { "player" }, changed = { "core/net/owner" } } }],
    Query[{
        ["or"] = {
            changed = { "core/net/connection", "core/player/attest" },
            added = { "voip/silenced" },
            removed = { "voip/silenced" },
        },
    }],
    Query[{
        with = { "core/net/connection" },
        without = { "core/net", "WorldMirror" },
        optional = { "core/player/attest", "voip/silenced", "core/net/owns" },
    }],
    Query[{
        with = { "player", "core/net/owner" },
        without = { "WorldMirror", "core/net/peer/mirror" },
        optional = { Mut["voip/participant"], "core/net/sync" },
    }],
    Commands,
}, function(players_touched, connections_touched, connections, players, commands)
    local ids = {}
    for _, p in ipairs(players_touched:iter()) do
        ids[#ids + 1] = p:id()
    end
    for _, touched in ipairs(connections_touched:iter()) do
        local connection = connections:get(touched:id())
        for _, owned in ipairs(connection and connection:get("core/net/owns") or {}) do
            ids[#ids + 1] = owned
        end
    end
    for _, p in ipairs(players:iter_many_mut(ids)) do
        local connection = connections:get(p:get("core/net/owner"))
        if connection then
            local attest = connection:has("core/player/attest") and connection:get("core/player/attest") or {}
            local client_id = connection:get("core/net/connection").client_id
            local login = attest.state == "attested" and (attest.links or {}).github or nil
            local silenced = connection:has("voip/silenced")
            if p:has("voip/participant") then
                local participant = p:get_mut("voip/participant")
                participant.client_id = client_id
                participant.login = login
                participant.silenced = silenced
            else
                commands:entity(p:id()):insert({
                    ["voip/participant"] = {
                        client_id = client_id,
                        login = login,
                        speaking = false,
                        silenced = silenced,
                    },
                })
            end
            local sync = p:get("core/net/sync")
            if type(sync) == "table" and (sync["voip/participant"] == nil or sync["voip/silence"] == nil) then
                commands:entity(p:id()):entry("core/net/sync"):and_modify(function(entries)
                    entries["voip/participant"] = { authority = "server" }
                    entries["voip/silence"] = { authority = "client", target = "owner" }
                end)
            end
        end
    end
end):in_set("voip/server")

-- A player handed to another world stays here as its mirror, and one whose connection went keeps
-- no owner: neither is a participant here any more.
app:add_systems(Update, {
    Query[{
        ["or"] = { added = { "core/net/peer/mirror" }, removed = { "core/net/owner" } },
        with = { "voip/participant" },
    }],
    Commands,
}, function(left, commands)
    for _, p in ipairs(left:iter()) do
        commands:entity(p:id()):try_remove("voip/participant")
    end
end):in_set("voip/server")

-- The relay. A frame is forwarded only from a participant here who is not an observer and not
-- silenced, when it is well formed, at most 2,048 bytes, and among its sender's first 4 of this
-- run; it goes to every other participant here who is not an observer, with `from` the sender's
-- client id as core stamped it, never one the sender wrote. Each sender's connection is stamped
-- `voip/heard` at most every 100 ms.
app:add_systems(Update, {
    Res[Time],
    bevy.MessageReader["core/net/received"],
    Query[{ with = { "core/net", "core/world/net" }, without = { "WorldMirror" } }],
    Query[{
        with = { "core/net/connection", "ChildOf" },
        without = { "core/net", "WorldMirror" },
        optional = { "core/net/owns", "voip/silenced", Mut["voip/heard"] },
    }],
    Query[{ with = { "voip/participant" }, without = { "WorldMirror", "core/net/peer/mirror" } }],
    bevy.MessageWriter["core/net/send_to_client"],
    Commands,
}, function(time, received, nets, connections, participants, to_client, commands)
    local now = time:elapsed_secs()
    local net = nets:iter()[1]
    local config = net and net:get("core/net")
    local name = config and config.mode == "server" and config.name or nil
    -- Root's Lua messages are copied into every world VM, so only this world net's are its own.
    local frames = {}
    for _, m in ipairs(received:read()) do
        if m.channel == "voip/frame" and name ~= nil and m.net == name then frames[#frames + 1] = m end
    end
    local senders, listeners = {}, {}
    for _, c in ipairs(#frames > 0 and connections:iter_mut() or {}) do
        if c:get("ChildOf") == net:id() then
            local connection = c:get("core/net/connection")
            local here = participants:iter_many(c:get("core/net/owns") or {})[1] ~= nil
            senders[tostring(connection.client_id)] = { row = c, here = here, observer = connection.observer == true }
            if here and connection.observer ~= true then listeners[#listeners + 1] = connection.client_id end
        end
    end
    local forwarded, stamped = {}, {}
    for _, m in ipairs(frames) do
        local key = tostring(m.client_id)
        local sender = senders[key]
        local data = m.data
        if sender ~= nil and sender.here and not sender.observer and not sender.row:has("voip/silenced")
            and m.msg_type == "voip/frame" and type(m.codec) == "number"
            and type(data) == "string" and #data > 0 and #data <= 2048 and not data:find("[^%w%+/=]")
            and (forwarded[key] or 0) < 4 then
            forwarded[key] = (forwarded[key] or 0) + 1
            for _, client_id in ipairs(listeners) do
                if client_id ~= m.client_id then
                    to_client:write({
                        client_id = client_id,
                        net = name,
                        msg = { msg_type = "voip/frame", channel = "voip/frame", codec = m.codec, data = data, from = m.client_id },
                    })
                end
            end
            if not stamped[key] then
                stamped[key] = true
                local row = sender.row
                if not row:has("voip/heard") then
                    commands:entity(row:id()):insert({ ["voip/heard"] = { at = now } })
                elseif now - row:get("voip/heard").at >= 0.1 then
                    row:get_mut("voip/heard").at = now
                end
            end
        end
    end
end):in_set("voip/server"):run_if({ bevy.MessageReader["core/net/received"] }, function(received)
    return #received:read() > 0
end)

-- Speaking on a stamp.
app:add_systems(Update, {
    Query[{ changed = { "voip/heard" }, optional = { "core/net/owns" } }],
    Query[{ with = { Mut["voip/participant"] }, without = { "WorldMirror", "core/net/peer/mirror" } }],
}, function(stamped, participants)
    for _, c in ipairs(stamped:iter()) do
        for _, p in ipairs(participants:iter_many_mut(c:get("core/net/owns") or {})) do
            p:get_mut("voip/participant").speaking = true
        end
    end
end):in_set("voip/server")

-- Timed: no longer speaking 300 ms after the last stamp. Runs only while someone speaks.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { Mut["voip/participant"], "core/net/owner" },
        without = { "WorldMirror", "core/net/peer/mirror" },
    }],
    Query[{ with = { "core/net/connection" }, optional = { "voip/heard" } }],
}, function(time, participants, connections)
    local now = time:elapsed_secs()
    for _, p in ipairs(participants:iter_mut()) do
        if p:get("voip/participant").speaking then
            local connection = connections:get(p:get("core/net/owner"))
            local heard = connection and connection:has("voip/heard") and connection:get("voip/heard")
            if not heard or now - heard.at >= 0.3 then
                p:get_mut("voip/participant").speaking = false
            end
        end
    end
end):in_set("voip/server"):run_if({
    Query[{ with = { "voip/participant" }, without = { "WorldMirror", "core/net/peer/mirror" } }],
}, function(participants)
    for _, p in ipairs(participants:iter()) do
        if p:get("voip/participant").speaking then return true end
    end
    return false
end)

-- Silence. A player's `voip/silence` is its owner's wish; the server applies it only while the
-- owner's connection holds "writer" in its grants, read here on every entry, never from anything
-- the client sends. A user never silences themself. Only the entries that differ from what was
-- last applied for that user (`voip/silence/applied`, on their connection) are applied, so one
-- user's standing entry never undoes another user's later change. An entry gone from the map
-- changes nothing.
app:add_systems(Update, {
    Query[{
        changed = { "voip/silence" },
        with = { "voip/participant", "core/net/owner" },
        without = { "WorldMirror", "core/net/peer/mirror" },
    }],
    Query[{
        with = { "core/net/connection", "ChildOf" },
        without = { "core/net", "WorldMirror" },
        optional = { "core/permission/grants", "core/net/owns", "voip/silenced", "voip/silence/applied" },
    }],
    Query[{ with = { "voip/participant" }, without = { "WorldMirror", "core/net/peer/mirror" } }],
    Commands,
}, function(asks, connections, participants, commands)
    for _, ask in ipairs(asks:iter()) do
        local from = connections:get(ask:get("core/net/owner"))
        local grants = from and from:has("core/permission/grants") and from:get("core/permission/grants") or {}
        local writer = false
        for _, granted in ipairs(grants.names or {}) do
            if granted == "writer" then writer = true end
        end
        local wishes = ask:get("voip/silence")
        local applied = writer and from:has("voip/silence/applied") and from:get("voip/silence/applied") or {}
        for _, c in ipairs(writer and connections:iter() or {}) do
            local key = tostring(c:get("core/net/connection").client_id)
            local wanted = wishes[key]
            if wanted ~= nil and wanted ~= applied[key] and c:id() ~= from:id() and c:get("ChildOf") == from:get("ChildOf")
                and participants:iter_many(c:get("core/net/owns") or {})[1] ~= nil then
                if wanted == true and not c:has("voip/silenced") then
                    commands:entity(c:id()):insert({ ["voip/silenced"] = {} })
                elseif wanted == false and c:has("voip/silenced") then
                    commands:entity(c:id()):remove("voip/silenced")
                end
            end
        end
        if writer then
            local now = {}
            for key, wanted in pairs(wishes) do
                now[key] = wanted
            end
            commands:entity(from:id()):insert({ ["voip/silence/applied"] = now })
        else
            print(string.format("[VOIP] a silence from client %s ignored: its grants do not name \"writer\"",
                tostring(ask:get("voip/participant").client_id)))
        end
    end
end):in_set("voip/server")

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
