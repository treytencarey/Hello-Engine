-- The sign-in panel on a real player, driven headless, with root's replies stubbed: this VM plays
-- root and holds no session, so the replies are the suite's. `player/client` adds the carrier, and a
-- real click on the sidebar's button opens the panel.
--
-- A1  the carrier asks root who is signed in, once per sign-in, on requests under it
-- V1  before root answers, both rows say so and offer no button
-- C1  "Sign in" asks root to sign in on a new request; the standing ask stays
-- P1  a pending sign-in shows the code and the address, and no button
-- S1  signed in, a row shows the name root gave, with "Sign out"
-- O1  "Sign out" asks root to sign out, on a new request in place of the sign-in's
-- T1  a reply field the panel does not show reaches no other component
-- H1  a reload keeps the panel open, its rows, and its asks, none doubled
-- U1  the carrier's sign-ins taken off close every ask
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("ProfileSuite")
local T = suite.assert_test

local MOD_FILE = "assets/modules/sidebar/profile/init.lua"
local SITE_SECRET = "zz-site-access-secret"
local GITHUB_SECRET = "zz-github-token-secret"
local DEVICE_SECRET = "zz-device-code-secret"

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
    suite.finish("PROFILE")
end

local camera, player

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ ["ui/theme/dark"] = {} })
    camera = commands:spawn({ ["zz/camera"] = {} }):id()
    player = commands:spawn({
        ["zz/player"] = {},
        player = { client_id = 1, spawn_index = 1 },
        ["core/net/sync"] = false,
    }):id()
end)

local reloads = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("sidebar/profile/init.lua", 1, true) then reloads = reloads + 1 end
    end
end):in_set("zz/profile/reload_watch")

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

local function buttons(world)
    return world:query({ with = { "sidebar/profile/button" }, optional = { "sidebar/button", "sidebar/button/open", "ChildOf" } })
end

local function views(world)
    return world:query({ with = { "sidebar/profile/view" }, optional = { "sidebar/panel" } })
end

-- The asks under the player: `method` is the request's component; each as { id, wish, reply }.
local function asks(world, method)
    local out = {}
    for _, row in ipairs(world:query({
        iter_many = world:descendants(player),
        with = { method, "Request", "ChildOf" },
        optional = { method .. "/reply" },
    })) do
        if row:get("ChildOf") == player then
            out[#out + 1] = { id = row:id(), wish = row:get(method), reply = row:get(method .. "/reply") }
        end
    end
    return out
end

local function standing(world, method)
    for _, ask in ipairs(asks(world, method)) do
        if not (ask.wish.start or ask.wish.sign_out) then return ask end
    end
end

local function action(world, method)
    for _, ask in ipairs(asks(world, method)) do
        if ask.wish.start or ask.wish.sign_out then return ask end
    end
end

-- The texts under `id`, depth first, as they read on screen.
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

-- A row's texts, for the row whose first text is `title`.
local function row_texts(world, title)
    for _, row in ipairs(world:query({ with = { "sidebar/profile/row" } })) do
        local list = texts_under(world, row:id())
        if list[1] == title then return list end
    end
    return {}
end

local function has_text(list, text)
    for _, t in ipairs(list) do
        if t == text then return true end
    end
    return false
end

-- The button in the row titled `title` labelled `label`.
local function button_in(world, title, label)
    for _, row in ipairs(world:query({ with = { "sidebar/profile/row" } })) do
        local inside = world:descendants(row:id())
        if texts_under(world, row:id())[1] == title then
            for _, b in ipairs(world:query({ iter_many = inside, with = { "Button" } })) do
                local text = world:query({ iter_many = world:descendants(b:id()), with = { "Text" } })[1]
                if text and text:get("Text") == label then return b:id() end
            end
        end
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

-- Every component on every entity holding `needle`, as "name" strings.
local function holders_of(world, needle)
    local out = {}
    for _, row in ipairs(world:query({})) do
        local full = world:get_entity(row:id())
        local ok, names = pcall(function() return full:get_components() end)
        for _, name in ipairs(ok and names or {}) do
            local got, value = pcall(function() return full:get(name) end)
            if got and holds(value, needle, 0) then out[#out + 1] = name end
        end
    end
    return out
end

local function reply(commands, ask, name, value)
    commands:entity(ask.id):insert({ [name] = value })
end

local phase, clock = "arrived", 0
local mark = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "arrived" and clock > 0.3 then
        commands:entity(player):insert({ ["core/net/local"] = {} })
        step("button")

    elseif phase == "button" and #buttons(world) > 0 and clock > 0.3 then
        local me = world:query({ with = { "zz/player" }, optional = { "sidebar/profile" } })[1]
        local b = buttons(world)[1]
        local bar = world:query({ with = { "sidebar/bar" } })[1]
        T("A0_player_client_adds_the_carrier_and_one_button_in_the_bar", me:has("sidebar/profile")
            and #buttons(world) == 1 and b:get("ChildOf") == bar:id())
        local site, github = asks(world, "core/player/session/signin"), asks(world, "vault/github/signin")
        T("A1_the_carrier_asks_root_who_is_signed_in_once_per_sign_in", #site == 1 and #github == 1
            and next(site[1].wish) == nil and next(github[1].wish) == nil,
            string.format("site %d github %d", #site, #github))
        commands:entity(player):insert({ ["sidebar/open"] = {} })
        click(commands, b:id())
        step("opening")

    elseif phase == "opening" and #views(world) == 1 and #row_texts(world, "GitHub") > 0 and clock > 0.2 then
        local site, github = row_texts(world, "Hello!"), row_texts(world, "GitHub")
        T("V1_before_root_answers_both_rows_say_so_with_no_button", has_text(site, "Asking...") and has_text(github, "Asking...")
            and button_in(world, "Hello!", "Sign in") == nil and button_in(world, "GitHub", "Sign in") == nil,
            table.concat(site, "|") .. " / " .. table.concat(github, "|"))
        T("V1_the_title_is_set", views(world)[1]:get("sidebar/panel").title == "Accounts")
        reply(commands, standing(world, "core/player/session/signin"), "core/player/session/signin/reply", { pending = false })
        reply(commands, standing(world, "vault/github/signin"), "vault/github/signin/reply", { pending = false })
        step("signed_out")

    elseif phase == "signed_out" and button_in(world, "Hello!", "Sign in") ~= nil and button_in(world, "GitHub", "Sign in") ~= nil then
        T("V2_answered_signed_out_each_row_offers_sign_in", has_text(row_texts(world, "Hello!"), "Not signed in")
            and has_text(row_texts(world, "GitHub"), "Not signed in"))
        mark.standing = standing(world, "core/player/session/signin").id
        click(commands, button_in(world, "Hello!", "Sign in"))
        step("asked")

    elseif phase == "asked" and action(world, "core/player/session/signin") ~= nil and clock > 0.2 then
        local ask = action(world, "core/player/session/signin")
        local still = standing(world, "core/player/session/signin")
        T("C1_sign_in_asks_root_on_a_new_request", ask.wish.start == true and not ask.wish.sign_out
            and #asks(world, "core/player/session/signin") == 2 and action(world, "vault/github/signin") == nil)
        T("C1_the_standing_ask_stays", still ~= nil and still.id == mark.standing)
        reply(commands, ask, "core/player/session/signin/reply", { pending = true })
        step("pending_no_code")

    elseif phase == "pending_no_code" and has_text(row_texts(world, "Hello!"), "Waiting for sign-in...") then
        reply(commands, action(world, "core/player/session/signin"), "core/player/session/signin/reply", {
            pending = true,
            user_code = "ZZZZ-2222",
            verification_uri = "https://zz.invalid/device?user_code=ZZZZ-2222",
            device_code = DEVICE_SECRET,
        })
        step("pending")

    elseif phase == "pending" and has_text(row_texts(world, "Hello!"), "ZZZZ-2222") then
        local site = row_texts(world, "Hello!")
        T("P1_pending_shows_the_code", has_text(site, "ZZZZ-2222"), table.concat(site, "|"))
        T("P1_and_the_address", has_text(site, "Enter the code at https://zz.invalid/device?user_code=ZZZZ-2222:"), table.concat(site, "|"))
        T("P1_and_no_button", button_in(world, "Hello!", "Sign in") == nil and button_in(world, "Hello!", "Sign out") == nil)
        reply(commands, standing(world, "core/player/session/signin"), "core/player/session/signin/reply", {
            user = { id = "u-42", name = "Zz Player" }, pending = false, access_token = SITE_SECRET,
        })
        reply(commands, action(world, "core/player/session/signin"), "core/player/session/signin/reply", {
            user = { id = "u-42", name = "Zz Player" }, pending = false,
        })
        reply(commands, standing(world, "vault/github/signin"), "vault/github/signin/reply", {
            login = "zz-octo", pending = false, token = GITHUB_SECRET,
        })
        step("signed_in")

    elseif phase == "signed_in" and button_in(world, "Hello!", "Sign out") ~= nil and button_in(world, "GitHub", "Sign out") ~= nil then
        local site, github = row_texts(world, "Hello!"), row_texts(world, "GitHub")
        T("S1_signed_in_shows_the_name", has_text(site, "Zz Player") and not has_text(site, "ZZZZ-2222"), table.concat(site, "|"))
        T("S2_and_the_github_login", has_text(github, "zz-octo"), table.concat(github, "|"))
        step("scan")

    elseif phase == "scan" and clock > 0.6 then
        -- The device code's reply was replaced by the signed-in one, so only the two tokens are still
        -- held, each on its reply: the scan finds them there, so it can find them elsewhere.
        local leaks, found = {}, {}
        for _, secret in ipairs({ SITE_SECRET, GITHUB_SECRET, DEVICE_SECRET }) do
            for _, name in ipairs(holders_of(world, secret)) do
                if name:sub(-6) == "/reply" then found[secret] = true else leaks[#leaks + 1] = name end
            end
        end
        T("T1_no_token_reaches_any_component_but_the_reply_root_wrote", #leaks == 0 and found[SITE_SECRET]
            and found[GITHUB_SECRET], "leaks " .. table.concat(leaks, " "))
        mark.standing = standing(world, "core/player/session/signin").id
        mark.start = action(world, "core/player/session/signin").id
        click(commands, button_in(world, "Hello!", "Sign out"))
        step("sign_out")

    elseif phase == "sign_out" and action(world, "core/player/session/signin") ~= nil
        and action(world, "core/player/session/signin").wish.sign_out and clock > 0.2 then
        local ask = action(world, "core/player/session/signin")
        local list = asks(world, "core/player/session/signin")
        T("O1_sign_out_asks_root", ask.wish.sign_out == true and not ask.wish.start and ask.id ~= mark.start)
        T("O1_in_place_of_the_sign_in_s_request", #list == 2 and standing(world, "core/player/session/signin").id == mark.standing,
            tostring(#list))
        click(commands, button_in(world, "GitHub", "Sign out"))
        step("github_sign_out")

    elseif phase == "github_sign_out" and action(world, "vault/github/signin") ~= nil and clock > 0.2 then
        local ask = action(world, "vault/github/signin")
        T("O2_github_s_sign_out_asks_root_too", ask.wish.sign_out == true and #asks(world, "vault/github/signin") == 2)
        reply(commands, ask, "vault/github/signin/reply", { pending = false })
        reply(commands, standing(world, "vault/github/signin"), "vault/github/signin/reply", { pending = false })
        step("github_signed_out")

    elseif phase == "github_signed_out" and button_in(world, "GitHub", "Sign in") ~= nil then
        T("O3_signed_out_the_row_offers_sign_in_again", not has_text(row_texts(world, "GitHub"), "zz-octo"))
        mark.reloads = reloads
        mark.button = buttons(world)[1]:id()
        reload()
        step("reloading")

    elseif phase == "reloading" and reloads > mark.reloads then
        step("reloaded")

    elseif phase == "reloaded" and clock > 2 then
        local b = buttons(world)[1]
        T("H1_a_reload_leaves_one_new_button_open", #buttons(world) == 1 and b:id() ~= mark.button and b:has("sidebar/button/open"),
            tostring(#buttons(world)))
        T("H1_and_one_panel", #views(world) == 1 and #world:query({ with = { "sidebar/profile/row" } }) == 3,
            #views(world) .. " views " .. #world:query({ with = { "sidebar/profile/row" } }) .. " rows")
        T("H1_its_asks_stay_none_doubled", #asks(world, "core/player/session/signin") == 2 and #asks(world, "vault/github/signin") == 2
            and standing(world, "core/player/session/signin").id == mark.standing,
            #asks(world, "core/player/session/signin") .. " " .. #asks(world, "vault/github/signin"))
        T("H1_the_rows_say_what_they_said", button_in(world, "GitHub", "Sign in") ~= nil
            and has_text(row_texts(world, "Hello!"), "Zz Player"))
        commands:entity(player):remove("sidebar/profile")
        step("removed")

    elseif phase == "removed" and clock > 1 then
        local left = #asks(world, "core/player/session/signin") + #asks(world, "vault/github/signin")
        T("U1_taken_off_its_asks_close", left == 0, tostring(left))
        T("U1_and_its_button_and_panel_go", #buttons(world) == 0 and #views(world) == 0
            and #world:query({ with = { "sidebar/profile/row" } }) == 0)
        phase = "done"
        finish()
    end

    if phase ~= "done" and clock > 15 then
        T("Z_reached_" .. phase, false, "stuck in phase '" .. phase .. "'")
        phase = "done"
        finish()
    end
end):in_set("zz/profile/suite")
