-- --host
-- git/world/served on a client: its carrier carries its sub-mods git/world/served/status and
-- git/world/served/merge only while this world's own content library is the player's checkout
-- (`edits`, which core sets from the home fact). No home fact is published here, so the two
-- components are the fact under test, not what they do.
--
-- S1  the checkout was already this world's when the carrier arrived: the first run catches up
-- S2  the checkout moving away takes both off
-- S3  ...and coming back puts them back
-- S4  another scope's library being edited is not this world's checkout
-- S5  a reload of the mod keeps both on, added once
-- S6  git/world/served taken off an entity that stays takes both with it
-- S7  turning them on asks the player's root for the writer proof once, under the carrier, naming
--     no nonce
-- S8  ...and the answered request is closed
-- S9  a reload of the mod asks at most once: the sign-in system's first run sees root's identity as
--     changed, and the sub-mods are not added again
-- S10 signed out (root's identity without `site_user_id`), turning them on asks for no proof
-- S12 signing in while they are on asks for the proof once
-- S13 signing in while root's join record is still bound to the anonymous player asks for no proof:
--     root would push the ref the anonymous ticket names
-- S14 ...and root's join record bound to the player afterwards (the new ticket) asks for it once
-- S11 in both-mode (root's `core/process`), turning them on asks for no proof
-- S15 signed in, turning them on shows no notice
-- S16 signed out, turning them on says once that edits stay local, in a `git/merge/notice`
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitWorldServedSuite")
local T = suite.assert_test

local SCOPE = "github:zzserved/proj:main"
local OTHER = "github:zzserved/proj:other"
local SOURCE = "assets/modules/git/world/served/client/init.lua"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
    commands:spawn({
        ["core/world/status"] = { scope_key = SCOPE, mode = "client", status = "ready" },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    -- Root's identity, signed in: this suite is root.
    commands:spawn({
        ["core/player/identity"] = { site_user_id = "zz-user" },
        ["zz/served/identity"] = {},
        ["core/net/sync"] = false,
    })
    -- Root's join record for this world, its ticket bound to the signed-in player.
    commands:spawn({
        ["core/world/join"] = { endpoint = "127.0.0.1:15990", scope = SCOPE, ticket = "zz-join-1", requester = "zz-user" },
        ["zz/served/join"] = {},
        ["core/net/sync"] = false,
    })
    -- This world's own content library, already the player's checkout before the mod exists.
    commands:spawn({
        ["core/library"] = { ref = SCOPE, root = "test_fixtures/zz_served_none", order = 5, edits = true },
        ["zz/served/own"] = {},
        ["core/net/sync"] = false,
    })
end)

local STAY_LOCAL = "This world uses your checkout, but you are not signed in — edits stay local until you connect your account"

local added = 0
local notices, notice_text, notice_timeout = 0, nil, nil
app:add_systems(First, {
    Query[{ added = { "git/world/served/status" } }],
    Query[{ added = { "git/world/served/merge" } }],
    Query[{ added = { "git/merge/notice" }, optional = { "notification" } }],
}, function(status_rows, merge_rows, notice_rows)
    added = added + #status_rows:iter() + #merge_rows:iter()
    for _, row in ipairs(notice_rows:iter()) do
        notices = notices + 1
        notice_text = row:get("git/merge/notice").text
        notice_timeout = row:has("notification") and row:get("notification").timeout or nil
    end
end):in_set("zz/served_count")

-- How many proof requests have opened. One is open at a time here, as the suite answers each at
-- once, so each opening is a new ask.
local pushes, push_open, push_parent, push_nonce = 0, false, nil, nil

local function proof_requests(world)
    return world:query({
        with = { "vault/git/proof", "vault/git", "Request" },
        optional = { "ChildOf", "vault/git/proof/reply" },
    })
end

local function carrier(world)
    return world:query({ with = { "zz/served/carrier" }, optional = { "git/world/served/status", "git/world/served/merge" } })[1]
end

local function own(world)
    return world:query({ with = { "core/library", "zz/served/own" } })[1]
end

local function identity(world)
    return world:query({ with = { "core/player/identity", "zz/served/identity" } })[1]
end

local function join(world)
    return world:query({ with = { "core/world/join", "zz/served/join" } })[1]
end

local phase, clock = "carrier", 0
local seen_pushes = 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local c = carrier(world)
    local watching = c ~= nil and c:has("git/world/served/status") and c:has("git/world/served/merge")
    local stopped = c ~= nil and not c:has("git/world/served/status") and not c:has("git/world/served/merge")
    local requests = proof_requests(world)
    if #requests > 0 and not push_open then
        pushes, push_parent, push_nonce = pushes + 1, requests[1]:get("ChildOf"), requests[1]:get("vault/git").nonce
    end
    push_open = #requests > 0
    -- Root's answer, as the suite stands in for it.
    for _, r in ipairs(requests) do
        if not r:has("vault/git/proof/reply") then
            commands:entity(r:id()):insert({ ["vault/git/proof/reply"] = { status = "pushed" } })
        end
    end
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function edits(on)
        local lib = own(world)
        local declared = lib:get("core/library")
        declared.edits = on
        commands:entity(lib:id()):insert({ ["core/library"] = declared })
    end

    if phase == "carrier" and clock > 0.2 then
        -- The boot's base landing on the world entity, after the library was declared.
        commands:spawn({ ["git/world/served"] = {}, ["zz/served/carrier"] = {}, ["core/net/sync"] = false })
        step("s1")

    elseif phase == "s1" and (watching or clock > 5) then
        T("S1_already_the_checkout_on_arrival_is_caught_up", watching,
            "the carrier lacks its sub-mods after it arrived in a world whose tree is the checkout")
        T("S7_the_proof_is_asked_once_under_the_carrier", pushes == 1 and push_parent == c:id() and push_nonce == nil,
            string.format("%d asked, under %s, nonce %s", pushes, tostring(push_parent), tostring(push_nonce)))
        T("S15_signed_in_shows_no_notice", notices == 0,
            string.format("%d notice(s), the last '%s'", notices, tostring(notice_text)))
        step("s8")

    elseif phase == "s8" and (#requests == 0 or clock > 5) then
        T("S8_the_answered_proof_request_is_closed", #requests == 0, #requests .. " still open")
        edits(false)
        step("s2")

    elseif phase == "s2" and (stopped or clock > 5) then
        T("S2_the_checkout_moving_away_takes_it_off", stopped,
            "both must go when this world's tree stops being the checkout")
        edits(true)
        step("s3")

    elseif phase == "s3" and (watching or clock > 5) then
        T("S3_the_checkout_coming_back_puts_it_back", watching,
            "both must come back with the checkout")
        edits(false)
        commands:spawn({
            ["core/library"] = { ref = OTHER, root = "test_fixtures/zz_served_other", order = 6, edits = true },
            ["core/net/sync"] = false,
        })
        step("s4")

    elseif phase == "s4" and clock > 1 then
        T("S4_another_scopes_edited_library_is_not_this_worlds", stopped,
            "a library edited under another scope made this world watch")
        local me = world:query({ with = { "core/player/identity", "zz/served/identity" } })[1]
        commands:entity(me:id()):insert({ ["core/player/identity"] = {} })
        seen_pushes = pushes
        notices = 0
        edits(true)
        step("s10")

    elseif phase == "s10" and ((watching and clock > 0.5) or clock > 5) then
        T("S10_signed_out_asks_for_no_proof", watching and pushes == seen_pushes,
            string.format("on=%s, %d asked", tostring(watching), pushes - seen_pushes))
        T("S16_signed_out_says_once_that_edits_stay_local", notices == 1 and notice_text == STAY_LOCAL
            and notice_timeout == 20,
            string.format("%d notice(s), the last '%s', timeout %s", notices, tostring(notice_text), tostring(notice_timeout)))
        local me = world:query({ with = { "core/player/identity", "zz/served/identity" } })[1]
        commands:entity(me:id()):insert({ ["core/player/identity"] = { site_user_id = "zz-user" } })
        step("s12")

    elseif phase == "s12" and ((pushes > seen_pushes and clock > 1) or clock > 5) then
        T("S12_signing_in_while_on_asks_once", pushes == seen_pushes + 1,
            string.format("%d asked", pushes - seen_pushes))
        -- Signed out, and joined again anonymously.
        commands:entity(identity(world):id()):insert({ ["core/player/identity"] = {} })
        commands:entity(join(world):id()):insert({ ["core/world/join"] = {
            endpoint = "127.0.0.1:15990", scope = SCOPE, ticket = "zz-join-anon", requester = "zz-anon",
        } })
        step("s13 in")

    elseif phase == "s13 in" and clock > 0.3 then
        seen_pushes = pushes
        commands:entity(identity(world):id()):insert({ ["core/player/identity"] = { site_user_id = "zz-user" } })
        step("s13")

    elseif phase == "s13" and clock > 1 then
        T("S13_signing_in_with_an_anonymous_join_asks_for_no_proof", pushes == seen_pushes,
            string.format("%d asked", pushes - seen_pushes))
        seen_pushes = pushes
        commands:entity(join(world):id()):insert({ ["core/world/join"] = {
            endpoint = "127.0.0.1:15990", scope = SCOPE, ticket = "zz-join-2", requester = "zz-user",
        } })
        step("s14")

    elseif phase == "s14" and ((pushes > seen_pushes and clock > 1) or clock > 5) then
        T("S14_the_join_bound_to_the_player_asks_once", pushes == seen_pushes + 1,
            string.format("%d asked", pushes - seen_pushes))
        commands:spawn({ ["core/process"] = { mode = "both" }, ["zz/served/process"] = {}, ["core/net/sync"] = false })
        edits(false)
        step("s11 off")

    elseif phase == "s11 off" and (stopped or clock > 5) and clock > 0.3 then
        seen_pushes = pushes
        edits(true)
        step("s11")

    elseif phase == "s11" and ((watching and clock > 0.5) or clock > 5) then
        T("S11_both_mode_asks_for_no_proof", watching and pushes == seen_pushes,
            string.format("on=%s, %d asked", tostring(watching), pushes - seen_pushes))
        commands:entity(world:query({ with = { "zz/served/process" } })[1]:id()):despawn()
        step("s5 on")

    elseif phase == "s5 on" and (watching or clock > 5) and clock > 0.3 then
        added = 0
        seen_pushes = pushes
        write_file_bytes(SOURCE, read_file_bytes(SOURCE))
        step("s5 reload")

    elseif phase == "s5 reload" and clock > 2 then
        T("S5_a_reload_keeps_git_status_on_added_once", watching and added == 0,
            string.format("on=%s, added again %d time(s)", tostring(watching), added))
        T("S9_a_reload_asks_at_most_once", pushes - seen_pushes <= 1,
            string.format("%d asked across the reload", pushes - seen_pushes))
        commands:entity(c:id()):remove("git/world/served")
        step("s6")

    elseif phase == "s6" and (stopped or clock > 5) then
        T("S6_taking_the_carrier_off_takes_git_status", stopped,
            "a sub-mod stayed on an entity that is no longer git/world/served's")
        phase = "done"
        suite.finish("GIT_WORLD_SERVED")
    end

    if phase ~= "done" and clock > 15 then
        T("S0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 15 s")
        phase = "done"
        suite.finish("GIT_WORLD_SERVED")
    end
end):in_set("zz/served_suite")
