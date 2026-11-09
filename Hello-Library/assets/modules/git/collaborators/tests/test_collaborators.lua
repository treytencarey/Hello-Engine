-- The collaborators panel, driven headless with real clicks. The suite stands in for root: root's
-- mods answer nothing here (`world_id` is not root's), so every reply is the suite's write on the
-- request the panel made.
--
-- B1  a local player with the panel gets one "Collaborators" button in the bar
-- V1  opened, the panel asks root for the player's login, the invite list and this world's
--     repository's collaborators, under the panel; it loads until they come
-- R1  "COLLABORATORS (n)", a row per collaborator with its letter and role; the player's own row
--     and a row with no GitHub id have no Invite button
-- W1  before the invite list answers, "Checking website..." and Invite does nothing
-- W2  a list error says "Website offline - invites unavailable" and Invite does nothing
-- W3  signed out of Hello!, "Sign in on the Profile panel to send invites", and Invite does nothing
-- E1  an error from root says "Error: <error>", and an empty list "No collaborators found."
-- S1  online, Invite asks root to invite that login into this world, with "Inviting <login>..."
-- S2  root's ok says "Invited <login>"; a second click closes the first request
-- S3  "not-a-collaborator" and other refusals each say why
-- F1  what sidebar/invites last said shows under them
-- G1  git/panel's chosen repository is listed instead, with no Invite buttons; unchosen, this
--     world's again
-- N1  with neither, "No repository selected."
-- O1  signed out of GitHub, "Sign in to GitHub in Accounts"
-- T1  no token reaches any component but root's reply
-- H1  a reload keeps the panel open, rebuilt once, and its sends stay; with DEBUG_INVITES on, the
--     player's own row offers "Debug", which makes a local invite card to a fresh branch here
-- U1  the panel taken off closes its sends, its button and its panel
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local MessageReader = require("bevy::prelude").MessageReader

world_id = 7

local suite = helpers.create_suite("CollaboratorsSuite")
local T = suite.assert_test

local MOD_FILE = "assets/modules/git/collaborators/init.lua"
local HERE = "github:zz/here:main"
local SECRET = "zz-github-token-secret"

app:add_systems(Startup, { Commands }, function(commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
end)

local original
local function reload_with_debug()
    original = original or read_file_bytes(MOD_FILE)
    local edited = original:gsub("local DEBUG_INVITES = false", "local DEBUG_INVITES = true")
    write_file_bytes(MOD_FILE, edited)
end

local function finish()
    if original ~= nil then write_file_bytes(MOD_FILE, original) end
    suite.finish("COLLABORATORS")
end

local camera, player, row

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ ["ui/theme/dark"] = {} })
    camera = commands:spawn({ ["zz/camera"] = {} }):id()
    row = commands:spawn({
        ["core/world/status"] = { scope_key = HERE, scope_root = "github:zz/here", world_id = 7, mode = "client" },
        WorldShared = {},
        ["core/net/sync"] = false,
    }):id()
    player = commands:spawn({
        ["zz/player"] = {},
        input = {},
        sidebar = {},
        ["git/collaborators"] = {},
        ["core/net/sync"] = false,
    }):id()
end)

local reloads = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("git/collaborators/init.lua", 1, true) then reloads = reloads + 1 end
    end
end):in_set("zz/collaborators/reload_watch")

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

local function buttons(world)
    return world:query({ with = { "git/collaborators/button" }, optional = { "sidebar/button", "sidebar/button/open", "ChildOf", "Node" } })
end

local function views(world)
    return world:query({ with = { "git/collaborators/view" }, optional = { "sidebar/panel", "Children" } })
end

-- The asks under `parent` carrying `method`, each as { id, wish, reply }.
local function asks_under(world, parent, method)
    local out = {}
    if parent == nil then return out end
    for _, r in ipairs(world:query({
        iter_many = world:descendants(parent),
        with = { method, "Request", "ChildOf" },
        optional = { method .. "/reply" },
    })) do
        if r:get("ChildOf") == parent then
            out[#out + 1] = { id = r:id(), wish = r:get(method), reply = r:get(method .. "/reply") }
        end
    end
    return out
end

local function view_id(world)
    local v = views(world)[1]
    return v and v:id()
end

local function sends(world)
    return asks_under(world, player, "core/registry/invites/send")
end

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

-- Every row's texts, in order.
local function rows_text(world)
    local out = {}
    for _, r in ipairs(world:query({ with = { "git/collaborators/row" }, optional = { "ChildOf" } })) do
        out[#out + 1] = table.concat(texts_under(world, r:id()), "|")
    end
    return out
end

local function has_row(world, text)
    for _, t in ipairs(rows_text(world)) do
        if t == text then return true end
    end
    return false
end

-- The row whose texts start with the avatar letter and `login`.
local function row_of(world, login)
    for _, r in ipairs(world:query({ with = { "git/collaborators/row" } })) do
        if texts_under(world, r:id())[2] == login then return r:id() end
    end
end

local function button_in(world, parent, label)
    if parent == nil then return nil end
    for _, b in ipairs(world:query({ iter_many = world:descendants(parent), with = { "Button" } })) do
        if texts_under(world, b:id())[1] == label then return b:id() end
    end
end

local function role_of(world, parent, text)
    for _, t in ipairs(world:query({ iter_many = world:descendants(parent), with = { "Text" }, optional = { "ui/style" } })) do
        if t:get("Text") == text then return (t:get("ui/style") or {}).text end
    end
end

local function holds(value, needle, depth)
    if type(value) == "string" then return value:find(needle, 1, true) ~= nil end
    if type(value) ~= "table" or depth > 8 then return false end
    for k, v in pairs(value) do
        if holds(k, needle, depth + 1) or holds(v, needle, depth + 1) then return true end
    end
    return false
end

local function holders_of(world, needle)
    local out = {}
    for _, r in ipairs(world:query({})) do
        local full = world:get_entity(r:id())
        local ok, names = pcall(function() return full:get_components() end)
        for _, name in ipairs(ok and names or {}) do
            local got, value = pcall(function() return full:get(name) end)
            if got and holds(value, needle, 0) then out[#out + 1] = name end
        end
    end
    return out
end

local function reply(commands, id, name, value)
    commands:entity(id):insert({ [name] = value })
end

local COLLABORATORS = {
    { github_id = "1", login = "zz-me", role = "admin" },
    { github_id = "2", login = "Alice", role = "write" },
    { github_id = "3", login = "bob" },
    { login = "noid", role = "read" },
}

local phase, clock = "arrived", 0
local mark = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "arrived" and clock > 0.3 then
        commands:entity(player):insert({ ["core/net/local"] = {} })
        step("button")

    -- The sidebar makes the button an icon, with its click observer, a frame or more after it comes.
    elseif phase == "button" and #buttons(world) > 0 and buttons(world)[1]:has("Node") and clock > 0.3 then
        local b = buttons(world)[1]
        local bar = world:query({ with = { "sidebar/bar" } })[1]
        T("B1_one_collaborators_button_in_the_bar", #buttons(world) == 1 and b:get("ChildOf") == bar:id()
            and b:get("sidebar/button").title == "Collaborators")
        commands:entity(player):insert({ ["sidebar/open"] = {} })
        step("icon")

    elseif phase == "icon" and clock > 0.3 then
        click(commands, buttons(world)[1]:id())
        step("opening")

    elseif phase == "opening" and #views(world) == 1 and clock > 0.6 then
        local v = view_id(world)
        local signin = asks_under(world, v, "vault/github/signin")
        local lists = asks_under(world, v, "core/registry/invites")
        local repos = asks_under(world, v, "vault/github/repos")
        T("V1_the_panel_asks_root_under_itself", #signin == 1 and #lists == 1 and #repos == 1
            and repos[1].wish.owner == "zz" and repos[1].wish.name == "here",
            string.format("%d %d %d", #signin, #lists, #repos))
        T("V1_none_on_the_carrier", #asks_under(world, player, "vault/github/repos") == 0
            and #asks_under(world, player, "core/registry/invites") == 0)
        T("V1_it_loads_until_they_come", has_row(world, "Loading collaborators..."), table.concat(rows_text(world), " / "))
        T("V1_the_title_is_set", views(world)[1]:get("sidebar/panel").title == "Collaborators")
        reply(commands, signin[1].id, "vault/github/signin/reply", { login = "zz-me", pending = false, token = SECRET })
        reply(commands, repos[1].id, "vault/github/repos/reply", { collaborators = COLLABORATORS })
        step("listed")

    elseif phase == "listed" and has_row(world, "COLLABORATORS (4)") and clock > 0.3 then
        local me, alice, noid = row_of(world, "zz-me"), row_of(world, "Alice"), row_of(world, "noid")
        local bob = row_of(world, "bob")
        T("R1_the_header_counts_them", true)
        local function background(id)
            return (world:query({ iter_many = { id }, optional = { "ui/style" } })[1]:get("ui/style") or {}).background
        end
        T("R1_rows_alternate", background(me) == "row_bg" and background(alice) == "row_alt" and background(bob) == "row_bg",
            tostring(background(alice)))
        T("R1_rows_have_a_letter_and_a_role", texts_under(world, alice)[1] == "A" and texts_under(world, alice)[3] == "write"
            and texts_under(world, bob)[1] == "B" and texts_under(world, bob)[3] == "collaborator"
            and role_of(world, me, "admin") == "accent" and role_of(world, alice, "write") == "text_dim",
            table.concat(texts_under(world, alice), "|"))
        T("R1_no_button_on_the_player_s_own_row_or_without_an_id", button_in(world, me, "Invite") == nil
            and button_in(world, me, "Debug") == nil and button_in(world, noid, "Invite") == nil
            and button_in(world, alice, "Invite") ~= nil)
        T("W1_before_the_list_answers_checking", has_row(world, "Checking website..."), table.concat(rows_text(world), " / "))
        click(commands, button_in(world, alice, "Invite"))
        step("checking_click")

    elseif phase == "checking_click" and clock > 0.4 then
        T("W1_and_invite_does_nothing", #sends(world) == 0)
        local lists = asks_under(world, view_id(world), "core/registry/invites")
        reply(commands, lists[1].id, "core/registry/invites/reply", { invites = {}, error = "registry-unreachable" })
        step("offline")

    elseif phase == "offline" and has_row(world, "Website offline - invites unavailable") and clock > 0.3 then
        T("W2_a_list_error_says_website_offline", true)
        click(commands, button_in(world, row_of(world, "Alice"), "Invite"))
        step("offline_click")

    elseif phase == "offline_click" and clock > 0.4 then
        T("W2_and_invite_does_nothing", #sends(world) == 0)
        local lists = asks_under(world, view_id(world), "core/registry/invites")
        reply(commands, lists[1].id, "core/registry/invites/reply", { invites = {}, error = "sign-in-required" })
        step("site_signed_out")

    elseif phase == "site_signed_out" and has_row(world, "Sign in on the Profile panel to send invites") and clock > 0.3 then
        T("W3_signed_out_of_hello_says_sign_in_on_the_profile_panel", not has_row(world, "Website offline - invites unavailable"))
        click(commands, button_in(world, row_of(world, "Alice"), "Invite"))
        step("site_signed_out_click")

    elseif phase == "site_signed_out_click" and clock > 0.4 then
        T("W3_and_invite_does_nothing", #sends(world) == 0)
        local lists = asks_under(world, view_id(world), "core/registry/invites")
        reply(commands, lists[1].id, "core/registry/invites/reply", { invites = {} })
        step("online")

    elseif phase == "online" and not has_row(world, "Sign in on the Profile panel to send invites") and clock > 0.3 then
        T("S1_online_no_website_line", not has_row(world, "Checking website..."))
        click(commands, button_in(world, row_of(world, "Alice"), "Invite"))
        step("sending")

    elseif phase == "sending" and #sends(world) == 1 and has_row(world, "Inviting Alice...") then
        local s = sends(world)[1]
        T("S1_invite_asks_root_for_this_world", s.wish.scope == HERE and s.wish.invitee == "Alice")
        T("S1_and_says_inviting", true)
        mark.first = s.id
        click(commands, button_in(world, row_of(world, "Alice"), "Invite"))
        step("in_flight_click")

    elseif phase == "in_flight_click" and clock > 0.4 then
        T("S1_a_click_while_it_flies_sends_nothing", #sends(world) == 1 and sends(world)[1].id == mark.first)
        reply(commands, mark.first, "core/registry/invites/send/reply", { status = "requested" })
        step("requested")

    elseif phase == "requested" and clock > 0.3 then
        reply(commands, mark.first, "core/registry/invites/send/reply", { status = "ok" })
        step("invited")

    elseif phase == "invited" and has_row(world, "Invited Alice") and clock > 0.3 then
        T("S2_root_s_ok_says_invited", true)
        click(commands, button_in(world, row_of(world, "bob"), "Invite"))
        step("bob")

    elseif phase == "bob" and #sends(world) == 2 then
        local list = sends(world)
        reply(commands, list[2].id, "core/registry/invites/send/reply", { status = "refused", reason = "not-a-collaborator" })
        step("bob_refused")

    elseif phase == "bob_refused" and has_row(world, "Only collaborators of this world can invite") and clock > 0.3 then
        T("S3_not_a_collaborator_says_only_collaborators", true)
        click(commands, button_in(world, row_of(world, "Alice"), "Invite"))
        step("again")

    elseif phase == "again" and clock > 0.4 then
        local alice = {}
        for _, s in ipairs(sends(world)) do
            if s.wish.invitee == "Alice" then alice[#alice + 1] = s end
        end
        T("S2_a_second_click_closes_the_first", #alice == 1 and alice[1].id ~= mark.first and #sends(world) == 2,
            #alice .. " open for Alice")
        if alice[1] then
            reply(commands, alice[1].id, "core/registry/invites/send/reply", { status = "refused", reason = "rate-limited" })
        end
        step("failed")

    elseif phase == "failed" and has_row(world, "Invite failed: rate-limited") and clock > 0.3 then
        T("S3_other_refusals_say_invite_failed", true)
        commands:entity(player):insert({ ["sidebar/invites/state"] = { feedback = "Portal opened - walk through to join", feedback_kind = "ok" } })
        step("feedback")

    elseif phase == "feedback" and has_row(world, "Portal opened - walk through to join") and clock > 0.3 then
        T("F1_sidebar_invites_feedback_shows", true)
        mark.here_ask = asks_under(world, view_id(world), "vault/github/repos")[1].id
        commands:entity(player):insert({ ["git/panel/state"] = { open = false, repo = { owner = "zz", name = "other" } } })
        step("chosen")

    elseif phase == "chosen" and clock > 0.5 then
        local repos = asks_under(world, view_id(world), "vault/github/repos")
        T("G1_git_panel_s_repository_is_asked_for_instead", #repos == 1 and repos[1].wish.name == "other"
            and repos[1].id ~= mark.here_ask, #repos .. " " .. tostring(repos[1] and repos[1].wish.name))
        if repos[1] then
            reply(commands, repos[1].id, "vault/github/repos/reply", { error = "HTTP 500", status = 500 })
        end
        step("chosen_error")

    elseif phase == "chosen_error" and has_row(world, "Error: HTTP 500") and clock > 0.3 then
        T("E1_an_error_says_error", true)
        reply(commands, asks_under(world, view_id(world), "vault/github/repos")[1].id, "vault/github/repos/reply", { collaborators = {} })
        step("chosen_empty")

    elseif phase == "chosen_empty" and has_row(world, "No collaborators found.") and clock > 0.3 then
        T("E1_none_says_no_collaborators_found", true)
        reply(commands, asks_under(world, view_id(world), "vault/github/repos")[1].id, "vault/github/repos/reply",
            { collaborators = { { github_id = "9", login = "carol" } } })
        step("chosen_listed")

    elseif phase == "chosen_listed" and has_row(world, "COLLABORATORS (1)") and clock > 0.3 then
        T("G1_its_rows_have_no_invite_button", button_in(world, row_of(world, "carol"), "Invite") == nil
            and row_of(world, "carol") ~= nil)
        commands:entity(player):remove("git/panel/state")
        step("unchosen")

    elseif phase == "unchosen" and clock > 0.5 then
        local repos = asks_under(world, view_id(world), "vault/github/repos")
        T("G1_unchosen_this_world_s_again", #repos == 1 and repos[1].wish.name == "here", tostring(#repos))
        commands:entity(row):insert({ ["core/world/status"] = { scope_key = "zz:nowhere", world_id = 7, mode = "client" } })
        step("no_repo")

    elseif phase == "no_repo" and clock > 0.5 then
        T("N1_with_neither_no_repository_selected", has_row(world, "No repository selected.")
            and #asks_under(world, view_id(world), "vault/github/repos") == 0, table.concat(rows_text(world), " / "))
        commands:entity(row):insert({ ["core/world/status"] = { scope_key = HERE, scope_root = "github:zz/here", world_id = 7, mode = "client" } })
        local signin = asks_under(world, view_id(world), "vault/github/signin")
        reply(commands, signin[1].id, "vault/github/signin/reply", { pending = false })
        step("signed_out")

    elseif phase == "signed_out" and clock > 0.5 then
        T("O1_signed_out_says_sign_in_to_github", has_row(world, "Sign in to GitHub in Accounts"), table.concat(rows_text(world), " / "))
        local signin = asks_under(world, view_id(world), "vault/github/signin")
        reply(commands, signin[1].id, "vault/github/signin/reply", { login = "zz-me", pending = false, token = SECRET })
        local repos = asks_under(world, view_id(world), "vault/github/repos")
        if repos[1] then reply(commands, repos[1].id, "vault/github/repos/reply", { collaborators = COLLABORATORS }) end
        step("scan")

    elseif phase == "scan" and has_row(world, "COLLABORATORS (4)") and clock > 0.3 then
        local leaks, found = {}, false
        for _, name in ipairs(holders_of(world, SECRET)) do
            if name == "vault/github/signin/reply" then found = true else leaks[#leaks + 1] = name end
        end
        T("T1_no_token_reaches_any_component_but_root_s_reply", found and #leaks == 0, "leaks " .. table.concat(leaks, " "))
        mark.reloads = reloads
        mark.button = buttons(world)[1]:id()
        mark.sends = #sends(world)
        reload_with_debug()
        step("reloading")

    elseif phase == "reloading" and reloads > mark.reloads then
        step("reloaded")

    elseif phase == "reloaded" and clock > 2 then
        local b = buttons(world)[1]
        local v = view_id(world)
        T("H1_a_reload_leaves_one_new_button_open", #buttons(world) == 1 and b:id() ~= mark.button and b:has("sidebar/button/open"),
            tostring(#buttons(world)))
        T("H1_and_one_panel_asking_once_each", #views(world) == 1 and #asks_under(world, v, "vault/github/signin") == 1
            and #asks_under(world, v, "core/registry/invites") == 1 and #asks_under(world, v, "vault/github/repos") == 1)
        T("H1_its_sends_stay", #sends(world) == mark.sends, #sends(world) .. " of " .. mark.sends)
        local signin = asks_under(world, v, "vault/github/signin")
        local lists = asks_under(world, v, "core/registry/invites")
        local repos = asks_under(world, v, "vault/github/repos")
        reply(commands, signin[1].id, "vault/github/signin/reply", { login = "zz-me", pending = false })
        reply(commands, lists[1].id, "core/registry/invites/reply", { invites = {} })
        reply(commands, repos[1].id, "vault/github/repos/reply", { collaborators = COLLABORATORS })
        step("debug")

    elseif phase == "debug" and has_row(world, "COLLABORATORS (4)") and clock > 0.3 then
        local me = row_of(world, "zz-me")
        T("H1_with_debug_on_the_own_row_offers_debug", button_in(world, me, "Debug") ~= nil
            and #world:query({ with = { "git/collaborators/row" } }) == 7, tostring(#world:query({ with = { "git/collaborators/row" } })))
        if button_in(world, me, "Debug") then click(commands, button_in(world, me, "Debug")) end
        step("debug_card")

    elseif phase == "debug_card" and clock > 0.5 then
        local card = world:query({ with = { "sidebar/invites/notification", "notification" } })[1]
        local inv = card and card:get("sidebar/invites/notification")
        local n = inv and tostring(inv.invite_id):match("^debug%-(%d+)$")
        T("H1_debug_makes_a_local_invite_card_to_a_fresh_branch_here", n ~= nil
            and inv.scope_key == "github:zz/here:debug-hub-" .. n and inv.sender_login == "you (debug)"
            and inv.message == "Debug invite to a fresh hub world" and #sends(world) == mark.sends,
            inv and tostring(inv.invite_id) .. " " .. tostring(inv.scope_key))
        commands:entity(player):remove("git/collaborators")
        step("removed")

    elseif phase == "removed" and clock > 1 then
        T("U1_taken_off_its_sends_close", #sends(world) == 0, tostring(#sends(world)))
        T("U1_and_its_button_and_panel_go", #buttons(world) == 0 and #views(world) == 0
            and #world:query({ with = { "git/collaborators/row" } }) == 0)
        phase = "done"
        finish()
    end

    if phase ~= "done" and clock > 15 then
        T("Z_reached_" .. phase, false, "stuck in phase '" .. phase .. "'")
        phase = "done"
        finish()
    end
end):in_set("zz/collaborators/suite")
