-- The GitHub panel's SESSIONS rows on a real player, driven headless, with root's replies stubbed:
-- this VM plays a client world on `github:zzpanel/world:main`, so root's replies, root's presences
-- (mirrors stood in with `WorldMirror = { world_id = 0 }`) and other worlds' rows are the suite's.
-- Real clicks drive the rows.
--
-- W1  the header: "Loading sessions…" before root answers, the error, then "No visible sessions"
-- W2  a row reads its scope without `github:`, cut to 24, "● " on this world's own, and the counts
-- W3  "^" on another row asks core's flip for that row's scope
-- W6  with no grants on this client's own net there is no "■ Stop for everyone"; with "writer", it is on
--     the rows of this world's repository, and not on another repository's row
-- W4  "■ Stop for everyone" arms as "sure?"; a second click asks root for one despawn; an arm lapses after 5 s
-- W5  a refused despawn says why on its row, and 10 s later its ask goes
-- W7  a world root's sessions reply says it holds is listed with "background" or "playing", "■ Stop here"
--     and Restart, a held world not on the registry's list getting a row of its own; nothing else (a
--     presence of root's, a world's row) makes a world held; a row neither held nor stoppable for
--     everyone has no Stop
-- W11 one Stop per row: with "writer", a held row of this world's repository has "■ Stop for everyone"
--     and no "■ Stop here"; the grants removed, "■ Stop for everyone" goes and "■ Stop here" comes back
-- W8  "■ Stop here" asks root to stop the world here, in place of an earlier ask; each refusal in the
--     row's own words; done closes the ask
-- W9  Restart asks root, reads "..." while restarting, and done closes the ask
-- W10 a portal this player placed here has Close, which despawns it; one being placed or another
--     player's has none
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")

local suite = helpers.create_suite("GitPanelWorldsSuite")
local T = suite.assert_test

-- This VM plays a client world, which is never root.
world_id = 7

local HERE = "github:zzpanel/world:main"
local LONG = "github:zzpanel/world:a-very-long-branch-name"
local OTHER = "github:zzother/elsewhere:main"
local BG = "github:zzpanel/world:bg"
local FORGED = "github:zzpanel/world:forged"
local GONE = "github:zzpanel/world:gone"
local DOOR = "github:zzpanel/world:door"

local camera, player

-- This client's world net, unconnected: what the client owns here is in its `core/net/owns`.
local own_net

app:add_systems(Startup, { Commands }, function(commands)
    own_net = commands:spawn({
        ["core/world/net"] = { mode = "client" },
        ["core/net"] = { mode = "client", name = "zzpanel" },
        ["core/net/sync"] = false,
    }):id()
    commands:spawn({
        ["core/world/status"] = { scope_key = HERE, scope_root = "github:zzpanel/world", mode = "client", status = "ready" },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["ui/theme/dark"] = {} })
    camera = commands:spawn({ ["zz/camera"] = {} }):id()
    player = commands:spawn({
        ["zz/player"] = {},
        player = { client_id = 1, spawn_index = 1 },
        ["core/net/sync"] = false,
    }):id()
end)

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = camera } },
    })
end

local function views(world)
    return world:query({ with = { "git/panel/view" }, optional = { "sidebar/panel" } })
end

local function state_of(world)
    local me = world:query({ with = { "zz/player" }, optional = { "git/panel/state" } })[1]
    return me and me:get("git/panel/state") or {}
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

local function panel_texts(world)
    local scroll = scroll_of(world)
    return scroll and texts_under(world, scroll) or {}
end

local function count(list, text)
    local n = 0
    for _, t in ipairs(list) do
        if t == text then n = n + 1 end
    end
    return n
end
local function has_text(list, text) return count(list, text) > 0 end

-- The top-level rows in order, each as { id, texts }.
local function rows(world)
    local scroll = scroll_of(world)
    local out = {}
    for _, id in ipairs(scroll and children_of(world, scroll) or {}) do
        out[#out + 1] = { id = id, texts = texts_under(world, id) }
    end
    return out
end

-- The button labelled `label` in the row whose first text is `first`, or in the row `offset` after
-- it (a held world's Stop and Restart sit on the line under its row).
local function button_in(world, first, label, offset)
    local list = rows(world)
    for i, r in ipairs(list) do
        if r.texts[1] == first then
            local target = list[i + (offset or 0)]
            for _, b in ipairs(target and world:query({ iter_many = world:descendants(target.id), with = { "Button" } }) or {}) do
                if texts_under(world, b:id())[1] == label then return b:id() end
            end
        end
    end
    return nil
end

-- The texts of the row whose first text is `first`, and of the one after it.
local function row_texts(world, first, offset)
    local list = rows(world)
    for i, r in ipairs(list) do
        if r.texts[1] == first then
            local target = list[i + (offset or 0)]
            return target and target.texts or {}
        end
    end
    return {}
end

local function reply(commands, id, name, value)
    commands:entity(id):insert({ [name] = value })
end

local function flips(world)
    return world:query({ with = { "core/world/flip" } })
end

local function sessions_ask(world) return asks(world, "core/registry/sessions")[1] end

local LIST = {
    { scope = HERE, scope_root = "github:zzpanel/world", active = 2, background = 1, since = "zz" },
    { scope = LONG, scope_root = "github:zzpanel/world", active = 0, background = 3, since = "zz" },
    { scope = OTHER, scope_root = "github:zzother/elsewhere", active = 1, background = 0, since = "zz" },
}

local phase, clock = "arrived", 0
local mark = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local shown = panel_texts(world)

    if phase == "arrived" and clock > 0.3 then
        commands:entity(player):insert({ ["core/net/owner"] = own_net, ["git/panel"] = {} })
        step("asked")

    elseif phase == "asked" and asks(world, "vault/github/repos")[1] ~= nil and sessions_ask(world) ~= nil and clock > 0.3 then
        local repos = asks(world, "vault/github/repos")[1]
        local gh = asks(world, "vault/github/signin", repos.id)[1]
        T("W0_the_carrier_asks_root_for_the_sessions_once_with_no_site_sign_in_ask",
            #asks(world, "core/registry/sessions") == 1 and next(sessions_ask(world).wish) == nil
            and #asks(world, "core/player/session/signin", sessions_ask(world).id) == 0,
            string.format("sessions=%d signin under it=%d", #asks(world, "core/registry/sessions"),
                #asks(world, "core/player/session/signin", sessions_ask(world).id)))
        reply(commands, gh.id, "vault/github/signin/reply", { login = "zz-octo", pending = false })
        reply(commands, repos.id, "vault/github/repos/reply", { repos = {
            { name = "world", owner = "zzpanel", default_branch = "main", is_base = true },
        } })
        step("button")

    elseif phase == "button" and world:query({ with = { "git/panel/button" } })[1] ~= nil and clock > 0.3 then
        commands:entity(player):insert({ ["sidebar/open"] = {} })
        click(commands, world:query({ with = { "git/panel/button" } })[1]:id())
        step("loading")

    elseif phase == "loading" and has_text(shown, "SESSIONS") and clock > 0.3 then
        T("W1_before_root_answers_loading_sessions", has_text(shown, "Loading sessions…"), (table.concat(shown, "|"):gsub("[^%g%s]+", "?")))
        reply(commands, sessions_ask(world).id, "core/registry/sessions/reply", { sessions = {}, error = "registry-unreachable" })
        step("error")

    elseif phase == "error" and has_text(shown, "⚠ sessions unavailable (registry-unreachable)") then
        T("W1_an_error_says_so", not has_text(shown, "No visible sessions"))
        reply(commands, sessions_ask(world).id, "core/registry/sessions/reply", { sessions = {} })
        step("empty")

    elseif phase == "empty" and has_text(shown, "No visible sessions") then
        T("W1_an_empty_list_says_so", not has_text(shown, "Loading sessions…"), (table.concat(shown, "|"):gsub("[^%g%s]+", "?")))
        reply(commands, sessions_ask(world).id, "core/registry/sessions/reply", { sessions = LIST })
        step("listed")

    elseif phase == "listed" and has_text(shown, "● zzpanel/world:main") and clock > 0.3 then
        T("W2_a_row_reads_its_scope_cut_to_24", has_text(shown, "zzpanel/world:a-very-...")
            and has_text(shown, "zzother/elsewhere:main"), (table.concat(shown, "|"):gsub("[^%g%s]+", "?")))
        T("W2_the_current_one_is_marked_and_the_counts_read", has_text(shown, "2▸ 1◌") and has_text(shown, "0▸ 3◌"))
        T("W3_switch_on_every_row_but_the_current", count(shown, "^") == 2, tostring(count(shown, "^")))
        T("W6_with_no_grants_no_stop_for_everyone", count(shown, "■ Stop for everyone") == 0, tostring(count(shown, "■ Stop for everyone")))
        -- The grants as this world's server syncs them onto this client's own net entity.
        commands:entity(own_net):insert({ ["core/permission/grants"] = { names = { "writer" } } })
        step("granted")

    elseif phase == "granted" and has_text(shown, "■ Stop for everyone") and clock > 0.3 then
        T("W6_with_writer_stop_for_everyone_only_on_this_world_s_repository", count(shown, "■ Stop for everyone") == 2
            and has_text(row_texts(world, "● zzpanel/world:main"), "■ Stop for everyone")
            and has_text(row_texts(world, "zzpanel/world:a-very-..."), "■ Stop for everyone")
            and not has_text(row_texts(world, "zzother/elsewhere:main"), "■ Stop for everyone"), (table.concat(shown, "|"):gsub("[^%g%s]+", "?")))
        click(commands, button_in(world, "zzpanel/world:a-very-...", "^"))
        step("flipped")

    elseif phase == "flipped" and #flips(world) > 0 and clock > 0.3 then
        local f = flips(world)
        T("W3_switch_asks_the_flip_for_that_row", #f == 1 and f[1]:get("core/world/flip").scope == LONG,
            tostring(#f))
        click(commands, button_in(world, "zzpanel/world:a-very-...", "■ Stop for everyone"))
        step("armed")

    elseif phase == "armed" and has_text(shown, "sure?") then
        T("W4_a_first_click_arms", state_of(world).armed ~= nil and state_of(world).armed.scope == LONG
            and #asks(world, "core/registry/despawn") == 0)
        click(commands, button_in(world, "zzpanel/world:a-very-...", "sure?"))
        step("confirmed")

    elseif phase == "confirmed" and #asks(world, "core/registry/despawn") > 0 and clock > 0.3 then
        local d = asks(world, "core/registry/despawn")
        T("W4_a_second_click_asks_root_for_one_despawn", #d == 1 and d[1].wish.scope == LONG
            and state_of(world).armed == nil, tostring(#d))
        T("W4_and_reads_dots_while_asked", has_text(row_texts(world, "zzpanel/world:a-very-..."), "..."), (table.concat(shown, "|"):gsub("[^%g%s]+", "?")))
        mark.despawn = d[1].id
        click(commands, button_in(world, "● zzpanel/world:main", "■ Stop for everyone"))
        step("armed_here")

    elseif phase == "armed_here" and state_of(world).armed ~= nil and clock > 0.2 then
        -- The arm's clock moved back past its window.
        local s = state_of(world)
        commands:entity(player):insert({ ["git/panel/state"] = { open = s.open, repo = s.repo, branch = s.branch,
            armed = { scope = s.armed.scope, at = s.armed.at - 6 } } })
        step("lapsed")

    elseif phase == "lapsed" and clock > 0.5 then
        T("W4_an_arm_lapses_after_5_s", state_of(world).armed == nil
            and has_text(row_texts(world, "● zzpanel/world:main"), "■ Stop for everyone"), tostring(state_of(world).armed))
        reply(commands, mark.despawn, "core/registry/despawn/reply", { status = "refused", reason = "zz-no" })
        step("refused")

    elseif phase == "refused" and has_text(shown, "⚠ despawn refused: zz-no") and clock > 0.2 then
        T("W5_a_refused_despawn_says_why_on_its_row",
            (state_of(world).refused or {})[LONG] ~= nil and #asks(world, "core/registry/despawn") == 1)
        local s = state_of(world)
        commands:entity(player):insert({ ["git/panel/state"] = { open = s.open, repo = s.repo, branch = s.branch,
            refused = { [LONG] = s.refused[LONG] - 11 } } })
        step("expired")

    elseif phase == "expired" and clock > 0.5 then
        T("W5_and_10_s_later_its_ask_goes", #asks(world, "core/registry/despawn") == 0
            and not has_text(shown, "⚠ despawn refused: zz-no") and next(state_of(world).refused or {}) == nil,
            tostring(#asks(world, "core/registry/despawn")))
        -- Root says what it holds on the sessions reply. A presence of root's for a world it doesn't
        -- list, with that world's row here, is no word that it holds it.
        reply(commands, sessions_ask(world).id, "core/registry/sessions/reply", { sessions = LIST, held = {
            { scope = BG, playing = false }, { scope = HERE, playing = true },
        } })
        commands:spawn({ ["core/world/presence"] = { scope_key = GONE, observer = true },
            WorldMirror = { world_id = 0 }, ["core/net/sync"] = false })
        commands:spawn({ ["core/world/status"] = { scope_key = GONE, mode = "client", status = "ready" },
            WorldMirror = { world_id = 9 }, ["core/net/sync"] = false })
        step("held")

    elseif phase == "held" and has_text(shown, "zzpanel/world:bg") and clock > 0.3 then
        T("W7_a_background_world_has_its_own_row_with_stop_here_and_restart",
            has_text(row_texts(world, "zzpanel/world:bg", 1), "background")
            and has_text(row_texts(world, "zzpanel/world:bg", 1), "■ Stop here")
            and has_text(row_texts(world, "zzpanel/world:bg", 1), "↻ Restart"), (table.concat(shown, "|"):gsub("[^%g%s]+", "?")))
        T("W7_the_world_played_reads_playing", has_text(row_texts(world, "● zzpanel/world:main", 1), "playing"), (table.concat(shown, "|"):gsub("[^%g%s]+", "?")))
        T("W7_only_root_s_held_list_says_a_world_is_held", not has_text(shown, "zzpanel/world:gone"))
        T("W7_a_row_neither_held_nor_stoppable_for_everyone_has_no_stop",
            not has_text(row_texts(world, "zzother/elsewhere:main"), "■ Stop for everyone")
            and not has_text(row_texts(world, "zzother/elsewhere:main", 1), "■ Stop here"))
        T("W11_a_held_row_of_this_repository_with_writer_has_one_stop_for_everyone",
            has_text(row_texts(world, "● zzpanel/world:main"), "■ Stop for everyone")
            and has_text(row_texts(world, "● zzpanel/world:main", 1), "playing")
            and not has_text(row_texts(world, "● zzpanel/world:main", 1), "■ Stop here")
            and has_text(row_texts(world, "● zzpanel/world:main", 1), "↻ Restart"), (table.concat(shown, "|"):gsub("[^%g%s]+", "?")))
        commands:entity(own_net):remove("core/permission/grants")
        step("ungranted")

    elseif phase == "ungranted" and not has_text(shown, "■ Stop for everyone") and clock > 0.3 then
        T("W11_the_grants_removed_stop_for_everyone_goes_and_stop_here_comes_back",
            count(shown, "■ Stop for everyone") == 0 and has_text(row_texts(world, "● zzpanel/world:main", 1), "■ Stop here"),
            (table.concat(shown, "|"):gsub("[^%g%s]+", "?")))
        click(commands, button_in(world, "● zzpanel/world:main", "■ Stop here", 1))
        step("stop_here")

    elseif phase == "stop_here" and #asks(world, "core/world/unload") > 0 and clock > 0.3 then
        local u = asks(world, "core/world/unload")
        T("W8_stop_asks_root_to_stop_the_world_here", #u == 1 and u[1].wish.scope == HERE)
        T("W8_and_reads_dots_until_root_answers", has_text(row_texts(world, "● zzpanel/world:main", 1), "..."))
        reply(commands, u[1].id, "core/world/unload/reply", { status = "refused", reason = "playing" })
        step("playing")

    elseif phase == "playing" and has_text(shown, "⚠ can't stop the world you are in: switch first") then
        T("W8_playing_in_the_row_s_own_words", true)
        click(commands, button_in(world, "zzpanel/world:bg", "■ Stop here", 1))
        step("stop_bg")

    elseif phase == "stop_bg" and #asks(world, "core/world/unload") == 2 and clock > 0.3 then
        local bg
        for _, u in ipairs(asks(world, "core/world/unload")) do
            if u.wish.scope == BG then bg = u end
        end
        reply(commands, bg.id, "core/world/unload/reply", { status = "refused", reason = "watched" })
        mark.unload = bg.id
        step("watched")

    elseif phase == "watched" and has_text(shown, "⚠ can't stop it: a portal looks at it") then
        click(commands, button_in(world, "zzpanel/world:bg", "■ Stop here", 1))
        step("stop_again")

    elseif phase == "stop_again" and clock > 0.3 then
        local bg = {}
        for _, u in ipairs(asks(world, "core/world/unload")) do
            if u.wish.scope == BG then bg[#bg + 1] = u end
        end
        T("W8_a_second_stop_asks_in_place_of_the_first", #bg == 1 and bg[1].id ~= mark.unload, tostring(#bg))
        reply(commands, bg[1].id, "core/world/unload/reply", { status = "done" })
        step("stopped")

    elseif phase == "stopped" and clock > 0.5 then
        local bg = 0
        for _, u in ipairs(asks(world, "core/world/unload")) do
            if u.wish.scope == BG then bg = bg + 1 end
        end
        T("W8_done_closes_the_ask", bg == 0, tostring(bg))
        click(commands, button_in(world, "zzpanel/world:bg", "↻ Restart", 1))
        step("restart")

    elseif phase == "restart" and #asks(world, "core/world/restart") > 0 and clock > 0.3 then
        local r = asks(world, "core/world/restart")
        T("W9_restart_asks_root", #r == 1 and r[1].wish.scope == BG)
        reply(commands, r[1].id, "core/world/restart/reply", { status = "restarting" })
        mark.restart = r[1].id
        step("restarting")

    elseif phase == "restarting" and clock > 0.5 then
        T("W9_and_reads_dots_while_restarting", has_text(row_texts(world, "zzpanel/world:bg", 1), "...")
            and not has_text(row_texts(world, "zzpanel/world:bg", 1), "↻ Restart"))
        reply(commands, mark.restart, "core/world/restart/reply", { status = "done" })
        step("restarted")

    elseif phase == "restarted" and clock > 0.5 then
        T("W9_done_closes_the_ask", #asks(world, "core/world/restart") == 0
            and has_text(row_texts(world, "zzpanel/world:bg", 1), "↻ Restart"))
        mark.mine = commands:spawn({ ["scope/portal"] = { target = DOOR }, ["core/net/owner"] = own_net, ["core/net/sync"] = false }):id()
        commands:spawn({ ["scope/portal"] = { target = "github:zzpanel/world:placing" }, ["core/net/owner"] = own_net,
            placement = {}, ["core/net/sync"] = false })
        commands:spawn({ ["scope/portal"] = { target = "github:zzpanel/world:theirs" }, ["core/net/sync"] = false })
        step("portals")

    elseif phase == "portals" and has_text(shown, "PORTALS") and clock > 0.3 then
        T("W10_a_portal_this_player_placed_has_close", has_text(shown, "◎ zzpanel/world:door") and count(shown, "Close") == 1
            and not has_text(shown, "◎ zzpanel/world:placing") and not has_text(shown, "◎ zzpanel/world:theirs"),
            (table.concat(shown, "|"):gsub("[^%g%s]+", "?")))
        click(commands, button_in(world, "◎ zzpanel/world:door", "Close"))
        step("closed")

    elseif phase == "closed" and clock > 0.5 then
        T("W10_close_despawns_it", world:get_entity(mark.mine) == nil and #world:query({ with = { "scope/portal" } }) == 2
            and not has_text(shown, "PORTALS"), tostring(#world:query({ with = { "scope/portal" } })))
        phase = "done"
        suite.finish("GIT_PANEL_WORLDS")
    end

    if phase ~= "done" and clock > 15 then
        T("Z_reached_" .. phase, false, "stuck in phase '" .. phase .. "'; " .. (table.concat(shown, "|"):gsub("[^%g%s]+", "?")))
        phase = "done"
        suite.finish("GIT_PANEL_WORLDS")
    end
end):in_set("zz/panel_worlds/suite")
