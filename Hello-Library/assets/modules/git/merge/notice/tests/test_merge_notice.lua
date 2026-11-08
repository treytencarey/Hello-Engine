-- git/merge/notice: a notification that says a title and a line.
--
-- N1  a notice shows its title and its line, each styled by role
-- N2  a notice given no title says EDIT
-- N3  a changed notice is drawn again, with its new words and no old line left
-- N4  a reload of the mod draws every notice again, once
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("MergeNoticeSuite")
local T = suite.assert_test

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/note"] = { name = "conflict" },
        ["git/merge/notice"] = { title = "CONFLICT", text = "Someone else changed a.txt too." },
        notification = {},
    })
    commands:spawn({
        ["zz/note"] = { name = "plain" },
        ["git/merge/notice"] = { text = "Merged." },
        notification = {},
    })
end)

local reloads = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("git/merge/notice/init.lua", 1, true) then
            reloads = reloads + 1
        end
    end
end):in_set("zz/merge_notice_watch")

local function note(world, name)
    for _, e in ipairs(world:query({ with = { "zz/note" } })) do
        if e:get("zz/note").name == name then
            return e
        end
    end
end

-- The lines under a notice, in the order they were spawned: { text, role } each.
local function lines(world, name)
    local e = note(world, name)
    local out = {}
    for _, row in ipairs(world:query({
        with = { "git/merge/notice/row", "ChildOf", "Text" },
        optional = { "ui/style" },
    })) do
        if e and row:get("ChildOf") == e:id() then
            local style = row:get("ui/style") or {}
            out[#out + 1] = { text = row:get("Text"), role = style.text }
        end
    end
    return out
end

local function said(list)
    local parts = {}
    for _, l in ipairs(list) do
        parts[#parts + 1] = string.format("%s (%s)", tostring(l.text), tostring(l.role))
    end
    return #list .. " lines: " .. table.concat(parts, " | ")
end

local PATH = "assets/modules/git/merge/notice/init.lua"
local phase, clock = "shown", 0

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "shown" then
        local conflict, plain = lines(world, "conflict"), lines(world, "plain")
        if (#conflict < 2 or #plain < 2) and clock < 5 then return end
        T("N1_a_notice_shows_its_title_and_line_by_role",
            #conflict == 2 and conflict[1].text == "CONFLICT" and conflict[1].role == "accent"
                and conflict[2].text == "Someone else changed a.txt too." and conflict[2].role == "text",
            said(conflict))
        T("N2_a_notice_with_no_title_says_EDIT",
            #plain == 2 and plain[1].text == "EDIT" and plain[2].text == "Merged.", said(plain))
        commands:entity(note(world, "conflict"):id()):insert({
            ["git/merge/notice"] = { title = "RESOLVED", text = "Sent." },
        })
        step("changed")
    elseif phase == "changed" then
        local conflict = lines(world, "conflict")
        local redrawn = conflict[1] and conflict[1].text == "RESOLVED"
        if not redrawn and clock < 5 then return end
        if clock < 0.5 then return end
        T("N3_a_changed_notice_is_drawn_again",
            #conflict == 2 and redrawn and conflict[2].text == "Sent.", said(conflict))
        write_file_bytes(PATH, read_file_bytes(PATH))
        step("reloading")
    elseif phase == "reloading" then
        if reloads == 0 and clock < 10 then return end
        local conflict, plain = lines(world, "conflict"), lines(world, "plain")
        if (#conflict < 2 or #plain < 2) and clock < 10 then return end
        -- A second drawing would land within a few frames of the first.
        if clock < 1.5 then return end
        T("N4_a_reload_draws_every_notice_once",
            reloads > 0 and #conflict == 2 and conflict[1].text == "RESOLVED" and #plain == 2 and plain[1].text == "EDIT",
            string.format("reloads %d; conflict %s; plain %s; notices %s %s; rows %d", reloads, said(conflict), said(plain),
                tostring(note(world, "conflict") ~= nil), tostring(note(world, "plain") ~= nil),
                #world:query({ with = { "git/merge/notice/row" } })))
        suite.finish("MERGE_NOTICE")
        step("done")
    end
end):in_set("zz/merge_notice_suite")
