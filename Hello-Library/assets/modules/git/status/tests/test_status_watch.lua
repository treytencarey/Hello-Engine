-- test_status_watch.lua: which changes git/status states as the player's edits. The suite stands in
-- for root and answers each status request with a scripted scan. A request asked at root comes
-- from no world root started, so nothing else answers it.
--
-- W1  the first request is asked as the carrier arrives, as its child
-- W2  each file a scan reports is an edit, a child of the carrier; a deletion is `deleted`
-- W3  a second save of a file still dirty moves its `mtime`, so its `seq` moves
-- W4  a scan with nothing new moves no `seq`
-- W5  a scan that failed changes nothing
-- W6  a reload of the mod keeps each edit, once, with its `seq`
-- W7  a revert (gone from the list, HEAD put) moves its `seq` once more; a new file gone is `deleted`
-- W8  ...and the next scan drops it
-- W9  a path leaving because HEAD moved is dropped at once
-- W10 a request nobody answers is closed after 10 s, and asked again
-- W11 one request open at a time
-- W12 git/status taken off an entity that stays: its edits and its request go
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitStatusWatchSuite")
local T = suite.assert_test

local SOURCE = "assets/modules/git/status/init.lua"
local H1 = "1111111111111111111111111111111111111111"
local H2 = "2222222222222222222222222222222222222222"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
end)

local asks, max_open, last_open = 0, 0, nil

local function carrier(world)
    return world:query({ with = { "zz/watch/carrier" }, optional = { "git/status", "Children" } })[1]
end

local function open_requests(world)
    return world:query({
        with = { "vault/git/status", "Request", "ChildOf" },
        without = { "vault/git/status/reply" },
    })
end

--- path -> { seq, deleted, parent, count }
local function edits(world)
    local out = {}
    for _, e in ipairs(world:query({ with = { "core/library/edit" }, optional = { "ChildOf" } })) do
        local d = e:get("core/library/edit")
        local had = out[d.path]
        out[d.path] = { seq = d.seq, deleted = d.deleted, parent = e:get("ChildOf"), count = (had and had.count or 0) + 1 }
    end
    return out
end

local phase, clock = "start", 0
local queued, asks_at_answer = nil, 0
local seen = {}

local function scan(head, entries) queued = { status = "ok", head = head, entries = entries } end

app:add_systems(Update, { World, Commands }, function(world, commands)
    if phase == "done" then return end
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function finish()
        phase = "done"
        suite.finish("GIT_STATUS_WATCH")
    end

    local open = open_requests(world)
    if #open > max_open then max_open = #open end
    -- One open at a time (W11), so a request not seen open before is a new ask.
    if open[1] ~= nil and open[1]:id() ~= last_open then
        asks, last_open = asks + 1, open[1]:id()
    end
    if queued ~= nil and open[1] ~= nil then
        commands:entity(open[1]:id()):insert({ ["vault/git/status/reply"] = queued })
        queued, asks_at_answer = nil, asks
    end
    -- The answer was read and the next request asked.
    local next_asked = queued == nil and asks > asks_at_answer
    local c = carrier(world)
    local d = edits(world)
    local A, B, C = d["zz/a.lua"], d["zz/b.lua"], d["zz/c.lua"]

    if phase == "start" and clock > 0.3 then
        commands:spawn({ ["git/status"] = {}, ["zz/watch/carrier"] = {}, ["core/net/sync"] = false })
        step("w1")

    elseif phase == "w1" and (asks > 0 or clock > 5) then
        T("W1_the_first_request_is_asked_as_the_carrier_arrives",
            asks == 1 and open[1] ~= nil and c ~= nil and open[1]:get("ChildOf") == c:id(),
            string.format("%d asked, open under %s", asks, tostring(open[1] and open[1]:get("ChildOf"))))
        scan(H1, {
            { path = "assets/zz/a.lua", op = "write", mtime = 1000 },
            { path = "assets/zz/b.lua", op = "create", mtime = 1000 },
            { path = "assets/zz/c.lua", op = "delete" },
        })
        step("w2")

    elseif phase == "w2" and ((A and B and C) or clock > 5) then
        T("W2_each_reported_file_is_an_edit_under_the_carrier",
            A ~= nil and B ~= nil and C ~= nil and A.seq == 1 and A.deleted == false and B.deleted == false
                and C.deleted == true and A.parent == c:id() and C.parent == c:id(),
            string.format("a=%s b=%s c=%s", tostring(A and A.seq), tostring(B and B.seq), tostring(C and C.deleted)))
        seen.b = B and B.seq
        scan(H1, {
            { path = "assets/zz/a.lua", op = "write", mtime = 2000 },
            { path = "assets/zz/b.lua", op = "create", mtime = 1000 },
            { path = "assets/zz/c.lua", op = "delete" },
        })
        step("w3")

    elseif phase == "w3" and ((A and A.seq == 2) or clock > 5) then
        T("W3_a_second_save_moves_the_seq", A ~= nil and A.seq == 2 and B ~= nil and B.seq == seen.b,
            string.format("a seq %s, b seq %s -> %s", tostring(A and A.seq), tostring(seen.b), tostring(B and B.seq)))
        scan(H1, {
            { path = "assets/zz/a.lua", op = "write", mtime = 2000 },
            { path = "assets/zz/b.lua", op = "create", mtime = 1000 },
            { path = "assets/zz/c.lua", op = "delete" },
        })
        step("w4")

    elseif phase == "w4" and (next_asked or clock > 5) then
        T("W4_a_scan_with_nothing_new_moves_no_seq", A ~= nil and A.seq == 2 and B.seq == 1 and C.seq == 1,
            string.format("a=%s b=%s c=%s", tostring(A and A.seq), tostring(B and B.seq), tostring(C and C.seq)))
        queued = { status = "failed", message = "zz: no git here" }
        step("w5")

    elseif phase == "w5" and (next_asked or clock > 5) then
        T("W5_a_failed_scan_changes_nothing", A ~= nil and B ~= nil and C ~= nil and A.seq == 2 and B.seq == 1,
            string.format("a=%s b=%s c=%s", tostring(A and A.seq), tostring(B and B.seq), tostring(C and C.seq)))
        write_file_bytes(SOURCE, read_file_bytes(SOURCE))
        step("w6 reload")

    elseif phase == "w6 reload" and clock > 1.5 then
        scan(H1, {
            { path = "assets/zz/a.lua", op = "write", mtime = 2000 },
            { path = "assets/zz/b.lua", op = "create", mtime = 1000 },
            { path = "assets/zz/c.lua", op = "delete" },
        })
        step("w6")

    elseif phase == "w6" and (next_asked or clock > 5) then
        T("W6_a_reload_keeps_each_edit_once",
            A ~= nil and B ~= nil and C ~= nil and A.count == 1 and B.count == 1 and C.count == 1
                and A.seq == 2 and B.seq == 1 and C.seq == 1,
            string.format("a=%s x%s b=%s x%s c=%s x%s", tostring(A and A.seq), tostring(A and A.count),
                tostring(B and B.seq), tostring(B and B.count), tostring(C and C.seq), tostring(C and C.count)))
        -- a and b back to HEAD; c still deleted
        scan(H1, { { path = "assets/zz/c.lua", op = "delete" } })
        step("w7")

    elseif phase == "w7" and ((A and B and A.seq == 3 and B.seq == 2) or clock > 5) then
        T("W7_a_revert_moves_the_seq_once_more",
            A ~= nil and B ~= nil and A.seq == 3 and A.deleted == false and B.seq == 2 and B.deleted == true,
            string.format("a=%s deleted=%s, b=%s deleted=%s", tostring(A and A.seq), tostring(A and A.deleted),
                tostring(B and B.seq), tostring(B and B.deleted)))
        scan(H1, { { path = "assets/zz/c.lua", op = "delete" } })
        step("w8")

    elseif phase == "w8" and (next_asked or clock > 5) then
        T("W8_and_the_next_scan_drops_it", A == nil and B == nil and C ~= nil and C.seq == 1,
            string.format("a=%s b=%s c=%s", tostring(A ~= nil), tostring(B ~= nil), tostring(C and C.seq)))
        scan(H2, {})
        step("w9")

    elseif phase == "w9" and (next_asked or clock > 5) then
        T("W9_a_path_leaving_because_head_moved_is_dropped_at_once", C == nil,
            "c is still stated, seq " .. tostring(C and C.seq))
        seen.asks, seen.open = asks, open[1] and open[1]:id()
        step("w10")

    elseif phase == "w10" then
        if seen.open == nil then seen.open = open[1] and open[1]:id() end
        local closed = seen.open ~= nil and (open[1] == nil or open[1]:id() ~= seen.open)
        if not (closed and open[1] ~= nil) and clock < 16 then return end
        T("W10_an_unanswered_request_is_closed_after_10_s_and_asked_again",
            closed and open[1] ~= nil and clock > 9 and asks == seen.asks + 1,
            string.format("closed=%s after %.1f s, %d asked since", tostring(closed), clock, asks - seen.asks))
        scan(H2, { { path = "assets/zz/a.lua", op = "write", mtime = 3000 } })
        step("w12 setup")

    elseif phase == "w12 setup" and (A or clock > 5) then
        T("W11_one_request_open_at_a_time", max_open == 1, "at most " .. tostring(max_open) .. " open")
        seen.asks = asks
        commands:entity(c:id()):remove("git/status")
        step("w12")

    elseif phase == "w12" and ((A == nil and open[1] == nil) or clock > 5) then
        if clock < 2.5 then return end
        T("W12_taking_git_status_off_takes_its_edits_and_request",
            A == nil and open[1] == nil and asks == seen.asks and c ~= nil and not c:has("git/status"),
            string.format("edit=%s open=%s asked=%d", tostring(A ~= nil), tostring(open[1] ~= nil), asks - seen.asks))
        finish()
    end

    if phase ~= "done" and phase ~= "w10" and clock > 20 then
        T("W0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 20 s")
        finish()
    end
end):in_set("zz/watch_suite")
