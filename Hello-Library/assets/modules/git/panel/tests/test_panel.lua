-- The GitHub panel's client half on a real player, driven headless, with root's replies stubbed:
-- this VM plays a client world on `github:zzpanel/world:main`, so root's replies, the flip asks'
-- answers and the server's answers are the suite's, and core's flip driver stays idle. The suite
-- adds the carrier as the server's sync brings it, and real clicks drive the panel.
--
-- A0  player/client adds no carrier of its own: the server's sync brings it; it adds
--     `sidebar/invites` and `git/collaborators` beside `sidebar/profile`
-- A1  the carrier asks root for the player's repositories once, with a sign-in ask under that ask
-- G1  before root answers, and signed out of GitHub, there is no "GitHub" button
-- I1  signing in asks again for the repositories root answered signed out
-- G2  ...and one "GitHub" button comes, in the bar
-- R1  the base repository is listed first and chosen, and its branches asked
-- B1  the first branch listed is chosen, though this world's own is listed too, and its commits asked
-- B3  choosing a branch asks its commits in place of the old ones
-- B4  a branch spelt with capitals keeps them in the target, where the owner and name are lowered
-- C1  on this world's own branch: "● Current", Pull, and a Portal that does nothing
-- K1  8 of root's 10 commits, the message's first line cut to 30
-- U1  Pull asks the world to pull its commit, and reads "⏳ Pulling…" while the ask is out
-- P1  a picker opens on a click, and opening one closes the other; the chosen option can't be clicked
-- P2  the wheel over an open picker's list scrolls it, 20 px a step, and no further than its content
-- P3  choosing a repository closes the picker, clears the branch and the commits, asks its branches
-- B2  another repository's first branch is chosen
-- S1  Switch asks core's flip for the target, in canonical lower case, and asks the commits again
-- S2  the label follows the flip ask: switching, then failed with the reason
-- O1  Portal asks the server on the request slot for a portal to the target, in canonical lower
--     case with the branch as it is, and spawns nothing itself
-- O2  the server's answer takes the ask back, so the next one is a change
-- O3  while the server's answer stands, a click asks nothing; once it is taken back, a click asks
-- L1  a portal here to the target that is locked says why, and stops saying it once unlocked
-- H1  a reload keeps the panel open, its rows, its state and its asks, none doubled
-- X1  the carrier taken off closes its asks, and its button and panel go
-- R2  with no base named, the first repository listed is chosen
-- I2  signing out asks again for the repositories root answered signed in
-- V1  ...and takes the button, closing the open panel
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local Scroll = require("bevy::picking::prelude::Scroll")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("GitPanelSuite")
local T = suite.assert_test

-- This VM plays a client world, which is never root. At root, each `vault/github` method takes a
-- stubbed reply on an ask that has a parent for the answer to its own HTTP call.
world_id = 7

local MOD_FILE = "assets/modules/git/panel/client/init.lua"
local HEAD_SHA = "1111111aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

local original
local function reload()
    original = original or read_file_bytes(MOD_FILE)
    write_file_bytes(MOD_FILE, original .. "\n-- zz reload\n")
end

local function finish()
    if original ~= nil then write_file_bytes(MOD_FILE, original) end
    suite.finish("GIT_PANEL")
end

local camera, player

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/world/status"] = { scope_key = "github:zzpanel/world:main", mode = "client", status = "ready" },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["git/world/head"] = { sha = HEAD_SHA }, ["zz/head"] = {}, ["core/net/sync"] = false })
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
        if tostring(event.path):find("git/panel/client/init.lua", 1, true) then reloads = reloads + 1 end
    end
end):in_set("zz/panel/reload_watch")

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

local function buttons(world)
    return world:query({ with = { "git/panel/button" }, optional = { "sidebar/button", "sidebar/button/open", "ChildOf" } })
end

local function views(world)
    return world:query({ with = { "git/panel/view" }, optional = { "sidebar/panel" } })
end

local function state_of(world)
    local me = world:query({ with = { "zz/player" }, optional = { "git/panel/state", "git/panel" } })[1]
    return me and me:get("git/panel/state") or {}
end

local function request_of(world)
    local me = world:query({ with = { "zz/player" }, optional = { "git/panel/request" } })[1]
    return me and me:get("git/panel/request")
end

-- The asks right under `parent`: `method` is the request's component; each as { id, wish, reply }.
local function asks(world, method, parent)
    parent = parent or player
    local out = {}
    for _, row in ipairs(world:query({
        iter_many = world:descendants(parent),
        with = { method, "Request", "ChildOf" },
        optional = { method .. "/reply" },
    })) do
        if row:get("ChildOf") == parent then
            out[#out + 1] = { id = row:id(), wish = row:get(method), reply = row:get(method .. "/reply") }
        end
    end
    return out
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

local function children_of(world, id)
    local node = world:query({ iter_many = { id }, optional = { "Children" } })[1]
    return node and node:get("Children") or {}
end

local function scroll_of(world)
    local view = views(world)[1]
    if view == nil then return nil end
    local s = world:query({ iter_many = world:descendants(view:id()), with = { "sidebar/panel/scroll" } })[1]
    return s and s:id()
end

-- Every text in the panel, as it reads on screen.
local function panel_texts(world)
    local scroll = scroll_of(world)
    return scroll and texts_under(world, scroll) or {}
end

local function has_text(list, text)
    for _, t in ipairs(list) do
        if t == text then return true end
    end
    return false
end

-- A picker by its label: its trigger, whether its list shows, its arrow and its options' texts.
local function picker(world, label)
    local scroll = scroll_of(world)
    for _, block in ipairs(scroll and children_of(world, scroll) or {}) do
        local list = texts_under(world, block)
        if list[1] == label then
            local out = { arrow = list[3], chosen = list[2], options = {} }
            for i = 4, #list do out.options[#out.options + 1] = list[i] end
            for _, part in ipairs(world:query({ iter_many = children_of(world, block), optional = { "Button", "ScrollPosition", "Node" } })) do
                if part:has("Button") then out.trigger = part:id() end
                if part:has("ScrollPosition") then
                    out.shown = part:get("Node").display ~= "None"
                    out.list = part:id()
                end
            end
            return out
        end
    end
    return nil
end

local function option(world, label, text)
    local p = picker(world, label)
    for _, row in ipairs(p and world:query({ iter_many = children_of(world, p.list), optional = { "Button" } }) or {}) do
        if texts_under(world, row:id())[1] == text then return row:has("Button") and row:id() or false end
    end
    return nil
end

-- The button under the panel labelled `label`.
local function button_labelled(world, label)
    local view = views(world)[1]
    for _, b in ipairs(view and world:query({ iter_many = world:descendants(view:id()), with = { "Button" } }) or {}) do
        if texts_under(world, b:id())[1] == label then return b:id() end
    end
    return nil
end

local function portals(world)
    return world:query({ with = { "scope/portal" }, optional = { "placement", "scope/portal/view", "core/net/sync", "scope/portal/locked" } })
end

local function flips(world)
    return world:query({ with = { "core/world/flip" }, optional = { "WorldShared", "core/net/sync" } })
end

local function reply(commands, id, name, value)
    commands:entity(id):insert({ [name] = value })
end

local function commits(n)
    local out = {}
    for i = 1, n do
        out[i] = {
            sha = string.format("c%06d", i),
            message = i == 1 and "Fix the very long thing that goes past thirty\nsecond line" or ("commit " .. i),
        }
    end
    return out
end

local phase, clock = "arrived", 0
local mark = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "arrived" and clock > 0.3 then
        commands:entity(player):insert({ ["core/net/local"] = {} })
        step("local")

    elseif phase == "local" and clock > 0.5 then
        local me = world:query({
            with = { "zz/player" },
            optional = { "git/panel", "sidebar/profile", "sidebar/invites", "git/collaborators" },
        })[1]
        T("A0_player_client_adds_no_carrier_of_its_own", me:has("sidebar/profile") and not me:has("git/panel"))
        T("A0_it_adds_the_invite_cards_and_the_collaborators_panel_beside_the_profile",
            me:has("sidebar/invites") and me:has("git/collaborators"))
        commands:entity(player):insert({ ["git/panel"] = {} })
        step("button")

    elseif phase == "button" and clock > 0.6 then
        T("G1_before_root_answers_there_is_no_github_button", #buttons(world) == 0, tostring(#buttons(world)))
        local repos = asks(world, "vault/github/repos")
        local signins = repos[1] and asks(world, "vault/github/signin", repos[1].id) or {}
        T("A1_the_carrier_asks_root_for_the_repositories_once", #repos == 1 and next(repos[1].wish) == nil,
            tostring(#repos))
        T("A1_with_a_sign_in_ask_under_that_ask", #signins == 1 and next(signins[1].wish) == nil, tostring(#signins))
        T("A1_and_nothing_else_yet", #asks(world, "vault/github/branches") == 0 and #asks(world, "vault/github/commits") == 0)
        reply(commands, repos[1].id, "vault/github/repos/reply", { error = "not signed in to GitHub" })
        reply(commands, signins[1].id, "vault/github/signin/reply", { pending = false })
        mark.repos = repos[1].id
        step("signed_out")

    elseif phase == "signed_out" and clock > 0.6 then
        T("G1_signed_out_there_is_no_github_button", #buttons(world) == 0, tostring(#buttons(world)))
        reply(commands, asks(world, "vault/github/signin", mark.repos)[1].id, "vault/github/signin/reply",
            { login = "zz-octo", pending = false })
        step("signed_in")

    elseif phase == "signed_in" and asks(world, "vault/github/repos")[1] ~= nil
        and asks(world, "vault/github/repos")[1].id ~= mark.repos and #buttons(world) > 0 and clock > 0.5 then
        local repos = asks(world, "vault/github/repos")
        local signins = asks(world, "vault/github/signin", repos[1].id)
        local b = buttons(world)[1]
        local bar = world:query({ with = { "sidebar/bar" } })[1]
        T("I1_signing_in_asks_again_for_what_root_answered_signed_out", #repos == 1 and repos[1].reply == nil
            and #signins == 1, #repos .. " " .. #signins)
        T("G2_signed_in_one_github_button_in_the_bar", #buttons(world) == 1 and b:get("ChildOf") == bar:id()
            and b:get("sidebar/button").title == "GitHub")
        reply(commands, signins[1].id, "vault/github/signin/reply", { login = "zz-octo", pending = false })
        reply(commands, repos[1].id, "vault/github/repos/reply", { repos = {
            { name = "Other-Repo", owner = "ZzOwner", default_branch = "main", is_base = false },
            { name = "world", owner = "zzpanel", default_branch = "main", is_base = true },
            { name = "third", owner = "zzpanel", default_branch = "main", is_base = false },
        } })
        commands:entity(player):insert({ ["sidebar/open"] = {} })
        click(commands, b:id())
        step("repos")

    elseif phase == "repos" and state_of(world).repo ~= nil and #asks(world, "vault/github/branches") == 1
        and #views(world) == 1 and picker(world, "REPOSITORY") ~= nil and #picker(world, "REPOSITORY").options == 3 then
        local p = picker(world, "REPOSITORY")
        local wish = asks(world, "vault/github/branches")[1].wish
        T("V0_the_title_is_github", views(world)[1]:get("sidebar/panel").title == "GitHub")
        T("R1_the_base_repository_is_chosen", state_of(world).repo == "zzpanel/world" and p.chosen == "world",
            tostring(state_of(world).repo))
        T("R1_and_listed_first", table.concat(p.options, "|") == "world|Other-Repo|third", table.concat(p.options, "|"))
        T("R1_and_its_branches_asked", wish.owner == "zzpanel" and wish.name == "world")
        T("P0_the_picker_starts_shut", p.arrow == "▼" and p.shown == false)
        reply(commands, asks(world, "vault/github/branches")[1].id, "vault/github/branches/reply",
            { branches = { "alpha", "main", "zeta" } })
        step("branches")

    elseif phase == "branches" and state_of(world).branch ~= nil and #asks(world, "vault/github/commits") == 1
        and button_labelled(world, "↗ Switch") ~= nil then
        local wish = asks(world, "vault/github/commits")[1].wish
        T("B1_the_first_branch_listed_is_chosen_though_this_world_s_own_is_listed", state_of(world).branch == "alpha",
            tostring(state_of(world).branch))
        T("B1_and_its_commits_asked", wish.owner == "zzpanel" and wish.name == "world" and wish.branch == "alpha")
        mark.commits = asks(world, "vault/github/commits")[1].id
        click(commands, option(world, "BRANCH", "main"))
        step("current")

    elseif phase == "current" and state_of(world).branch == "main" and #asks(world, "vault/github/commits") == 1
        and asks(world, "vault/github/commits")[1].id ~= mark.commits and button_labelled(world, "● Current") ~= nil then
        local c = asks(world, "vault/github/commits")
        local shown = panel_texts(world)
        T("B3_choosing_a_branch_asks_its_commits_in_place_of_the_old", c[1].wish.branch == "main", tostring(c[1].wish.branch))
        T("C1_on_this_world_s_branch_current_pull_and_portal", has_text(shown, "⭳ Pull") and has_text(shown, "🌀 Portal")
            and not has_text(shown, "↗ Switch"), table.concat(shown, "|"))
        reply(commands, asks(world, "vault/github/commits")[1].id, "vault/github/commits/reply", { commits = commits(10) })
        step("commits")

    elseif phase == "commits" and has_text(panel_texts(world), "RECENT COMMITS") then
        local shown = panel_texts(world)
        T("K1_eight_of_root_s_ten_commits", has_text(shown, "c000008") and not has_text(shown, "c000009"),
            table.concat(shown, "|"))
        T("K1_the_first_line_cut_to_thirty", has_text(shown, "Fix the very long thing tha...")
            and has_text(shown, "commit 8"))
        click(commands, button_labelled(world, "🌀 Portal"))
        click(commands, button_labelled(world, "⭳ Pull"))
        step("pull")

    elseif phase == "pull" and #world:query({ with = { "git/world/head/pull" } }) > 0
        and has_text(panel_texts(world), "⏳ Pulling…") and clock > 0.3 then
        local pulls = world:query({ with = { "git/world/head/pull" } })
        T("U1_pull_asks_the_world_to_pull_its_commit", #pulls == 1 and pulls[1]:get("git/world/head/pull").sha == HEAD_SHA)
        T("U1_and_reads_pulling_while_the_ask_is_out", not has_text(panel_texts(world), "⭳ Pull"))
        T("C1_the_portal_on_this_world_s_branch_does_nothing", #portals(world) == 0 and request_of(world) == nil)
        -- The server takes the ask and its copy goes, which despawns the client's.
        commands:entity(pulls[1]:id()):despawn()
        step("pulled")

    elseif phase == "pulled" and has_text(panel_texts(world), "⭳ Pull") then
        click(commands, picker(world, "REPOSITORY").trigger)
        step("repo_open")

    elseif phase == "repo_open" and picker(world, "REPOSITORY").shown then
        local repo, branch = picker(world, "REPOSITORY"), picker(world, "BRANCH")
        T("P1_a_click_opens_the_picker", repo.arrow == "▲" and branch.shown == false and branch.arrow == "▼")
        T("P1_the_chosen_option_can_t_be_clicked", option(world, "REPOSITORY", "world") == false
            and option(world, "REPOSITORY", "third") ~= nil)
        -- Headless, nothing lays the list out: it stands as Bevy's layout leaves a list taller than its
        -- 180 px, and the wheel step lands on it, as picking's bubbling from an option row does.
        mark.list = repo.list
        commands:entity(repo.list):insert({
            ComputedNode = { size = { x = 264, y = 180 }, content_size = { x = 264, y = 230 } },
        })
        step("wheel")

    elseif phase == "wheel" and clock > 0.2 then
        commands:trigger(Pointer[Scroll], {
            entity = mark.list,
            pointer_location = { target = { None = { width = 0, height = 0 } } },
            event = { unit = "Line", y = -2, hit = { camera = camera } },
        })
        step("wheeled")

    elseif phase == "wheeled" and clock > 0.3 then
        local list = world:query({ iter_many = { mark.list }, optional = { "ScrollPosition" } })[1]
        local at = list and list:get("ScrollPosition")
        T("P2_the_wheel_scrolls_an_open_picker_s_list", at ~= nil and at.y == 40, tostring(at and at.y))
        commands:trigger(Pointer[Scroll], {
            entity = mark.list,
            pointer_location = { target = { None = { width = 0, height = 0 } } },
            event = { unit = "Line", y = -5, hit = { camera = camera } },
        })
        step("wheeled_far")

    elseif phase == "wheeled_far" and clock > 0.3 then
        local list = world:query({ iter_many = { mark.list }, optional = { "ScrollPosition" } })[1]
        local at = list and list:get("ScrollPosition")
        T("P2_and_stops_at_the_end_of_its_content", at ~= nil and at.y == 50, tostring(at and at.y))
        click(commands, picker(world, "BRANCH").trigger)
        step("branch_open")

    elseif phase == "branch_open" and picker(world, "BRANCH").shown then
        local repo, branch = picker(world, "REPOSITORY"), picker(world, "BRANCH")
        T("P1_opening_one_picker_closes_the_other", repo.shown == false and repo.arrow == "▼" and branch.arrow == "▲")
        click(commands, picker(world, "REPOSITORY").trigger)
        step("repo_again")

    elseif phase == "repo_again" and picker(world, "REPOSITORY").shown and not picker(world, "BRANCH").shown then
        mark.branches = asks(world, "vault/github/branches")[1].id
        click(commands, option(world, "REPOSITORY", "Other-Repo"))
        step("chose")

    elseif phase == "chose" and state_of(world).repo == "ZzOwner/Other-Repo"
        and asks(world, "vault/github/branches")[1] ~= nil and asks(world, "vault/github/branches")[1].id ~= mark.branches
        and clock > 0.3 then
        local b = asks(world, "vault/github/branches")
        local repo = picker(world, "REPOSITORY")
        T("P3_choosing_a_repository_clears_the_branch", state_of(world).branch == nil and picker(world, "BRANCH").chosen == "(none)")
        T("P3_and_asks_its_branches_in_place_of_the_old", #b == 1 and b[1].wish.owner == "ZzOwner" and b[1].wish.name == "Other-Repo")
        T("P3_and_closes_the_commits", #asks(world, "vault/github/commits") == 0 and not has_text(panel_texts(world), "RECENT COMMITS"))
        T("P3_and_closes_the_picker", repo.shown == false and repo.arrow == "▼" and repo.chosen == "Other-Repo")
        reply(commands, b[1].id, "vault/github/branches/reply", { branches = { "Dev", "main" } })
        step("other_branches")

    elseif phase == "other_branches" and state_of(world).branch ~= nil and #asks(world, "vault/github/commits") == 1
        and button_labelled(world, "↗ Switch") ~= nil then
        local wish = asks(world, "vault/github/commits")[1].wish
        T("B2_another_repository_s_first_branch_is_chosen", state_of(world).branch == "Dev")
        T("B2_and_its_commits_asked", wish.owner == "ZzOwner" and wish.name == "Other-Repo" and wish.branch == "Dev")
        T("B2_another_branch_offers_no_pull", not has_text(panel_texts(world), "⭳ Pull"))
        mark.commits = asks(world, "vault/github/commits")[1].id
        click(commands, button_labelled(world, "↗ Switch"))
        step("switched")

    elseif phase == "switched" and #flips(world) > 0 and clock > 0.3 then
        local f = flips(world)
        local c = asks(world, "vault/github/commits")
        T("S1_switch_asks_core_s_flip_in_canonical_lower_case", #f == 1
            and f[1]:get("core/world/flip").scope:sub(1, 24) == "github:zzowner/other-rep", tostring(f[1]:get("core/world/flip").scope))
        T("B4_a_branch_spelt_with_capitals_keeps_them", #f == 1
            and f[1]:get("core/world/flip").scope == "github:zzowner/other-repo:Dev", tostring(f[1]:get("core/world/flip").scope))
        T("S1_the_ask_crosses_vms_never_the_wire", f[1]:has("WorldShared") and f[1]:get("core/net/sync") == false)
        T("S1_and_asks_the_commits_again", #c == 1 and c[1].id ~= mark.commits and c[1].wish.branch == "Dev")
        mark.flip = f[1]:id()
        commands:entity(mark.flip):insert({ ["core/world/flip"] = { scope = "github:zzowner/other-repo:Dev", status = "resolving" } })
        step("switching")

    elseif phase == "switching" and button_labelled(world, "⏳ Switching…") ~= nil then
        commands:entity(mark.flip):insert({ ["core/world/flip"] = {
            scope = "github:zzowner/other-repo:Dev", status = "failed", reason = "zz-refused",
        } })
        step("failed")

    elseif phase == "failed" and button_labelled(world, "⚠ zz-refused — retry") ~= nil then
        T("S2_the_label_follows_the_flip_ask", true)
        click(commands, button_labelled(world, "🌀 Portal"))
        step("portal")

    elseif phase == "portal" and request_of(world) ~= nil and clock > 0.3 then
        local ask = request_of(world)
        T("O1_portal_asks_the_server_for_a_portal_to_the_target_in_canonical_form", ask.op == "portal"
            and ask.target_sk == "github:zzowner/other-repo:Dev", tostring(ask.op) .. " " .. tostring(ask.target_sk))
        T("O1_and_spawns_nothing_itself", #portals(world) == 0, tostring(#portals(world)))
        commands:entity(player):insert({ ["git/panel/response"] = {
            op = "portal", scope = "github:zzowner/other-repo:Dev", status = "opened",
        } })
        step("answered")

    elseif phase == "answered" and request_of(world) ~= nil and request_of(world).op == nil and clock > 0.2 then
        T("O2_the_server_s_answer_takes_the_ask_back", next(request_of(world)) == nil)
        click(commands, button_labelled(world, "🌀 Portal"))
        step("standing")

    elseif phase == "standing" and clock > 0.3 then
        T("O3_while_the_answer_stands_a_click_asks_nothing", request_of(world) ~= nil and next(request_of(world)) == nil)
        -- The server takes its answer back once the ask is.
        commands:entity(player):insert({ ["git/panel/response"] = {} })
        step("cleared")

    elseif phase == "cleared" and clock > 0.3 then
        click(commands, button_labelled(world, "🌀 Portal"))
        step("asked_again")

    elseif phase == "asked_again" and request_of(world) ~= nil and request_of(world).op ~= nil then
        T("O3_once_it_is_taken_back_a_click_asks_again", request_of(world).target_sk == "github:zzowner/other-repo:Dev")
        -- The portal the server spawned, as its sync brings it here.
        mark.portal = commands:spawn({
            ["scope/portal"] = { target = "github:zzowner/other-repo:Dev" },
            ["scope/portal/locked"] = { reason = "zz-locked" },
            ["core/net/sync"] = false,
        }):id()
        step("locked")

    elseif phase == "locked" and has_text(panel_texts(world), "⚠ portal refused: zz-locked") then
        T("L1_a_locked_portal_to_the_target_says_why", true)
        commands:entity(mark.portal):remove("scope/portal/locked")
        step("unlocked")

    elseif phase == "unlocked" and not has_text(panel_texts(world), "⚠ portal refused: zz-locked") and clock > 0.3 then
        T("L1_and_stops_once_unlocked", true)
        commands:entity(mark.portal):despawn()
        step("settle")

    elseif phase == "settle" and clock > 0.5 then
        mark.texts = table.concat(panel_texts(world), "|")
        mark.button = buttons(world)[1]:id()
        mark.asks = {
            repos = asks(world, "vault/github/repos")[1].id,
            branches = asks(world, "vault/github/branches")[1].id,
            commits = asks(world, "vault/github/commits")[1].id,
        }
        mark.reloads = reloads
        reload()
        step("reloading")

    elseif phase == "reloading" and reloads > mark.reloads then
        step("reloaded")

    elseif phase == "reloaded" and clock > 2 then
        local b = buttons(world)[1]
        T("H1_a_reload_leaves_one_new_button_open", #buttons(world) == 1 and b:id() ~= mark.button and b:has("sidebar/button/open"),
            tostring(#buttons(world)))
        T("H1_and_one_panel_saying_what_it_said", #views(world) == 1 and table.concat(panel_texts(world), "|") == mark.texts,
            table.concat(panel_texts(world), "|"))
        local r, b2, c = asks(world, "vault/github/repos"), asks(world, "vault/github/branches"), asks(world, "vault/github/commits")
        T("H1_its_asks_stay_none_doubled", #r == 1 and #b2 == 1 and #c == 1 and r[1].id == mark.asks.repos
            and b2[1].id == mark.asks.branches and c[1].id == mark.asks.commits, #r .. " " .. #b2 .. " " .. #c)
        T("H1_its_state_stays", state_of(world).repo == "ZzOwner/Other-Repo" and state_of(world).branch == "Dev"
            and state_of(world).open == true)
        commands:entity(player):remove("git/panel")
        step("removed")

    elseif phase == "removed" and clock > 1 then
        local left = #asks(world, "vault/github/repos") + #asks(world, "vault/github/branches") + #asks(world, "vault/github/commits")
        T("X1_taken_off_its_asks_close", left == 0, tostring(left))
        T("X1_and_its_button_and_panel_go", #buttons(world) == 0 and #views(world) == 0
            and #world:query({ with = { "git/panel/row" } }) == 0)
        T("X1_the_flip_ask_is_the_player_s_and_stays", #flips(world) == 1)
        commands:entity(player):insert({ ["git/panel"] = {} })
        step("readded")

    elseif phase == "readded" and asks(world, "vault/github/repos")[1] ~= nil
        and asks(world, "vault/github/signin", asks(world, "vault/github/repos")[1].id)[1] ~= nil and clock > 0.3 then
        local repos = asks(world, "vault/github/repos")[1]
        reply(commands, asks(world, "vault/github/signin", repos.id)[1].id, "vault/github/signin/reply", { login = "zz-octo", pending = false })
        reply(commands, repos.id, "vault/github/repos/reply", { repos = {
            { name = "b-repo", owner = "zz", default_branch = "main" },
            { name = "a-repo", owner = "zz", default_branch = "main" },
        } })
        step("first")

    elseif phase == "first" and state_of(world).repo ~= nil and #buttons(world) == 1 and clock > 0.5 then
        T("R2_with_no_base_named_the_first_listed_is_chosen", state_of(world).repo == "zz/b-repo", tostring(state_of(world).repo))
        click(commands, buttons(world)[1]:id())
        step("reopened")

    elseif phase == "reopened" and #views(world) == 1 and state_of(world).open and clock > 0.3 then
        mark.repos = asks(world, "vault/github/repos")[1].id
        reply(commands, asks(world, "vault/github/signin", mark.repos)[1].id, "vault/github/signin/reply", { pending = false })
        step("signed_off")

    elseif phase == "signed_off" and asks(world, "vault/github/repos")[1] ~= nil
        and asks(world, "vault/github/repos")[1].id ~= mark.repos and clock > 0.5 then
        local repos = asks(world, "vault/github/repos")
        T("I2_signing_out_asks_again_for_what_root_answered_signed_in", #repos == 1 and repos[1].reply == nil
            and #asks(world, "vault/github/signin", repos[1].id) == 1)
        T("V1_signing_out_takes_the_button", #buttons(world) == 0, tostring(#buttons(world)))
        T("V1_and_closes_the_panel", #views(world) == 0 and state_of(world).open == false,
            #views(world) .. " " .. tostring(state_of(world).open))
        phase = "done"
        finish()
    end

    if phase ~= "done" and clock > 15 then
        T("Z_reached_" .. phase, false, "stuck in phase '" .. phase .. "'")
        phase = "done"
        finish()
    end
end):in_set("zz/panel/suite")
