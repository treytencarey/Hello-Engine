-- edit/notice: what happened to this player's edits, said on screen.
--
-- E6  a replacement core records gets a card that says which copy is kept and where the other is
-- E7  a clean merge says the changes were merged
-- E8  an upload in flight, waiting or sending, gets no card here (root lists it, `core/transfers`)
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

--- Every `Text` on screen, as a set.
local function lines(world)
    local out = {}
    for _, t in ipairs(world:query({ with = { "Text" } })) do out[tostring(t:get("Text"))] = true end
    return out
end
local function mentions(world, path)
    for text in pairs(lines(world)) do
        if text:find(path, 1, true) then return text end
    end
end

local phase, clock = "spawn", 0
app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(p) phase, clock = p, 0 end
    if phase == "done" then return end

    if phase == "spawn" then
        commands:spawn({ ["core/library/replaced"] = { path = "maps/a.glb", by = "world", kept = 7, both = true },
            ChildOf = library, ["core/net/sync"] = false })
        commands:spawn({ ["core/library/replaced"] = { path = "m.lua", by = "me", both = true },
            ChildOf = library, ["core/net/sync"] = false })
        step("replaced")
    elseif phase == "replaced" then
        local seen = lines(world)
        local both = seen["maps/a.glb changed here and in the world. The world's newer copy is kept; yours is in .hello/held/7."]
        local merged = seen["m.lua changed here and in the world; the changes were merged."]
        if not (both and merged) and clock < 3 then return end
        T("E6_a_replacement_says_which_copy_is_kept", both == true, "")
        T("E7_a_clean_merge_says_so", merged == true, "")
        commands:spawn({ ["core/library/upload"] = { path = "maps/lab.glb", bytes = 10 * MB, total = 100, got = 50, state = "sending" },
            ChildOf = library, ["core/net/sync"] = false })
        commands:spawn({ ["core/library/upload"] = { path = "maps/slow.glb", bytes = 2 * MB, total = 20, got = 0, state = "waiting" },
            ChildOf = library, ["core/net/sync"] = false })
        step("uploads")
    elseif phase == "uploads" and clock > 11 then
        local said = mentions(world, "maps/lab.glb") or mentions(world, "maps/slow.glb")
        T("E8_an_upload_gets_no_card_here", said == nil, tostring(said))
        phase = "done"
        suite.finish("EDIT_NOTICE")
    end
end):in_set("zz/edit_notice_flow")
