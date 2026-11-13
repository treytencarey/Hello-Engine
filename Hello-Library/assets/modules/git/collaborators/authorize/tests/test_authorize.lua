-- test_authorize.lua: git/collaborators/authorize answers each of core's write requests from the
-- writer proof. The suite stands in for core's authority endpoint, spawning `core/asset/write`
-- requests with the author the connection proved; for core/net and core/player/attest, stating each
-- client's `core/net/connection` with its attestation; and for root, answering each `vault/git/proof` check. A check asked at root comes
-- from no world root started, so nothing else answers it.
--
-- A1  the carrier is marked the world's write authorizer
-- A2  bob's first write waits, and one check names his nonce, under his connection; a second write
--     while it is open asks nothing more
-- A3  proved allows both waiting writes and closes the check
-- A4  bob's next write is allowed at once, with no new check
-- A5  absent soon after carol's first ask leaves her write waiting and asks again a moment later,
--     and a push that lands meanwhile allows it
-- A6  absent on every check: frank's write waits, root is asked again on a growing back-off (not
--     on every answer), and at `proof_wait` (pinned to 6 s) his write is denied
-- A6b ...and his next write asks again
-- A10 gina on two connections, absent on both: her write is denied at `proof_wait` too, not left
--     to core's ceiling
-- A7  an anonymous author is denied, and so is a connection attested anonymous, with no check
-- A8  bob re-attests: his record goes, and his next write asks with the new nonce
-- A9  dave's connection goes while his check is open: the check goes with it, and his waiting write is
--     denied
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitAuthorizeSuite")
local T = suite.assert_test

local N1 = "11111111-1111-4111-8111-111111111111"
local N2 = "22222222-2222-4222-8222-222222222222"
local N3 = "33333333-3333-4333-8333-333333333333"
local N4 = "44444444-4444-4444-8444-444444444444"
local N5 = "55555555-5555-4555-8555-555555555555"
local N6 = "66666666-6666-4666-8666-666666666666"
local N7 = "77777777-7777-4777-8777-777777777777"
local WAIT = 6

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/player/attest"] = { state = "attested", user = "bob", nonce = N1 },
        ["core/net/connection"] = { client_id = 1 },
        ["zz/authorize/player"] = { name = "bob" },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/player/attest"] = { state = "attested", user = "carol", nonce = N2 },
        ["core/net/connection"] = { client_id = 2 },
        ["zz/authorize/player"] = { name = "carol" },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/player/attest"] = { state = "anonymous" },
        ["core/net/connection"] = { client_id = 3 },
        ["zz/authorize/player"] = { name = "erin" },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/player/attest"] = { state = "attested", user = "dave", nonce = N4 },
        ["core/net/connection"] = { client_id = 4 },
        ["zz/authorize/player"] = { name = "dave" },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/player/attest"] = { state = "attested", user = "frank", nonce = N5 },
        ["core/net/connection"] = { client_id = 5 },
        ["zz/authorize/player"] = { name = "frank" },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/player/attest"] = { state = "attested", user = "gina", nonce = N6 },
        ["core/net/connection"] = { client_id = 6 },
        ["zz/authorize/player"] = { name = "gina" },
        ["core/net/sync"] = false,
    })
    commands:spawn({
        ["core/player/attest"] = { state = "attested", user = "gina", nonce = N7 },
        ["core/net/connection"] = { client_id = 7 },
        ["zz/authorize/player"] = { name = "gina2" },
        ["core/net/sync"] = false,
    })
end)

-- The suite is root, so root's own vault/git judges each check as root's own request and refuses
-- it. The suite stands in for root's answer instead: that refusal is taken off before the
-- authorizer reads it.
app:add_systems(First, {
    Query[{ with = { "vault/git/proof/reply", "vault/git/proof", "Request" } }],
    Commands,
}, function(replies, commands)
    for _, r in ipairs(replies:iter()) do
        if r:get("vault/git/proof/reply").status == "refused" then
            commands:entity(r:id()):remove("vault/git/proof/reply")
        end
    end
end):in_set("zz/authorize_stand_in"):before("git/collaborators/authorize")

-- nonce -> how many checks named it. One is open at a time per nonce, so a check not seen open
-- before is a new ask: `added` on `vault/git/proof` fired twice per check here, as vault/git loads
-- at root. A re-ask replaces its check in one frame.
local asks, last_open = {}, {}

-- nonce -> the status root answers with, once; `always`: every check of that nonce
local answers, always = {}, {}

local function player(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/authorize/player", "core/player/attest" },
        optional = { "git/collaborators/authorize/proof" },
    })) do
        if e:get("zz/authorize/player").name == name then return e end
    end
    return nil
end

local function checks(world, nonce)
    local out = {}
    for _, e in ipairs(world:query({ with = { "vault/git/proof", "vault/git", "Request" }, optional = { "ChildOf" } })) do
        if e:get("vault/git").nonce == nonce then out[#out + 1] = e end
    end
    return out
end

local function reply(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/authorize/write" },
        optional = { "core/asset/write/reply" },
    })) do
        if e:get("zz/authorize/write").name == name then
            return e:get("core/asset/write/reply") or false
        end
    end
    return nil
end

local function write(commands, name, author)
    commands:spawn({
        ["core/asset/write"] = { op = "write", path = name .. ".lua", author = author, client = 1 },
        ["zz/authorize/write"] = { name = name },
        ["core/net/sync"] = false,
    })
end

local function total_asks()
    local n = 0
    for _, count in pairs(asks) do n = n + count end
    return n
end

local phase, clock = "start", 0
local seen = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    if phase == "done" then return end
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function finish()
        phase = "done"
        suite.finish("GIT_AUTHORIZE")
    end

    for nonce, status in pairs(answers) do
        local open = checks(world, nonce)[1]
        if open ~= nil then
            commands:entity(open:id()):insert({ ["vault/git/proof/reply"] = { status = status, message = "zz" } })
            answers[nonce] = nil
        end
    end
    for nonce, status in pairs(always) do
        for _, open in ipairs(checks(world, nonce)) do
            if not open:has("vault/git/proof/reply") then
                commands:entity(open:id()):insert({ ["vault/git/proof/reply"] = { status = status, message = "zz" } })
            end
        end
    end

    for _, nonce in ipairs({ N1, N2, N3, N4, N5, N6, N7 }) do
        local open = checks(world, nonce)[1]
        if open ~= nil and open:id() ~= last_open[nonce] then
            asks[nonce], last_open[nonce] = (asks[nonce] or 0) + 1, open:id()
        end
    end

    local bob, carol, dave = player(world, "bob"), player(world, "carol"), player(world, "dave")

    if phase == "start" and clock > 0.2 then
        commands:spawn({ ["git/collaborators/authorize"] = { proof_wait = WAIT }, ["zz/authorize/carrier"] = {}, ["core/net/sync"] = false })
        step("a1")

    elseif phase == "a1" then
        local marked = #world:query({ with = { "zz/authorize/carrier", "core/asset/authorizer" } }) == 1
        if not marked and clock < 5 then return end
        T("A1_the_carrier_is_the_worlds_write_authorizer", marked, "no core/asset/authorizer on the carrier")
        write(commands, "b1", { role = "player", user = "bob" })
        step("a2")

    elseif phase == "a2" and asks[N1] and not seen.b1b then
        seen.b1b = true
        write(commands, "b1b", { role = "player", user = "bob" })
        clock = 0

    elseif phase == "a2" and ((seen.b1b and clock > 0.5) or clock > 5) then
        local open = checks(world, N1)[1]
        local proof = bob:get("git/collaborators/authorize/proof")
        T("A2_the_first_write_waits_and_one_check_names_the_nonce",
            reply(world, "b1") == false and reply(world, "b1b") == false and asks[N1] == 1 and open ~= nil and open:get("ChildOf") == bob:id()
                and proof ~= nil and proof.state == "checking" and proof.user == "bob",
            string.format("reply=%s asks=%s under=%s proof=%s", tostring(reply(world, "b1")), tostring(asks[N1]),
                tostring(open and open:get("ChildOf")), tostring(proof and proof.state)))
        answers[N1] = "proved"
        step("a3")

    elseif phase == "a3" and ((reply(world, "b1") and reply(world, "b1b")) or clock > 5) then
        local r, rb = reply(world, "b1"), reply(world, "b1b")
        T("A3_proved_allows_the_waiting_writes_and_closes_the_check",
            r and r.verdict == "allow" and rb and rb.verdict == "allow" and #checks(world, N1) == 0
                and (bob:get("git/collaborators/authorize/proof") or {}).state == "writer",
            string.format("verdict=%s open=%d", tostring(r and r.verdict), #checks(world, N1)))
        write(commands, "b2", { role = "player", user = "bob" })
        step("a4")

    elseif phase == "a4" and (reply(world, "b2") or clock > 5) then
        local r = reply(world, "b2")
        T("A4_a_writer_is_allowed_at_once_with_no_new_check", r and r.verdict == "allow" and asks[N1] == 1,
            string.format("verdict=%s asks=%s", tostring(r and r.verdict), tostring(asks[N1])))
        write(commands, "c1", { role = "player", user = "carol" })
        step("a5")

    elseif phase == "a5" then
        if asks[N2] == 1 and not seen.c1 then
            seen.c1 = true
            answers[N2] = "absent"
        elseif asks[N2] == 2 and not seen.c1_again then
            seen.c1_again = true
            seen.c1_waiting = reply(world, "c1") == false
            answers[N2] = "proved"
        end
        if not reply(world, "c1") and clock < 5 then return end
        local r = reply(world, "c1")
        T("A5_an_early_absent_asks_again_and_a_late_push_allows",
            seen.c1_waiting == true and r and r.verdict == "allow" and asks[N2] == 2,
            string.format("waited=%s verdict=%s asks=%s", tostring(seen.c1_waiting), tostring(r and r.verdict),
                tostring(asks[N2])))
        write(commands, "f1", { role = "player", user = "frank" })
        step("a6")

    elseif phase == "a6" then
        if asks[N5] == 1 and not seen.f1 then
            seen.f1 = true
            clock = 0
            always[N5] = "absent"
        end
        if not reply(world, "f1") and clock < WAIT + 4 then return end
        local r = reply(world, "f1")
        local proof = player(world, "frank"):get("git/collaborators/authorize/proof")
        T("A6_absent_waits_on_a_back_off_and_is_denied_at_the_wait",
            r and r.verdict == "deny" and proof ~= nil and proof.state == "absent"
                and asks[N5] >= 2 and asks[N5] <= 5 and clock >= WAIT - 1,
            string.format("verdict=%s proof=%s asks=%s after %.1f s", tostring(r and r.verdict),
                tostring(proof and proof.state), tostring(asks[N5]), clock))
        seen.f_asks = asks[N5]
        write(commands, "f2", { role = "player", user = "frank" })
        step("a6b")

    elseif phase == "a6b" and (asks[N5] == seen.f_asks + 1 or clock > 5) then
        T("A6b_absent_is_asked_again_on_the_next_write", asks[N5] == seen.f_asks + 1 and reply(world, "f2") == false,
            string.format("asks=%s reply=%s", tostring(asks[N5]), tostring(reply(world, "f2"))))
        always[N5] = nil
        always[N6], always[N7] = "absent", "absent"
        write(commands, "g1", { role = "player", user = "gina" })
        step("a10")

    elseif phase == "a10" then
        if not reply(world, "g1") and clock < WAIT + 4 then return end
        local r = reply(world, "g1")
        T("A10_two_connections_absent_are_denied_at_the_wait_too",
            r and r.verdict == "deny" and asks[N6] and asks[N7] and clock >= WAIT - 1,
            string.format("verdict=%s asks=%s/%s after %.1f s", tostring(r and r.verdict), tostring(asks[N6]),
                tostring(asks[N7]), clock))
        always[N6], always[N7] = nil, nil
        seen.asks = total_asks()
        write(commands, "x1", nil)
        write(commands, "e1", { role = "player", user = "erin" })
        step("a7")

    elseif phase == "a7" and ((reply(world, "x1") and reply(world, "e1")) or clock > 5) then
        local x, e = reply(world, "x1"), reply(world, "e1")
        T("A7_anonymous_is_denied_with_no_check",
            x and x.verdict == "deny" and e and e.verdict == "deny" and total_asks() == seen.asks,
            string.format("anonymous=%s signed out=%s asks %d -> %d", tostring(x and x.verdict),
                tostring(e and e.verdict), seen.asks, total_asks()))
        commands:entity(bob:id()):insert({ ["core/player/attest"] = { state = "attested", user = "bob", nonce = N3 } })
        step("a8 cleared")

    elseif phase == "a8 cleared" then
        local gone = not bob:has("git/collaborators/authorize/proof")
        if not gone and clock < 5 then return end
        seen.cleared = gone
        write(commands, "b3", { role = "player", user = "bob" })
        step("a8")

    elseif phase == "a8" and (asks[N3] or clock > 5) then
        T("A8_a_new_attestation_clears_the_record_and_asks_again",
            seen.cleared and asks[N3] == 1 and asks[N1] == 1 and reply(world, "b3") == false,
            string.format("cleared=%s asks new=%s old=%s reply=%s", tostring(seen.cleared), tostring(asks[N3]),
                tostring(asks[N1]), tostring(reply(world, "b3"))))
        write(commands, "d1", { role = "player", user = "dave" })
        step("a9 asked")

    elseif phase == "a9 asked" and (asks[N4] or clock > 5) then
        commands:entity(dave:id()):despawn()
        step("a9")

    elseif phase == "a9" and (reply(world, "d1") or clock > 5) then
        local r = reply(world, "d1")
        T("A9_the_record_and_its_check_go_with_the_connection",
            dave == nil and #checks(world, N4) == 0 and r and r.verdict == "deny",
            string.format("player=%s open=%d verdict=%s", tostring(dave ~= nil), #checks(world, N4),
                tostring(r and r.verdict)))
        finish()
    end

    if phase ~= "done" and clock > 15 then
        T("A0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 15 s")
        finish()
    end
end):in_set("zz/authorize_suite")
