-- edit/notice: an upload in flight, said on screen.
--
-- E1  an upload of more than one chunk gets one card, which says it waits for the world
-- E2  sending, its line says how much the world holds and its bar fills to match
-- E3  an upload of one chunk gets no card
-- E4  the upload answered, its card fades out
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

local function card(world, path)
    for _, e in ipairs(world:query({ with = { "edit/notice/card" }, optional = { "notification", "notification/fade", "Children" } })) do
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
        commands:spawn({ ["core/library/upload"] = { path = "maps/lab.glb", bytes = 10 * MB, total = 100, got = 0, state = "waiting" },
            ChildOf = library, ["core/net/sync"] = false })
        commands:spawn({ ["core/library/upload"] = { path = "small.lua", bytes = 100, total = 1, got = 0, state = "waiting" },
            ChildOf = library, ["core/net/sync"] = false })
        step("waiting")
    elseif phase == "waiting" then
        local s = said(world, "maps/lab.glb")
        if not s and clock < 5 then return end
        T("E1_a_card_says_it_waits_for_the_world", s == "Waiting for the world to accept maps/lab.glb…", tostring(s))
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
        finish()
    end
end):in_set("zz/edit_notice_flow")
