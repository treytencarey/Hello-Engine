-- The invite cards and what follows an answer, driven headless with real clicks. The suite stands
-- in for root and for the world's server: root's mods answer nothing here (`world_id` is not
-- root's), so each reply, each load status and each server answer is the suite's own write on the
-- entity the mod made, and a portal the server opens is the suite's spawn, as its sync brings it.
--
-- A1   the carrier asks root for its invites once, on a request under it
-- D1   a debug accept with no world row says "No active scope to place a portal in"
-- D2   a debug accept into this world says "You are already in that world"
-- D3   a debug decline says "Invite declined", asks root nothing and drops nothing
-- D4   a debug accept asks the server for one portal at once, on the panel's request slot, with no
--      request to root and no load, and spawns none itself; a click on its fading card says "That
--      invite no longer exists"
-- C1   the server's opened answer says "Portal opened - walk through to join"
-- I1   one card per listed invite, with its texts and 26 px buttons, no timeout; no duplicates
-- I2   an invite that leaves the list fades its card only
-- I3   a click answers on a new request and starts the card's exit at once
-- IA2  a decline says "Invite declined" and loads nothing; a refused answer says why
-- I4   an answered invite still listed gets no card while its hold runs, and one once it ends
-- IA1  root's ok, after "asking", loads the world join-only and says "Opening a door to <scope>"
-- IA3  the load's ready asks the server for one portal to it; a second ready asks none
-- IA7  the load ask goes with the portal
-- IA4  a failed load says "That world has ended" or "Could not open that world: <reason>"
-- IA6  a load that is not the carrier's own drops nothing
-- IA5  eight portals of this player's refuse the drop; the server's refusal says the same
-- H1   a reload redraws every card once and keeps the asks
-- U1   `sidebar/invites` taken off closes its asks
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local MessageReader = require("bevy::prelude").MessageReader

world_id = 7

local suite = helpers.create_suite("InvitesSuite")
local T = suite.assert_test

local MOD_FILE = "assets/modules/sidebar/invites/init.lua"
local HERE = "github:zz/here:main"
local HOST_A = "github:zz/host:a"
local HOST_C = "github:zz/host:c"
local DEBUG_SCOPE = "github:zz/here:debug-hub-4"

app:add_systems(Startup, { Commands }, function(commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
end)

local original
local function reload()
    original = original or read_file_bytes(MOD_FILE)
    write_file_bytes(MOD_FILE, original .. "\n-- zz reload\n")
end

local function finish()
    if original ~= nil then write_file_bytes(MOD_FILE, original) end
    suite.finish("INVITES")
end

local camera, player

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ ["ui/theme/dark"] = {} })
    camera = commands:spawn({ ["zz/camera"] = {} }):id()
    player = commands:spawn({
        ["zz/player"] = {},
        ["sidebar/invites"] = {},
        ["git/panel"] = {},
        ["core/net/local"] = {},
        ["core/net/owner"] = { client_id = 1 },
        Transform = {
            translation = { x = 10, y = 0, z = 5 },
            rotation = { x = 0, y = 0.70710678, z = 0, w = 0.70710678 },
        },
        ["core/net/sync"] = false,
    }):id()
end)

local reloads = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("sidebar/invites/init.lua", 1, true) then reloads = reloads + 1 end
    end
end):in_set("zz/invites/reload_watch")

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

-- The player's direct children carrying `method`, each as { id, wish, reply }.
local function asks(world, method)
    local out = {}
    for _, row in ipairs(world:query({
        iter_many = world:descendants(player),
        with = { method, "ChildOf" },
        optional = { method .. "/reply" },
    })) do
        if row:get("ChildOf") == player then
            out[#out + 1] = { id = row:id(), wish = row:get(method), reply = row:get(method .. "/reply") }
        end
    end
    return out
end

-- Root's answer requests anywhere under the player (each under its hold), as { id, wish, hold }.
local function answers(world)
    local out = {}
    for _, row in ipairs(world:query({
        iter_many = world:descendants(player),
        with = { "core/registry/invites/answer", "Request", "ChildOf" },
    })) do
        out[#out + 1] = { id = row:id(), wish = row:get("core/registry/invites/answer"), hold = row:get("ChildOf") }
    end
    return out
end

local function answer_for(world, id)
    for _, a in ipairs(answers(world)) do
        if a.wish.id == id then return a end
    end
end

local function loads(world, scope)
    local out = {}
    for _, l in ipairs(asks(world, "core/world/load")) do
        if scope == nil or l.wish.scope == scope then out[#out + 1] = l end
    end
    return out
end

-- Cards still showing (not fading, not dismissed), by invite id.
local function cards(world)
    local out, n = {}, 0
    for _, c in ipairs(world:query({
        with = { "sidebar/invites/notification", "notification" },
        optional = { "notification/fade", "notification/alive" },
    })) do
        local inv = c:get("sidebar/invites/notification")
        if not c:has("notification/fade") and not c:get("notification").dismiss then
            out[inv.invite_id] = c
            n = n + 1
        end
    end
    return out, n
end

local function card_rows(world)
    local total = 0
    for _, c in ipairs(world:query({ with = { "sidebar/invites/notification" } })) do
        total = total + #world:query({ iter_many = world:descendants(c:id()), with = { "sidebar/invites/notification/row" } })
    end
    return total
end

-- The texts under `id`, depth first.
local function texts_under(world, id, list)
    list = list or {}
    local node = world:query({ iter_many = { id }, optional = { "Text", "Children" } })[1]
    if node == nil then return list end
    if node:has("Text") then list[#list + 1] = node:get("Text") end
    for _, child in ipairs(node:get("Children") or {}) do
        texts_under(world, child, list)
    end
    return list
end

local function button_in(world, card, label)
    for _, b in ipairs(world:query({ iter_many = world:descendants(card), with = { "Button" }, optional = { "Node" } })) do
        if texts_under(world, b:id())[1] == label then return b end
    end
end

local function feedback(world)
    local p = world:query({ with = { "zz/player" }, optional = { "sidebar/invites/state" } })[1]
    return p:has("sidebar/invites/state") and p:get("sidebar/invites/state") or {}
end

local function portals(world, target)
    local out = {}
    for _, p in ipairs(world:query({
        with = { "scope/portal" },
        optional = { "scope/portal/view", "Transform", "placement", "core/net/sync", "core/net/predict", "sidebar/invites/request" },
    })) do
        if target == nil or p:get("scope/portal").target == target then out[#out + 1] = p end
    end
    return out
end

-- What this mod asked on the panel's request slot.
local function slot(world)
    local p = world:query({ with = { "zz/player" }, optional = { "git/panel/request" } })[1]
    return p:has("git/panel/request") and p:get("git/panel/request") or {}
end

-- This mod's records of its portal asks, under the player.
local function records(world)
    local out = {}
    for _, r in ipairs(asks(world, "sidebar/invites/request")) do
        if r.wish.op == "drop_portal" then out[#out + 1] = r end
    end
    return out
end

-- The world's server's answer on the panel's slot.
local function answer(commands, scope, status, message)
    commands:entity(player):insert({
        ["git/panel/response"] = { op = "drop_portal", scope = scope, status = status, message = message },
    })
end

-- A portal the server opened for this player, as its sync brings it here.
local function server_portal(commands, scope)
    return commands:spawn({
        ["scope/portal"] = { target = scope },
        ["core/net/owner"] = { client_id = 1 },
        ["core/net/local"] = {},
        ["core/net/sync"] = false,
    }):id()
end

local function debug_card(commands, n, scope, message)
    commands:spawn({
        ["sidebar/invites/notification"] = {
            invite_id = "debug-" .. n,
            sender_login = "you (debug)",
            scope_key = scope,
            message = message or "Debug invite to a fresh hub world",
        },
        notification = {},
    })
end

local function list_reply(commands, world, invites)
    local list = asks(world, "core/registry/invites")[1]
    commands:entity(list.id):insert({ ["core/registry/invites/reply"] = { invites = invites } })
end

local function reply(commands, id, name, value)
    commands:entity(id):insert({ [name] = value })
end

local phase, clock = "arrived", 0
local mark = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local shown, count = cards(world)

    if phase == "arrived" and clock > 0.5 then
        local lists = asks(world, "core/registry/invites")
        T("A1_the_carrier_asks_root_for_its_invites_once", #lists == 1 and next(lists[1].wish) == nil,
            tostring(#lists))
        mark.list = lists[1] and lists[1].id
        debug_card(commands, 1, "github:zz/here:debug-hub-1")
        step("debug_norow")

    elseif phase == "debug_norow" and shown["debug-1"] ~= nil and button_in(world, shown["debug-1"]:id(), "Accept") then
        click(commands, button_in(world, shown["debug-1"]:id(), "Accept"):id())
        step("debug_norow_said")

    elseif phase == "debug_norow_said" and clock > 0.5 then
        T("D1_no_world_row_says_no_active_scope", feedback(world).feedback == "No active scope to place a portal in",
            tostring(feedback(world).feedback))
        T("D1_and_drops_nothing", #portals(world) == 0, tostring(#portals(world)))
        commands:spawn({
            ["core/world/status"] = { scope_key = HERE, scope_root = "github:zz/here", world_id = 7, mode = "client" },
            WorldShared = {},
            ["core/net/sync"] = false,
        })
        debug_card(commands, 2, HERE)
        step("debug_here")

    elseif phase == "debug_here" and shown["debug-2"] ~= nil and button_in(world, shown["debug-2"]:id(), "Accept") and clock > 0.2 then
        click(commands, button_in(world, shown["debug-2"]:id(), "Accept"):id())
        step("debug_here_said")

    elseif phase == "debug_here_said" and clock > 0.5 then
        T("D2_into_this_world_says_already_there", feedback(world).feedback == "You are already in that world",
            tostring(feedback(world).feedback))
        debug_card(commands, 3, "github:zz/here:debug-hub-3")
        step("debug_decline")

    elseif phase == "debug_decline" and shown["debug-3"] ~= nil and button_in(world, shown["debug-3"]:id(), "Decline") then
        click(commands, button_in(world, shown["debug-3"]:id(), "Decline"):id())
        step("debug_declined")

    elseif phase == "debug_declined" and clock > 0.5 then
        T("D3_a_debug_decline_says_declined", feedback(world).feedback == "Invite declined", tostring(feedback(world).feedback))
        T("D3_and_asks_root_nothing_and_drops_nothing", #answers(world) == 0
            and #portals(world) == 0 and #loads(world) == 0)
        debug_card(commands, 4, DEBUG_SCOPE)
        step("debug_accept")

    elseif phase == "debug_accept" and shown["debug-4"] ~= nil and button_in(world, shown["debug-4"]:id(), "Accept") then
        local accept = button_in(world, shown["debug-4"]:id(), "Accept"):id()
        click(commands, accept)
        click(commands, accept)
        step("debug_dropped")

    elseif phase == "debug_dropped" and clock > 0.5 then
        local ask = slot(world)
        T("D4_a_debug_accept_asks_the_server_for_one_portal_at_once", ask.op == "drop_portal"
            and ask.target_sk == DEBUG_SCOPE and #records(world) == 1,
            tostring(ask.target_sk) .. " records=" .. #records(world))
        T("D4_and_spawns_none_itself", #portals(world) == 0, tostring(#portals(world)))
        T("D4_with_no_request_and_no_load", #answers(world) == 0 and #loads(world) == 0)
        T("D4_a_click_on_its_fading_card_says_it_no_longer_exists",
            feedback(world).feedback == "That invite no longer exists", tostring(feedback(world).feedback))
        answer(commands, DEBUG_SCOPE, "opened")
        mark.debug_portal = server_portal(commands, DEBUG_SCOPE)
        step("debug_confirmed")

    elseif phase == "debug_confirmed" and clock > 0.5 then
        T("C1_the_server_s_opened_answer_says_portal_opened", feedback(world).feedback == "Portal opened - walk through to join",
            tostring(feedback(world).feedback))
        T("C1_and_the_record_of_the_ask_goes", #records(world) == 0, tostring(#records(world)))
        commands:entity(mark.debug_portal):despawn()
        list_reply(commands, world, {
            { id = "inv-a", scope = HOST_A, inviter = "Alice", expires_at = "2099-01-01" },
            { id = "inv-b", scope = "github:zz/host:b", inviter = "Bob" },
            { id = "inv-c", scope = HOST_C },
        })
        step("listed")

    elseif phase == "listed" and count == 3 and clock > 0.5 then
        local a = shown["inv-a"]
        local texts = a and texts_under(world, a:id()) or {}
        T("I1_one_card_per_listed_invite", shown["inv-a"] and shown["inv-b"] and shown["inv-c"] and true or false)
        T("I1_the_card_says_who_and_where", texts[1] == "INVITE" and texts[2] == "Alice invited you"
            and texts[3] == HOST_A and texts[4] == "wants you in " .. HOST_A
            and texts[5] == "Accept" and texts[6] == "Decline", table.concat(texts, "|"))
        T("I1_someone_when_no_sender", texts_under(world, shown["inv-c"]:id())[2] == "someone invited you")
        local accept = a and button_in(world, a:id(), "Accept")
        local node = accept and accept:get("Node")
        T("I1_buttons_are_26_px", node ~= nil and node.height ~= nil and node.height.Px == 26,
            node and tostring(node.height and node.height.Px))
        T("I1_no_timeout", a ~= nil and a:get("notification").timeout == nil and not a:has("notification/alive"))
        mark.rows = card_rows(world)
        list_reply(commands, world, {
            { id = "inv-a", scope = HOST_A, inviter = "Alice", expires_at = "2099-01-02" },
            { id = "inv-b", scope = "github:zz/host:b", inviter = "Bob" },
            { id = "inv-c", scope = HOST_C },
        })
        step("relisted")

    elseif phase == "relisted" and clock > 0.5 then
        T("I1_a_new_list_naming_them_makes_no_duplicates", count == 3
            and #world:query({ with = { "sidebar/invites/notification" } }) == 3, tostring(count))
        list_reply(commands, world, {
            { id = "inv-a", scope = HOST_A, inviter = "Alice" },
            { id = "inv-c", scope = HOST_C },
        })
        step("withdrawn")

    elseif phase == "withdrawn" and clock > 0.5 then
        T("I2_a_withdrawn_invite_fades_its_card_only", count == 2 and shown["inv-b"] == nil
            and shown["inv-a"] ~= nil and shown["inv-c"] ~= nil, tostring(count))
        mark.c_card = shown["inv-c"]:id()
        click(commands, button_in(world, mark.c_card, "Decline"):id())
        step("declining")

    elseif phase == "declining" and clock > 0.1 then
        local ask = answer_for(world, "inv-c")
        T("I3_a_click_answers_on_a_new_request", ask ~= nil and ask.wish.action == "decline"
            and #answers(world) == 1)
        T("I3_and_starts_the_card_s_exit_at_once", shown["inv-c"] == nil)
        reply(commands, ask.id, "core/registry/invites/answer/reply", { status = "asking" })
        mark.c_ask = ask.id
        step("declining_asked")

    elseif phase == "declining_asked" and clock > 0.2 then
        reply(commands, mark.c_ask, "core/registry/invites/answer/reply", { status = "ok" })
        step("declined")

    elseif phase == "declined" and clock > 0.6 then
        T("IA2_a_decline_says_declined", feedback(world).feedback == "Invite declined", tostring(feedback(world).feedback))
        T("IA2_and_loads_nothing", #loads(world) == 0, tostring(#loads(world)))
        list_reply(commands, world, {
            { id = "inv-a", scope = HOST_A, inviter = "Alice" },
            { id = "inv-c", scope = HOST_C, inviter = "Cleo" },
            { id = "inv-g", scope = "github:zz/host:g" },
            { id = "inv-h", scope = "github:zz/host:h" },
        })
        step("held")

    elseif phase == "held" and clock > 0.6 then
        T("I4_an_answered_invite_still_listed_gets_no_card_while_held", shown["inv-c"] == nil and shown["inv-g"] ~= nil,
            tostring(count))
        T("I4_its_request_stays_through_the_hold", answer_for(world, "inv-c") ~= nil)
        click(commands, button_in(world, shown["inv-g"]:id(), "Accept"):id())
        step("refusing")

    elseif phase == "refusing" and answer_for(world, "inv-g") ~= nil then
        reply(commands, answer_for(world, "inv-g").id, "core/registry/invites/answer/reply", { status = "refused", reason = "not-listed" })
        step("refused")

    elseif phase == "refused" and clock > 0.5 then
        T("IA2_a_refused_accept_says_why", feedback(world).feedback == "Invite accept failed: not-listed",
            tostring(feedback(world).feedback))
        T("IA2_and_loads_nothing_either", #loads(world) == 0)
        click(commands, button_in(world, shown["inv-h"]:id(), "Decline"):id())
        step("signed_out")

    elseif phase == "signed_out" and answer_for(world, "inv-h") ~= nil then
        reply(commands, answer_for(world, "inv-h").id, "core/registry/invites/answer/reply", { status = "refused", reason = "sign-in-required" })
        step("signed_out_said")

    elseif phase == "signed_out_said" and clock > 0.5 then
        T("IA2_signed_out_says_sign_in_to_answer", feedback(world).feedback == "Sign in to answer invites",
            tostring(feedback(world).feedback))
        click(commands, button_in(world, shown["inv-a"]:id(), "Accept"):id())
        step("accepting")

    elseif phase == "accepting" and answer_for(world, "inv-a") ~= nil then
        mark.a_ask = answer_for(world, "inv-a").id
        reply(commands, mark.a_ask, "core/registry/invites/answer/reply", { status = "asking" })
        step("accepting_asked")

    elseif phase == "accepting_asked" and clock > 0.3 then
        T("IA1_asking_loads_nothing_yet", #loads(world) == 0)
        reply(commands, mark.a_ask, "core/registry/invites/answer/reply", { status = "ok", scope = HOST_A })
        step("accepted")

    elseif phase == "accepted" and clock > 0.5 then
        local l = loads(world, HOST_A)
        local row = l[1] and world:query({ iter_many = { l[1].id }, optional = { "WorldShared", "core/net/sync" } })[1]
        T("IA1_ok_loads_the_world_join_only_once", #l == 1 and l[1].wish.join_only == true and #loads(world) == 1,
            tostring(#l))
        T("IA1_the_ask_is_shared_and_never_crosses_the_wire", row ~= nil and row:has("WorldShared")
            and row:get("core/net/sync") == false)
        T("IA1_and_says_opening_a_door", feedback(world).feedback == "Opening a door to " .. HOST_A,
            tostring(feedback(world).feedback))
        T("IA3_no_portal_before_the_world_is_ready", #portals(world, HOST_A) == 0)
        if l[1] then
            commands:entity(l[1].id):insert({ ["core/world/load"] = { scope = HOST_A, join_only = true, status = "ready" } })
            mark.a_load = l[1].id
        end
        step("ready")

    elseif phase == "ready" and clock > 0.5 then
        local ask = slot(world)
        T("IA3_ready_asks_the_server_for_one_portal_to_it", ask.op == "drop_portal" and ask.target_sk == HOST_A
            and #records(world) == 1, tostring(ask.target_sk) .. " records=" .. #records(world))
        T("IA3_and_spawns_none_itself", #portals(world, HOST_A) == 0, tostring(#portals(world, HOST_A)))
        commands:entity(mark.a_load):insert({ ["core/world/load"] = { scope = HOST_A, join_only = true, status = "ready", waited = 1 } })
        step("ready_again")

    elseif phase == "ready_again" and clock > 0.5 then
        T("IA3_a_second_ready_while_it_is_asked_asks_none", #records(world) == 1 and slot(world).target_sk == HOST_A,
            tostring(#records(world)))
        answer(commands, HOST_A, "opened")
        mark.a_portal = server_portal(commands, HOST_A)
        step("opened")

    elseif phase == "opened" and clock > 0.5 then
        T("IA3_opened_its_record_goes", #records(world) == 0 and slot(world).op == nil, tostring(#records(world)))
        commands:entity(mark.a_load):insert({ ["core/world/load"] = { scope = HOST_A, join_only = true, status = "ready", waited = 2 } })
        step("ready_third")

    elseif phase == "ready_third" and clock > 0.5 then
        T("IA3_a_ready_with_its_portal_standing_asks_none", #records(world) == 0 and slot(world).op == nil,
            tostring(slot(world).target_sk))
        T("IA7_the_load_ask_stays_while_its_portal_does", #loads(world, HOST_A) == 1)
        commands:entity(mark.a_portal):despawn()
        step("portal_gone")

    elseif phase == "portal_gone" and clock > 0.5 then
        T("IA7_the_load_ask_goes_with_the_portal", #loads(world, HOST_A) == 0, tostring(#loads(world, HOST_A)))
        mark.d_load = commands:spawn({
            ["core/world/load"] = { scope = "github:zz/host:d", join_only = true },
            ["core/net/sync"] = false,
            ChildOf = player,
        }):id()
        step("d_spawned")

    elseif phase == "d_spawned" and clock > 0.2 then
        commands:entity(mark.d_load):insert({ ["core/world/load"] = { scope = "github:zz/host:d", status = "failed", reason = "not-running" } })
        step("d_failed")

    elseif phase == "d_failed" and clock > 0.5 then
        T("IA4_not_running_says_the_world_has_ended", feedback(world).feedback == "That world has ended",
            tostring(feedback(world).feedback))
        T("IA4_and_its_ask_goes_with_no_portal", #loads(world) == 0 and #portals(world, "github:zz/host:d") == 0)
        mark.e_load = commands:spawn({
            ["core/world/load"] = { scope = "github:zz/host:e", join_only = true },
            ["core/net/sync"] = false,
            ChildOf = player,
        }):id()
        step("e_spawned")

    elseif phase == "e_spawned" and clock > 0.2 then
        commands:entity(mark.e_load):insert({ ["core/world/load"] = { scope = "github:zz/host:e", status = "failed", reason = "boom" } })
        step("e_failed")

    elseif phase == "e_failed" and clock > 0.5 then
        T("IA4_another_failure_says_why", feedback(world).feedback == "Could not open that world: boom",
            tostring(feedback(world).feedback))
        commands:spawn({ ["core/world/load"] = { scope = "github:zz/host:f", join_only = true, status = "ready" }, ["core/net/sync"] = false })
        step("lookalike")

    elseif phase == "lookalike" and clock > 0.6 then
        T("IA6_a_load_that_is_not_the_carrier_s_drops_nothing", #portals(world, "github:zz/host:f") == 0)
        for i = 1, 8 do
            commands:spawn({ ["scope/portal"] = { target = "github:zz/full:" .. i }, ["core/net/owner"] = { client_id = 1 }, ["zz/full"] = {} })
        end
        commands:spawn({ ["scope/portal"] = { target = "github:zz/other:1" }, ["core/net/owner"] = { client_id = 2 }, ["zz/full"] = {} })
        debug_card(commands, 5, "github:zz/here:debug-hub-5")
        step("full")

    elseif phase == "full" and shown["debug-5"] ~= nil and button_in(world, shown["debug-5"]:id(), "Accept") and clock > 0.3 then
        click(commands, button_in(world, shown["debug-5"]:id(), "Accept"):id())
        step("full_said")

    elseif phase == "full_said" and clock > 0.5 then
        T("IA5_eight_portals_of_this_player_s_refuse_the_drop", feedback(world).feedback == "You have too many portals open"
            and #portals(world, "github:zz/here:debug-hub-5") == 0, tostring(feedback(world).feedback))
        for _, e in ipairs(world:query({ with = { "zz/full" } })) do
            commands:entity(e:id()):despawn()
        end
        debug_card(commands, 6, "github:zz/here:debug-hub-6")
        step("refusal")

    elseif phase == "refusal" and shown["debug-6"] ~= nil and button_in(world, shown["debug-6"]:id(), "Accept") and clock > 0.3 then
        click(commands, button_in(world, shown["debug-6"]:id(), "Accept"):id())
        step("refusal_dropped")

    elseif phase == "refusal_dropped" and slot(world).target_sk == "github:zz/here:debug-hub-6" and clock > 0.3 then
        commands:entity(player):insert({ ["sidebar/invites/state"] = { feedback = "zz", feedback_kind = "ok" } })
        answer(commands, "github:zz/here:debug-hub-6", "failed", "8 portals already")
        step("refused_portal")

    elseif phase == "refused_portal" and clock > 0.5 then
        T("IA5_the_server_s_refusal_says_too_many_portals", feedback(world).feedback == "You have too many portals open"
            and #records(world) == 0, tostring(feedback(world).feedback))
        local ask = answer_for(world, "inv-c")
        local hold = ask and world:query({ iter_many = { ask.hold }, with = { "cooldown/left", "sidebar/invites/request" } })[1]
        local left = hold and hold:get("cooldown/left")["sidebar/invites/request"]
        T("I4_the_hold_is_a_30_s_cooldown_under_the_request", left ~= nil and left > 20 and left <= 30, tostring(left))
        if hold then
            commands:entity(hold:id()):insert({ ["cooldown/left"] = { ["sidebar/invites/request"] = 0.01 } })
        end
        step("unheld")

    elseif phase == "unheld" and clock > 0.8 then
        T("I4_once_the_hold_ends_the_invite_still_listed_gets_its_card_again", shown["inv-c"] ~= nil
            and texts_under(world, shown["inv-c"]:id())[2] == "Cleo invited you", tostring(count))
        T("I4_and_its_answered_request_goes", answer_for(world, "inv-c") == nil)
        mark.cards = count
        mark.answers = #answers(world)
        mark.reloads = reloads
        reload()
        step("reloading")

    elseif phase == "reloading" and reloads > mark.reloads then
        step("reloaded")

    elseif phase == "reloaded" and clock > 2 then
        local rows_now = card_rows(world)
        local expected = 0
        for _, c in pairs(shown) do
            local inv = c:get("sidebar/invites/notification")
            expected = expected + (inv.message ~= nil and 5 or 4)
        end
        T("H1_a_reload_keeps_one_card_per_invite", count == mark.cards
            and #world:query({ with = { "sidebar/invites/notification" } }) == mark.cards, count .. " of " .. mark.cards)
        T("H1_and_redraws_each_once", rows_now == expected, rows_now .. " rows, " .. expected .. " expected")
        T("H1_its_asks_stay", #asks(world, "core/registry/invites") == 1 and asks(world, "core/registry/invites")[1].id == mark.list
            and #answers(world) == mark.answers)
        commands:entity(player):remove("sidebar/invites")
        step("removed")

    elseif phase == "removed" and clock > 1 then
        local left = #asks(world, "core/registry/invites") + #answers(world) + #loads(world)
        T("U1_taken_off_its_asks_close", left == 0, tostring(left))
        phase = "done"
        finish()
    end

    if phase ~= "done" and clock > 15 then
        T("Z_reached_" .. phase, false, "stuck in phase '" .. phase .. "'")
        phase = "done"
        finish()
    end
end):in_set("zz/invites/suite")
