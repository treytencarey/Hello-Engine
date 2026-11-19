-- voip, the client's half: the local player speaks through root's microphone and hears the
-- others. One ask of root per world visit, a child of this client's copy of the `voip` carrier,
-- says whether the device is open and which blocks go; the packets root writes on its reply are
-- sent on the world net's `voip/frame` channel. Frames from the others are decoded per source,
-- held in each source's jitter buffer, and mixed into one speaker. V, held, is push-to-talk in
-- game input.
--
-- voip = {
--     complexity = <the Opus encoder's complexity root uses, 0 to 10; 5 when absent>,
-- }
-- voip/mic = {
--     muted = <the player muted their microphone>,
--     mode = "push" | "voice",
-- }
-- voip/intent = {
--     transmit = <the ask is open and root allowed it>,
--     listen = <this player hears the others>,
--     taken = <the number of the newest packet taken from root's reply>,
-- }
-- voip/participant/local = {
--     local_muted = <this player muted that participant for themself>,
-- }
-- voip/indicator = {}
-- voip/control = {
--     kind = "speaking" | "mute" | "silence" | "mic" | "level" | "mode",
-- }
--     on voip's items in the people panel's rows (`sidebar/people/row/item`)

local bevy = require("bevy::prelude")
local Option = require("std::option::Option")
local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local StandardMaterial = require("bevy::pbr::StandardMaterial")
local Sphere = require("bevy::math::primitives::Sphere")
local OpusDecoders = require("hello::audio::OpusDecoders")
local Speakers = require("hello::audio::Speakers")
local Base64 = require("modules/voip/client/base64.lua")

-- Each source's jitter buffer: source -> { blocks = { <960 samples, 16-bit mono PCM at 48 kHz,
-- as a byte string>, ... }, primed, ever_primed }. Held in this VM's Lua memory, not on a
-- component: it is audio, rewritten 50 times a second per source, and a reload losing it costs
-- at most a second of buffered speech, re-primed in 60 ms.
local sources = {}

-- The world net's channel, on its Unreliable lane, as the server half declares it on its side.
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
        if net:get("core/net").mode == "client" and (channels.Unreliable or {})["voip/frame"] == nil then
            commands:entity(net:id()):entry("core/net/channels"):or_default():and_modify(function(declared)
                declared.Unreliable = declared.Unreliable or {}
                declared.Unreliable["voip/frame"] = {}
            end)
        end
    end
end):in_set("voip/client"):run_if({
    Query[{ added = { "voip" }, without = { "WorldMirror" } }],
    Query[{ added = { "core/net" }, with = { "core/world/net" }, without = { "WorldMirror" } }],
}, function(carried, started)
    return not carried:is_empty() or not started:is_empty()
end)

-- The local voice player: its microphone settings, its intent and its push-to-talk key. A remote
-- participant gets its local mute. Bound again when `input` comes back, as bindings go with it.
app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "voip/participant", "input" },
            changed = { "core/net/owner" },
        },
        with = { "voip/participant" },
        optional = { "core/net/owner", "input" },
    }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Query[{ with = { "voip" }, without = { "WorldMirror" }, optional = { "Children" } }],
    Query[{
        with = { "vault/microphone", "Request" },
        without = { "RequestFrom" },
        optional = { "vault/microphone/reply" },
    }],
    Commands,
}, function(participants, own, carriers, asks, commands)
    local carrier = carriers:iter()[1]
    local ask = carrier and asks:iter_many(carrier:get("Children") or {})[1]
    local reply = ask and ask:has("vault/microphone/reply") and ask:get("vault/microphone/reply")
    for _, p in ipairs(participants:iter()) do
        if p:has("core/net/owner") and own:contains(p:get("core/net/owner")) then
            commands:entity(p:id()):insert_if_new({
                ["voip/mic"] = { muted = false, mode = "push" },
                -- Packets already on the reply are old: a new player starts after them.
                ["voip/intent"] = { transmit = false, listen = true, taken = reply and reply.last or 0 },
            })
            if p:has("input") then
                commands:entity(p:id()):entry("input/game"):or_default():and_modify(function(game)
                    game.voip = { talk = { key = "KeyV" } }
                end)
            end
        else
            commands:entity(p:id()):insert_if_new({ ["voip/participant/local"] = { local_muted = false } })
        end
    end
end):in_set("voip/client")

-- A participant gone from an entity that stays: what this half added for it goes, its key is
-- unbound, and its source and decoder go. A despawned one is in the removed rows too.
app:add_systems(First, {
    Query[{
        ["or"] = { removed = { "voip/participant" } },
        optional = { "voip/participant", "input", "Children" },
    }],
    Query[{ with = { "voip/indicator" } }],
    ResMut[OpusDecoders],
    Commands,
}, function(removed, indicators, decoders, commands)
    for _, p in ipairs(removed:iter()) do
        local participant = p:get("voip/participant")
        local source = participant and tostring(participant.client_id)
        if source then
            sources[source] = nil
            decoders:remove(source)
        end
        local entity = commands:get_entity(p:id())
        if entity then
            entity:try_remove("voip/mic", "voip/intent", "voip/participant/local")
            if p:has("input") then
                entity:entry("input/game"):and_modify(function(game) game.voip = nil end)
            end
        end
        for _, marker in ipairs(indicators:iter_many(p:get("Children") or {})) do
            commands:entity(marker:id()):try_despawn()
        end
    end
end):in_set("voip/client")

-- The last carrier gone: the channel, the ask, the push-to-talk key, the speaker and every
-- source's buffer and decoder go. The registry takes the mod's own components as it unloads.
app:add_systems(First, {
    Query[{ removed = { "voip" } }],
    Query[{ with = { "voip" }, without = { "WorldMirror" } }],
    Query[{ with = { "core/net", "core/world/net", "core/net/channels" }, without = { "WorldMirror" } }],
    Query[{ with = { "vault/microphone", "Request", "ChildOf" }, without = { "RequestFrom" } }],
    Query[{ with = { "voip/participant" }, optional = { "input" } }],
    Option[ResMut[Speakers]],
    ResMut[OpusDecoders],
    Commands,
}, function(removed, carriers, nets, asks, participants, speakers, decoders, commands)
    local gone = {}
    for _, carrier in ipairs(removed:iter()) do
        gone[#gone + 1] = carrier:id()
    end
    for _, ask in ipairs(asks:iter()) do
        for _, carrier in ipairs(gone) do
            if ask:get("ChildOf") == carrier then commands:entity(ask:id()):try_despawn() end
        end
    end
    local last = #gone > 0 and carriers:is_empty()
    for _, net in ipairs(last and nets:iter() or {}) do
        if (net:get("core/net/channels").Unreliable or {})["voip/frame"] ~= nil then
            commands:entity(net:id()):entry("core/net/channels"):and_modify(function(declared)
                declared.Unreliable["voip/frame"] = nil
            end)
        end
    end
    for _, p in ipairs(last and participants:iter() or {}) do
        local source = tostring(p:get("voip/participant").client_id)
        sources[source] = nil
        decoders:remove(source)
        if p:has("input") then
            commands:entity(p:id()):entry("input/game"):and_modify(function(game) game.voip = nil end)
        end
    end
    if last and speakers then speakers:remove("voip/speaker") end
end):in_set("voip/client")

-- A participant muted for this player alone: what of theirs is buffered goes too.
app:add_systems(First, {
    Query[{ changed = { "voip/participant/local" }, with = { "voip/participant" } }],
}, function(muted)
    for _, p in ipairs(muted:iter()) do
        if p:get("voip/participant/local").local_muted then
            sources[tostring(p:get("voip/participant").client_id)] = nil
        end
    end
end):in_set("voip/client")

-- The ask of root, and the intent, on their inputs' edges: the microphone settings, the
-- participant, the talk key, the owner, the carrier and root's reply. A respawned player keeps
-- the ask, so one dialog covers the visit.
app:add_systems(Update, {
    Query[{ with = { "voip" }, without = { "WorldMirror" }, optional = { "Children" } }],
    Query[{
        with = { Mut["vault/microphone"], "Request" },
        without = { "RequestFrom" },
        optional = { "vault/microphone/reply" },
    }],
    Query[{
        with = { "voip/participant", "core/net/owner", "voip/mic", Mut["voip/intent"] },
        optional = { "input/game/voip/talk" },
    }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(carriers, asks, players, own, commands)
    local carrier = carriers:iter()[1]
    local player = nil
    for _, p in ipairs(players:iter_mut()) do
        if own:contains(p:get("core/net/owner")) then
            player = p
            break
        end
    end
    local mic = player and player:get("voip/mic")
    local participant = player and player:get("voip/participant")
    local open = player ~= nil and not mic.muted and not participant.silenced
    local send = "none"
    if player ~= nil and mic.mode == "voice" then
        send = "voice"
    elseif player ~= nil and player:has("input/game/voip/talk") then
        send = "all"
    end
    local complexity = carrier and carrier:get("voip").complexity or 5
    local ask = carrier and asks:iter_many_mut(carrier:get("Children") or {})[1]
    if ask then
        local wanted = ask:get_mut("vault/microphone")
        wanted.open, wanted.send, wanted.complexity = open, send, complexity
    elseif carrier and player then
        commands:spawn({
            ["vault/microphone"] = { open = open, send = send, complexity = complexity },
            Request = {},
            ChildOf = carrier:id(),
            ["core/net/sync"] = false,
            -- The ask outlives a reload of this mod, so a reload asks the player nothing; it goes
            -- with the carrier, or when `voip` leaves it.
            ["core/script/owner"] = false,
        })
    end
    if player then
        local allowed = ask ~= nil and ask:has("vault/microphone/reply")
            and ask:get("vault/microphone/reply").status == "allowed"
        local intent = player:get_mut("voip/intent")
        intent.transmit = open and allowed
        intent.listen = true
    end
end):in_set("voip/client"):run_if({
    Query[{
        ["or"] = {
            changed = { "voip/mic", "voip/participant", "voip/intent", "voip", "core/net/owner",
                "input/game/voip/talk", "vault/microphone/reply" },
            removed = { "input/game/voip/talk" },
        },
    }],
}, function(touched)
    return not touched:is_empty()
end)

-- Send. A world's `First` systems never see a newly arrived reply, so this reads it in `Update`.
-- The reply holds root's newest packets, numbered up to `last`: those above `taken` go, one
-- frame each. Packets older than the window are lost, and said in the log.
app:add_systems(Update, {
    Query[{
        changed = { "vault/microphone/reply" },
        with = { "vault/microphone", "ChildOf" },
        without = { "RequestFrom" },
    }],
    Query[{ with = { "voip" }, without = { "WorldMirror" } }],
    Query[{ with = { "voip/participant", "core/net/owner", Mut["voip/intent"] } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    bevy.MessageWriter["core/net/send"],
}, function(replies, carriers, players, own, send)
    for _, ask in ipairs(replies:iter()) do
        for _, p in ipairs(carriers:contains(ask:get("ChildOf")) and players:iter_mut() or {}) do
            if own:contains(p:get("core/net/owner")) then
                local reply = ask:get("vault/microphone/reply")
                local intent = p:get_mut("voip/intent")
                local packets = reply.packets or {}
                local first = (reply.last or 0) - #packets + 1
                if ask:get("vault/microphone").open and reply.status == "allowed" then
                    for i, packet in ipairs(packets) do
                        if first + i - 1 > intent.taken then
                            send:write({ msg_type = "voip/frame", channel = "voip/frame", codec = 2, data = packet })
                        end
                    end
                    if intent.taken > 0 and first > intent.taken + 1 then
                        print(string.format("[VOIP] %d microphone packets lost before packet %d",
                            first - intent.taken - 1, first))
                    end
                end
                if reply.last ~= nil then intent.taken = reply.last end
            end
        end
    end
end):in_set("voip/client")

-- Receive. Root's Lua messages are copied into every world VM, so only this world net's frames
-- are its own. A frame of this player's own, or from a participant this player muted, is never
-- decoded.
app:add_systems(Update, {
    bevy.MessageReader["core/net/received"],
    Query[{ with = { "core/net", "core/world/net" }, without = { "WorldMirror" } }],
    Query[{ with = { "voip/participant" }, optional = { "voip/participant/local", "core/net/owner" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    ResMut[OpusDecoders],
}, function(received, nets, participants, own, decoders)
    local net = nets:iter()[1]
    local config = net and net:get("core/net")
    local name = config and config.mode == "client" and config.name or nil
    local frames = {}
    for _, m in ipairs(received:read()) do
        if m.channel == "voip/frame" and name ~= nil and m.net == name then frames[#frames + 1] = m end
    end
    local mine = nil
    for _, p in ipairs(#frames > 0 and participants:iter() or {}) do
        if p:has("core/net/owner") and own:contains(p:get("core/net/owner")) then
            mine = p:get("voip/participant").client_id
        end
    end
    for _, m in ipairs(frames) do
        local sender = nil
        for _, p in ipairs(participants:iter()) do
            if p:get("voip/participant").client_id == m.from then sender = p end
        end
        local muted = sender ~= nil and sender:has("voip/participant/local")
            and sender:get("voip/participant/local").local_muted
        local packet = sender ~= nil and m.from ~= mine and not muted and type(m.data) == "string"
            and Base64.decode(m.data) or nil
        if packet then
            local source = tostring(m.from)
            if not decoders:contains_key(source) then decoders:open(source, 48000, "Mono") end
            local ok, pcm = pcall(function() return decoders:get_mut(source):decode(packet, 960, "Normal") end)
            if not ok then
                print(string.format("[VOIP] a frame from %s did not decode: %s", source, tostring(pcm)))
            else
                local buffer = sources[source] or { blocks = {}, primed = false, ever_primed = false }
                sources[source] = buffer
                buffer.blocks[#buffer.blocks + 1] = pcm
                -- About a second per source; the oldest goes.
                if #buffer.blocks > 50 then table.remove(buffer.blocks, 1) end
                -- A source plays once 60 ms (3 blocks) wait, and after running dry once 2 do: a
                -- full refill after every dry spell never primes again when arrival only just
                -- keeps up with playback.
                if not buffer.primed and #buffer.blocks >= (buffer.ever_primed and 2 or 3) then
                    buffer.primed, buffer.ever_primed = true, true
                end
            end
        end
    end
end):in_set("voip/client"):run_if({ bevy.MessageReader["core/net/received"] }, function(received)
    return #received:read() > 0
end)

-- Playback, a per-frame drain as the device plays. While the speaker holds less than 60 ms, one
-- block of every primed source is summed, clamped, resampled to the device's rate when it is not
-- 48 kHz, and written once. A primed source with nothing left has run dry and primes again.
-- Silence is never written: the device underruns. A speaker with no device plays nothing, so its
-- queue fills to 60 ms and stays.
app:add_systems(Update, {
    Option[ResMut[Speakers]],
}, function(speakers)
    local speaker = speakers and speakers:get_mut("voip/speaker")
    local status = speaker and speaker:status()
    local rate = status and status.sample_rate > 0 and status.sample_rate or 48000
    local format = "<" .. string.rep("i2", 960)
    while status and status.state ~= "opening" and speaker:queued() < rate * 0.06 do
        local mixed = nil
        for _, buffer in pairs(sources) do
            if buffer.primed and #buffer.blocks == 0 then
                buffer.primed = false
            elseif buffer.primed then
                local block = { string.unpack(format, table.remove(buffer.blocks, 1)) }
                if mixed == nil then
                    mixed = block
                else
                    for i = 1, 960 do mixed[i] = mixed[i] + block[i] end
                end
            end
        end
        if mixed == nil then break end
        for i = 1, 960 do
            local v = mixed[i]
            if v > 32767 then mixed[i] = 32767 elseif v < -32768 then mixed[i] = -32768 end
        end
        if rate == 48000 then
            speaker:write(string.pack(format, table.unpack(mixed, 1, 960)))
        else
            local count = math.floor(960 * rate / 48000)
            local step, out = 48000 / rate, {}
            for j = 0, count - 1 do
                local x = j * step
                local i = math.floor(x)
                local a, b = mixed[i + 1], mixed[math.min(i + 2, 960)]
                out[j + 1] = math.floor(a + (b - a) * (x - i) + 0.5)
            end
            speaker:write(string.pack("<" .. string.rep("i2", count), table.unpack(out, 1, count)))
        end
    end
end):in_set("voip/client"):run_if(function()
    for _, buffer in pairs(sources) do
        if buffer.primed then return true end
    end
    return false
end)

-- The speaker: open while this player listens, removed when no one here does, with every
-- source's buffer. With no `Speakers` (no output), the player only speaks.
app:add_systems(Update, {
    Query[{ with = { "voip/intent" } }],
    Option[ResMut[Speakers]],
}, function(intents, speakers)
    local listen = false
    for _, p in ipairs(intents:iter()) do
        if p:get("voip/intent").listen then listen = true end
    end
    if speakers and listen and not speakers:contains_key("voip/speaker") then
        speakers:open("voip/speaker", { rate = 48000 })
    elseif speakers and not listen and speakers:contains_key("voip/speaker") then
        speakers:remove("voip/speaker")
        for source in pairs(sources) do sources[source] = nil end
    end
end):in_set("voip/client"):run_if({
    Query[{ ["or"] = { changed = { "voip/intent" }, removed = { "voip/intent" } } }],
}, function(touched)
    return not touched:is_empty()
end)

-- The speaking sphere over a participant who speaks. A headless world has no material assets:
-- the marker still comes and goes, with nothing drawn.
app:add_systems(Update, {
    Query[{ changed = { "voip/participant" }, optional = { "Children" } }],
    Query[{ with = { "voip/indicator" } }],
    Option[ResMut[Assets[Mesh]]],
    Option[ResMut[Assets[StandardMaterial]]],
    Commands,
}, function(participants, indicators, meshes, materials, commands)
    for _, p in ipairs(participants:iter()) do
        local speaking = p:get("voip/participant").speaking == true
        local marker = indicators:iter_many(p:get("Children") or {})[1]
        if speaking and marker == nil then
            commands:spawn({
                Transform = { translation = { x = 0, y = 1.4, z = 0 } },
                Mesh3d = meshes and materials and meshes:add(Sphere.new(0.12)) or nil,
                ["MeshMaterial3d<StandardMaterial>"] = meshes and materials and materials:add({
                    base_color = { Srgba = { red = 0.25, green = 0.85, blue = 0.35, alpha = 1 } },
                    emissive = { red = 0.1, green = 0.45, blue = 0.15, alpha = 1 },
                    perceptual_roughness = 0.4,
                }) or nil,
                ["voip/indicator"] = {},
                ChildOf = p:id(),
            })
        elseif not speaking and marker ~= nil then
            commands:entity(marker:id()):despawn()
        end
    end
end):in_set("voip/client")

-- voip's items in the people panel's rows. A row's player is its `sidebar/people/row/player`.
-- A remote participant's row gets the speaking dot, Mute and, while this client's own grants
-- name "writer", Silence; the local player's row gets the microphone, its level and the mode. A
-- row whose player is no participant gets none. Every label and `enabled` is written here, from
-- the state the item shows, never from a click. A rebuilt row is a new `added` edge, and gets its
-- items again.
app:add_systems(Update, {
    Query[{ with = { "sidebar/people/row", "sidebar/people/row/player" }, optional = { "Children" } }],
    Query[{ with = { "voip/control", Mut["sidebar/people/row/item"] } }],
    Query[{ with = { "voip/participant" }, optional = { "voip/participant/local", "voip/mic", "core/net/owner" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Query[{ with = { "core/net", "core/permission/grants" } }],
    Query[{ with = { "vault/microphone", "Request" }, without = { "RequestFrom" }, optional = { "vault/microphone/reply" } }],
    Commands,
}, function(rows, items, players, own, granted, asks, commands)
    local writer = false
    for _, net in ipairs(granted:iter()) do
        for _, name in ipairs(net:get("core/permission/grants").names or {}) do
            if name == "writer" then writer = true end
        end
    end
    local ask = asks:iter()[1]
    local reply = ask and ask:has("vault/microphone/reply") and ask:get("vault/microphone/reply") or {}
    for _, row in ipairs(rows:iter()) do
        local player = players:iter_many({ row:get("sidebar/people/row/player").entity })[1]
        local want = {}
        if player and player:has("core/net/owner") and own:contains(player:get("core/net/owner")) then
            local mic = player:has("voip/mic") and player:get("voip/mic") or { muted = false, mode = "push" }
            local level = reply.status == "allowed" and not mic.muted and reply.level or 0
            want.mic = { order = 1, label = mic.muted and "Unmute mic" or "Mute mic", button = true, enabled = true }
            want.level = { order = 2, label = string.rep("|", math.floor(level * 10 + 0.5)), button = false, enabled = true }
            want.mode = { order = 3, label = mic.mode == "voice" and "Open mic" or "Push to talk (V)", button = true, enabled = true }
        elseif player then
            local participant = player:get("voip/participant")
            local muted = player:has("voip/participant/local") and player:get("voip/participant/local").local_muted
            want.speaking = { order = 1, label = "*", button = false, enabled = participant.speaking == true }
            want.mute = { order = 2, label = muted and "Unmute" or "Mute", button = true, enabled = true }
            if writer then
                want.silence = { order = 3, label = participant.silenced and "Unsilence" or "Silence", button = true, enabled = true }
            end
        end
        local have = {}
        for _, item in ipairs(items:iter_many_mut(row:get("Children") or {})) do
            local kind = item:get("voip/control").kind
            local wanted = want[kind]
            if wanted == nil or have[kind] then
                commands:entity(item:id()):despawn()
            else
                have[kind] = true
                local shown = item:get_mut("sidebar/people/row/item")
                shown.label, shown.enabled = wanted.label, wanted.enabled
            end
        end
        for kind, wanted in pairs(want) do
            if not have[kind] then
                local spawned = commands:spawn({
                    ["sidebar/people/row/item"] = wanted,
                    ["voip/control"] = { kind = kind },
                    ChildOf = row:id(),
                })
                -- A dimmed button still reaches this observer: a click on one does nothing.
                if wanted.button then
                    spawned:observe(On[Pointer[Click]], {
                        Query[{ with = { "voip/control", "sidebar/people/row/item", "ChildOf" } }],
                        Query[{ with = { "sidebar/people/row/player" } }],
                        Query[{
                            with = { "voip/participant" },
                            optional = { Mut["voip/participant/local"], Mut["voip/mic"], "core/net/owner" },
                        }],
                        Query[{ with = { "core/net", "core/net/owns" } }],
                        Query[{ with = { "core/net", "core/permission/grants" } }],
                        Commands,
                    }, function(event, controls, links, participants, nets, grants, click_commands)
                        for _, item in ipairs(controls:iter_many({ event.entity })) do
                            local link = links:iter_many({ item:get("ChildOf") })[1]
                            local player = link and participants:iter_many_mut({ link:get("sidebar/people/row/player").entity })[1]
                            local clicked = item:get("voip/control").kind
                            local allowed = false
                            for _, net in ipairs(grants:iter()) do
                                for _, name in ipairs(net:get("core/permission/grants").names or {}) do
                                    if name == "writer" then allowed = true end
                                end
                            end
                            if player and item:get("sidebar/people/row/item").enabled then
                                if clicked == "mute" and player:has("voip/participant/local") then
                                    local mine = player:get_mut("voip/participant/local")
                                    mine.local_muted = not mine.local_muted
                                elseif clicked == "mic" and player:has("voip/mic") then
                                    local mic = player:get_mut("voip/mic")
                                    mic.muted = not mic.muted
                                elseif clicked == "mode" and player:has("voip/mic") then
                                    local mic = player:get_mut("voip/mic")
                                    mic.mode = mic.mode == "voice" and "push" or "voice"
                                elseif clicked == "silence" and allowed then
                                    local key = tostring(player:get("voip/participant").client_id)
                                    local silence = not player:get("voip/participant").silenced
                                    for _, me in ipairs(participants:iter()) do
                                        if me:has("core/net/owner") and nets:contains(me:get("core/net/owner")) then
                                            click_commands:entity(me:id()):entry("voip/silence"):or_default():and_modify(function(wishes)
                                                wishes[key] = silence
                                            end)
                                        end
                                    end
                                end
                            end
                        end
                    end)
                end
            end
        end
    end
end):in_set("voip/client"):run_if({
    Query[{
        ["or"] = {
            changed = { "sidebar/people/row", "voip/participant", "voip/participant/local", "voip/mic",
                "vault/microphone/reply", "core/permission/grants", "core/net/owner" },
            removed = { "voip/participant", "core/permission/grants" },
        },
    }],
}, function(touched)
    return not touched:is_empty()
end)

return {}
