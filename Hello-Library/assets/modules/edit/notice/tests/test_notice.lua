-- edit/notice: an upload in flight, said on screen.
--
-- E0  an upload still waiting for the world shows nothing for its first 10 s
-- E1  ...and then one card, which says it waits for the world
-- E2  sending, its line says how much the world holds and its bar fills to match
-- E3  an upload of one chunk gets no card
-- E4  the upload answered, its card fades out
-- E5  an upload that streams within its first 10 s is shown at once
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("EditNoticeSuite")
local T = suite.assert_test

local MB = 1024 * 1024
local library

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ ["edit/notice"] = {} })
    library = commands:spawn({ ["zz/library"] = {} }):id()
end)

--- The shown card for `path` (a notification), or nil.
local function card(world, path)
    for _, e in ipairs(world:query({ with = { "edit/notice/card", "notification" }, optional = { "notification/fade", "Children" } })) do
        if e:get("edit/notice/card").path == path then return e end
    end
end
local function said(world, path)
    local c = card(world, path)
    for _, t in ipairs(world:query({ with = { "Text", "ChildOf" } })) do
        if c and t:get("ChildOf") == c:id() then return tostring(t:get("Text")) end
    end
end
local function width(world)
    for _, b in ipairs(world:query({ with = { "edit/notice/bar", "Node" } })) do
        local w = b:get("Node").width
        return type(w) == "table" and w.Percent or w
    end
end
local function row(world, path)
    for _, e in ipairs(world:query({ with = { "core/library/upload" } })) do
        if e:get("core/library/upload").path == path then return e end
    end
end
local function upload(commands, path, bytes, total, state)
    commands:spawn({ ["core/library/upload"] = { path = path, bytes = bytes, total = total, got = 0, state = state },
        ChildOf = library, ["core/net/sync"] = false })
end

local phase, clock = "spawn", 0
app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(p) phase, clock = p, 0 end
    local function finish()
        phase = "done"
        suite.finish("EDIT_NOTICE")
    end
    if phase == "done" then return end

    if phase == "spawn" then
        upload(commands, "maps/lab.glb", 10 * MB, 100, "waiting")
        upload(commands, "small.lua", 100, 1, "waiting")
        step("early")
    elseif phase == "early" and clock > 3 then
        T("E0_a_waiting_upload_shows_nothing_at_first", card(world, "maps/lab.glb") == nil, "a card after 3 s")
        step("waiting")
    elseif phase == "waiting" then
        local s = said(world, "maps/lab.glb")
        if not s and clock < 12 then return end
        T("E1_after_its_wait_a_card_says_it_waits_for_the_world", s == "Waiting for the world to accept maps/lab.glb…", tostring(s))
        T("E3_a_one_chunk_upload_gets_no_card", card(world, "small.lua") == nil, "a card for small.lua")
        row(world, "maps/lab.glb"):patch({ ["core/library/upload"] = { got = 50, state = "sending" } })
        step("sending")
    elseif phase == "sending" then
        local s = said(world, "maps/lab.glb")
        if (s == nil or not s:find("Sending", 1, true)) and clock < 5 then return end
        T("E2_sending_says_how_much_and_fills_the_bar",
            s == "Sending maps/lab.glb — 5.0 / 10.0 MB" and width(world) == 50,
            tostring(s) .. " bar=" .. tostring(width(world)))
        commands:entity(row(world, "maps/lab.glb"):id()):despawn()
        step("gone")
    elseif phase == "gone" then
        local c = card(world, "maps/lab.glb")
        local fading = c == nil or c:has("notification/fade") or (c:get("notification") or {}).dismiss == true
        if not fading and clock < 5 then return end
        T("E4_the_card_fades_when_the_upload_is_answered", fading, "card still shown")
        upload(commands, "maps/quick.glb", 2 * MB, 20, "waiting")
        step("quick")
    elseif phase == "quick" and clock > 0.5 then
        row(world, "maps/quick.glb"):patch({ ["core/library/upload"] = { got = 10, state = "sending" } })
        step("quick shown")
    elseif phase == "quick shown" then
        local s = said(world, "maps/quick.glb")
        if not s and clock < 3 then return end
        T("E5_an_upload_streaming_early_is_shown_at_once", s ~= nil and s:find("Sending", 1, true) ~= nil and clock < 3,
            tostring(s) .. string.format(" after %.1f s", clock))
        finish()
    end
end):in_set("zz/edit_notice_flow")
