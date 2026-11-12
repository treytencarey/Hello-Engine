-- test_status_watch.lua: which changes git/world/served/status states as the player's edits. The suite stands in
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
-- W12 git/world/served/status taken off an entity that stays: its edits and its request go
-- W13 signed out (root's identity without `site_user_id`) nothing is asked; signing in asks again
-- W14 in both-mode (root's `core/process`) nothing is asked; out of it, it asks again
-- W15 an edit under the carrier that core marks `core/library/edit/refused` is told once, in a
--     `git/merge/notice` titled REFUSED; a marked edit under no carrier is not
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitStatusWatchSuite")
local T = suite.assert_test

local SOURCE = "assets/modules/git/world/served/status/init.lua"
local H1 = "1111111111111111111111111111111111111111"
local H2 = "2222222222222222222222222222222222222222"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    -- Root's identity, signed in: this suite is root.
    commands:spawn({
        ["core/player/identity"] = { site_user_id = "zz-user" },
        ["zz/watch/identity"] = {},
        ["core/net/sync"] = false,
    })
end)

local asks, max_open, last_open = 0, 0, nil

local function carrier(world)
    return world:query({ with = { "zz/watch/carrier" }, optional = { "git/world/served/status", "Children" } })[1]
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

-- Every notice spawned, as title, text and its notification's timeout.
local notices = {}
app:add_systems(First, {
    Query[{ added = { "git/merge/notice" }, optional = { "notification" } }],
}, function(rows)
    for _, row in ipairs(rows:iter()) do
        local n = row:get("git/merge/notice")
        notices[#notices + 1] = { title = n.title, text = n.text,
            timeout = row:has("notification") and row:get("notification").timeout or nil }
    end
end):in_set("zz/watch_notices")

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
        commands:spawn({ ["git/world/served/status"] = {}, ["zz/watch/carrier"] = {}, ["core/net/sync"] = false })
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
        commands:entity(c:id()):remove("git/world/served/status")
        step("w12")

    elseif phase == "w12" and ((A == nil and open[1] == nil) or clock > 5) then
        if clock < 2.5 then return end
        T("W12_taking_git_status_off_takes_its_edits_and_request",
            A == nil and open[1] == nil and asks == seen.asks and c ~= nil and not c:has("git/world/served/status"),
            string.format("edit=%s open=%s asked=%d", tostring(A ~= nil), tostring(open[1] ~= nil), asks - seen.asks))
        commands:entity(c:id()):insert({ ["git/world/served/status"] = {} })
        scan(H2, {})
        step("w13 answer")

    elseif phase == "w13 answer" and queued == nil and open[1] == nil then
        local me = world:query({ with = { "core/player/identity", "zz/watch/identity" } })[1]
        commands:entity(me:id()):insert({ ["core/player/identity"] = {} })
        seen.asks = asks
        step("w13 out")

    elseif phase == "w13 out" and clock > 4 then
        seen.out = asks - seen.asks
        local me = world:query({ with = { "core/player/identity", "zz/watch/identity" } })[1]
        commands:entity(me:id()):insert({ ["core/player/identity"] = { site_user_id = "zz-user" } })
        step("w13 in")

    elseif phase == "w13 in" and (asks > seen.asks or clock > 5) then
        T("W13_signed_out_asks_nothing_and_signing_in_asks_again", seen.out == 0 and asks == seen.asks + 1,
            string.format("%d asked while signed out, %d after signing in", seen.out, asks - seen.asks))
        scan(H2, {})
        step("w14 answer")

    elseif phase == "w14 answer" and queued == nil and open[1] == nil then
        commands:spawn({ ["core/process"] = { mode = "both" }, ["zz/watch/process"] = {}, ["core/net/sync"] = false })
        seen.asks = asks
        step("w14 out")

    elseif phase == "w14 out" and clock > 4 then
        seen.out = asks - seen.asks
        commands:entity(world:query({ with = { "zz/watch/process" } })[1]:id()):despawn()
        step("w14 in")

    elseif phase == "w14 in" and (asks > seen.asks or clock > 5) then
        T("W14_in_both_mode_asks_nothing_and_out_of_it_asks_again", seen.out == 0 and asks == seen.asks + 1,
            string.format("%d asked in both-mode, %d after", seen.out, asks - seen.asks))
        scan(H2, { { path = "assets/zz/a.lua", op = "write", mtime = 4000 } })
        step("w15 edit")

    elseif phase == "w15 edit" and (A or clock > 5) then
        -- Core marks an edit the world refused. One with no status carrier above it is not this mod's.
        for _, e in ipairs(world:query({ with = { "core/library/edit", "ChildOf" } })) do
            if e:get("core/library/edit").path == "zz/a.lua" then
                commands:entity(e:id()):insert({ ["core/library/edit/refused"] = {} })
            end
        end
        commands:spawn({
            ["core/library/edit"] = { path = "zz/loose.lua", seq = 1 },
            ["core/library/edit/refused"] = {},
            ["core/net/sync"] = false,
        })
        notices = {}
        step("w15")

    elseif phase == "w15" and clock > 1.5 then
        local n = notices[1] or {}
        T("W15_a_refused_edit_under_the_carrier_is_told_once",
            #notices == 1 and n.title == "REFUSED"
                and n.text == "This world refused your edit of zz/a.lua. It stays in your copy only."
                and n.timeout == 20,
            string.format("%d notice(s), the first %s: '%s', timeout %s", #notices, tostring(n.title),
                tostring(n.text), tostring(n.timeout)))
        finish()
    end

    if phase ~= "done" and phase ~= "w10" and clock > 20 then
        T("W0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 20 s")
        finish()
    end
end):in_set("zz/watch_suite")
