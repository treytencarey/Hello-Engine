-- transfers: files in transit, in a screen corner.
--
-- X1  with no transfer there is no icon
-- X2  a download or upload of more than one chunk brings the icon, counting each way; one chunk does not count
-- X3  not hovered, the list shows nothing
-- X4  hovered, the list has a line per transfer, both directions, "x / y MB", a waiting upload saying so, and bars
-- X5  a row that moves while hovered moves its line
-- X6  no longer hovered, the list hides
-- X7  the last row gone, the icon goes
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("TransfersSuite")
local T = suite.assert_test

local MB = 1024 * 1024
local library

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ transfers = {} })
    library = commands:spawn({ ["zz/library"] = {} }):id()
end)

local function icon(world)
    return world:query({ with = { "transfers/icon" }, optional = { "Children", "Interaction" } })[1]
end
local function list(world)
    return world:query({ with = { "transfers/list", "Node" } })[1]
end
--- The icon's count.
local function counted(world)
    local i = icon(world)
    for _, t in ipairs(world:query({ with = { "Text", "ChildOf" } })) do
        if i and t:get("ChildOf") == i:id() then return tostring(t:get("Text")) end
    end
end
--- The list's lines, text → its bar's width.
local function shown(world)
    local l = list(world)
    if not l then return {} end
    local parent = {}
    for _, e in ipairs(world:query({ with = { "ChildOf" } })) do parent[e:id()] = e:get("ChildOf") end
    local out, text_of = {}, {}
    for _, t in ipairs(world:query({ with = { "Text", "ChildOf" } })) do
        if parent[t:id()] and parent[parent[t:id()]] == l:id() then text_of[parent[t:id()]] = tostring(t:get("Text")) end
    end
    for _, n in ipairs(world:query({ with = { "Node", "ChildOf" }, without = { "Text" } })) do
        local track = parent[n:id()]
        local line = track and parent[track]
        if line and parent[line] == l:id() and text_of[line] then
            local w = n:get("Node").width
            out[text_of[line]] = type(w) == "table" and w.Percent or w
        end
    end
    return out
end
local function display(world)
    local l = list(world)
    return l and tostring(l:get("Node").display)
end
local function count(m) local n = 0 for _ in pairs(m) do n = n + 1 end return n end
local function row(world, name, path)
    for _, e in ipairs(world:query({ with = { name } })) do
        if e:get(name).path == path then return e end
    end
end

local DOWN = "down  maps/big.glb  1.0 / 4.0 MB"
local UP = "up  maps/lab.glb  5.0 / 10.0 MB"
local WAIT = "up  maps/slow.glb  0.0 / 2.0 MB, waiting for the world"

local phase, clock = "start", 0
app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(p) phase, clock = p, 0 end
    if phase == "done" then return end

    if phase == "start" and clock > 1 then
        T("X1_no_transfer_no_icon", icon(world) == nil, "an icon")
        commands:spawn({ ["core/library/download"] = { path = "maps/big.glb", total = 4 * MB, got = 1 * MB },
            ChildOf = library, ["core/net/sync"] = false })
        commands:spawn({ ["core/library/upload"] = { path = "maps/lab.glb", bytes = 10 * MB, total = 100, got = 50, state = "sending" },
            ChildOf = library, ["core/net/sync"] = false })
        commands:spawn({ ["core/library/upload"] = { path = "maps/slow.glb", bytes = 2 * MB, total = 20, got = 0, state = "waiting" },
            ChildOf = library, ["core/net/sync"] = false })
        commands:spawn({ ["core/library/upload"] = { path = "small.lua", bytes = 100, total = 1, got = 0, state = "waiting" },
            ChildOf = library, ["core/net/sync"] = false })
        step("icon")
    elseif phase == "icon" then
        local c = counted(world)
        if c == nil and clock < 3 then return end
        T("X2_the_icon_counts_each_way", c == "1 down  2 up", tostring(c))
        T("X3_not_hovered_the_list_shows_nothing", display(world) == "None" and count(shown(world)) == 0,
            string.format("display=%s lines=%d", tostring(display(world)), count(shown(world))))
        commands:entity(icon(world):id()):insert({ Interaction = "Hovered" })
        step("hover")
    elseif phase == "hover" then
        local lines = shown(world)
        if count(lines) < 3 and clock < 3 then return end
        local names = {}
        for text, w in pairs(lines) do names[#names + 1] = text .. " [" .. tostring(w) .. "]" end
        T("X4_hovered_a_line_per_transfer_both_ways",
            display(world) == "Flex" and count(lines) == 3 and lines[DOWN] == 25 and lines[UP] == 50 and lines[WAIT] == 0,
            string.format("display=%s %s", tostring(display(world)), table.concat(names, " | ")))
        row(world, "core/library/download", "maps/big.glb"):set({
            ["core/library/download"] = { path = "maps/big.glb", total = 4 * MB, got = 3 * MB } })
        step("moved")
    elseif phase == "moved" then
        local lines = shown(world)
        local moved = "down  maps/big.glb  3.0 / 4.0 MB"
        if lines[moved] == nil and clock < 3 then return end
        T("X5_a_row_that_moves_moves_its_line", lines[moved] == 75 and lines[DOWN] == nil, tostring(lines[moved]))
        commands:entity(icon(world):id()):insert({ Interaction = "None" })
        step("unhover")
    elseif phase == "unhover" then
        if (display(world) ~= "None" or count(shown(world)) > 0) and clock < 3 then return end
        T("X6_no_longer_hovered_the_list_hides", display(world) == "None" and count(shown(world)) == 0,
            string.format("display=%s lines=%d", tostring(display(world)), count(shown(world))))
        for _, name in ipairs({ "core/library/download", "core/library/upload" }) do
            for _, e in ipairs(world:query({ with = { name } })) do commands:entity(e:id()):despawn() end
        end
        step("gone")
    elseif phase == "gone" then
        if icon(world) ~= nil and clock < 3 then return end
        T("X7_the_last_row_gone_the_icon_goes", icon(world) == nil, "icon still there")
        phase = "done"
        suite.finish("TRANSFERS")
    end
end):in_set("zz/transfers_flow")
