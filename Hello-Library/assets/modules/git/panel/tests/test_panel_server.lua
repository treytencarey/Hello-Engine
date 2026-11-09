-- --host
-- git/panel's server half, headless, on a world's server. The owner's ask arrives as the net server
-- writes it, `git/panel/request` on the owner's carrier, which carries `core/net/owner`; what the
-- server answers and spawns is read back here. One carrier is a real player, set up by
-- `player/server`.
--
--   PS1 `player/server` gives a player `git/panel`, which declares its own sync to the owner, and the
--       request slot (client, owner) and the answer (server, owner) on the player's sync
--   PS2 a portal ask opens one portal, at the asker, for the asker to place, owned by it on the net,
--       with the sync every client needs; it is answered "opened"
--   PS3 the owner taking its ask back takes the answer back
--   PS4 an ask for this world's own scope opens nothing, answered "failed"
--   PS5 a target that is not a string, empty or too long opens nothing, answered "failed"
--   PS6 an owner holds at most 8 portals here, counting the one it opened; another owner can still
--       open one
--   PS7 taking `git/panel` off a carrier that stays takes the two sync entries this half added
--   PS8 a reload of this half keeps the portals it opened: they are the world's, not the file's
--   PS9 a `drop_portal` ask opens a portal standing 3 m ahead of the asker (its back(), on the ground
--       plane), placed, its Transform the server's, answered with op `drop_portal`
--   PS10 ...though the answer to a `portal` ask for the same target still stands
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("GitPanelServerSuite")
local T = suite.assert_test

local HERE = "github:zzpanelsrv/here:main"
local OTHER = "github:zzpanelsrv/other:Feature-X"
local MOD_FILE = "assets/modules/git/panel/server/init.lua"

local original
local function reload()
    original = original or read_file_bytes(MOD_FILE)
    write_file_bytes(MOD_FILE, original .. "\n-- zz reload\n")
end

local function finish()
    if original ~= nil then write_file_bytes(MOD_FILE, original) end
    suite.finish("GitPanelServerSuite")
end

local reloads = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("git/panel/server/init.lua", 1, true) then reloads = reloads + 1 end
    end
end):in_set("zz/panel_server_reload_watch")

app:add_systems(Startup, { Commands }, function(commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/world/status"] = { scope_key = HERE, mode = "server", status = "ready" },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
end)

local function carrier(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/carrier" },
        optional = { "git/panel", "git/panel/request", "git/panel/response", "core/net/sync" },
    })) do
        if e:get("zz/carrier").name == name then return e end
    end
end

local function answer_of(world, name)
    local c = carrier(world, name)
    return c and c:has("git/panel/response") and c:get("git/panel/response") or {}
end

local function portals(world, client_id)
    local out = {}
    for _, p in ipairs(world:query({
        with = { "scope/portal", "core/net/owner" },
        optional = { "scope/portal/view", "placement", "Transform", "core/net/sync", "core/script/owner", "zz/held" },
    })) do
        if client_id == nil or p:get("core/net/owner").client_id == client_id then out[#out + 1] = p end
    end
    return out
end

local function ask(commands, world, name, request)
    commands:entity(carrier(world, name):id()):insert({ ["git/panel/request"] = request })
end

local phase, clock = "spawn", 0
local table_refused = false
local mark_reloads = 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({
            player = { client_id = 5, spawn_index = 0 },
            Transform = { translation = { x = 0, y = 0, z = 0 } },
            ["core/net/owner"] = { client_id = 5 },
            ["core/net/sync"] = { Transform = { authority = "client", reliable = false } },
            ["zz/carrier"] = { name = "player" },
        })
        for _, c in ipairs({ { "seven", 7, 4 }, { "eight", 8, -4 } }) do
            commands:spawn({
                ["git/panel"] = {},
                -- Turned a quarter about Y, so ahead (+Z turned) is +X.
                Transform = {
                    translation = { x = c[3], y = 1, z = 2 },
                    rotation = { x = 0, y = 0.70710678, z = 0, w = 0.70710678 },
                },
                ["core/net/owner"] = { client_id = c[2] },
                ["core/net/sync"] = {},
                ["zz/carrier"] = { name = c[1] },
            })
        end
        step("spawned")

    elseif phase == "spawned" and clock > 0.5 then
        local p = carrier(world, "player")
        local sync = p:get("core/net/sync") or {}
        local own, req, resp = sync["git/panel"], sync["git/panel/request"], sync["git/panel/response"]
        T("PS1_player_server_gives_a_player_git_panel", p:has("git/panel"), "")
        T("PS1_it_syncs_from_the_server_to_its_owner", own ~= nil and own.authority == "server" and own.target == "owner",
            tostring(own and own.authority))
        T("PS1_with_the_slot_from_the_owner_and_the_answer_to_it",
            req ~= nil and req.authority == "client" and req.target == "owner"
                and resp ~= nil and resp.authority == "server" and resp.target == "owner", "")
        ask(commands, world, "seven", { op = "portal", target_sk = OTHER })
        step("asked")

    elseif phase == "asked" and answer_of(world, "seven").status ~= nil and clock > 0.2 then
        local mine = portals(world, 7)
        local p = mine[1]
        local sync = p and p:get("core/net/sync") or {}
        local at = p and p:get("Transform").translation
        local said = answer_of(world, "seven")
        T("PS2_a_portal_ask_opens_one_portal_to_the_target", #portals(world) == 1 and #mine == 1
            and p:get("scope/portal").target == OTHER and p:get("scope/portal/view").mode == "3d",
            tostring(#portals(world)))
        T("PS2_at_the_asker_for_it_to_place", p ~= nil and p:has("placement") and at.x == 4 and at.y == 1 and at.z == 2, "")
        T("PS2_owned_by_the_asker_on_the_net", p ~= nil and p:get("core/net/owner").client_id == 7, "")
        T("PS2_with_the_sync_every_client_needs",
            sync.placement and sync.placement.authority == "client"
                and sync.Transform and sync.Transform.authority == "client" and sync.Transform.reliable == false
                and sync["scope/portal"] and sync["scope/portal"].authority == "server" and sync["scope/portal"].target == nil
                and sync["scope/portal/view"] and sync["scope/portal/view"].authority == "server"
                and sync["scope/portal/hosted"] and sync["scope/portal/hosted"].authority == "server", "")
        T("PS2_answered_opened", said.op == "portal" and said.scope == OTHER and said.status == "opened",
            tostring(said.status))
        -- What sidebar/invites writes, while the answer to the panel's ask still stands.
        ask(commands, world, "seven", { op = "drop_portal", target_sk = OTHER })
        step("dropped")

    elseif phase == "dropped" and answer_of(world, "seven").op == "drop_portal" and clock > 0.2 then
        local placed = nil
        for _, p in ipairs(portals(world, 7)) do
            if not p:has("placement") then placed = p end
        end
        local at = placed and placed:get("Transform").translation
        local sync = placed and placed:get("core/net/sync") or {}
        local said = answer_of(world, "seven")
        T("PS9_drop_portal_stands_a_portal_3_m_ahead_of_the_asker", placed ~= nil and #portals(world, 7) == 2
            and math.abs(at.x - 7) < 0.01 and math.abs(at.y - 1) < 0.01 and math.abs(at.z - 2) < 0.01,
            at and string.format("%.2f %.2f %.2f", at.x, at.y, at.z) or "none")
        T("PS9_placed_its_transform_the_server_s", placed ~= nil and placed:get("scope/portal").target == OTHER
            and sync.placement == nil and sync.Transform and sync.Transform.authority == "server"
            and sync["scope/portal"] and sync["scope/portal/hosted"] and placed:get("core/net/owner").client_id == 7, "")
        T("PS9_answered_with_its_op", said.scope == OTHER and said.status == "opened", tostring(said.status))
        T("PS10_though_the_portal_ask_s_answer_stood", placed ~= nil, "")
        ask(commands, world, "seven", {})
        step("taken_back")

    elseif phase == "taken_back" and clock > 0.3 then
        T("PS3_taking_the_ask_back_takes_the_answer_back", next(answer_of(world, "seven")) == nil
            and carrier(world, "seven"):has("git/panel/response"), "")
        ask(commands, world, "seven", { op = "portal", target_sk = HERE })
        step("own")

    elseif phase == "own" and answer_of(world, "seven").status ~= nil and clock > 0.2 then
        local said = answer_of(world, "seven")
        T("PS4_this_world_s_own_scope_opens_nothing", #portals(world) == 2 and said.status == "failed"
            and said.message == "this world's own scope" and said.scope == HERE, tostring(said.message))
        ask(commands, world, "seven", {})
        step("own_back")

    elseif phase == "own_back" and next(answer_of(world, "seven")) == nil then
        ask(commands, world, "seven", { op = "portal", target_sk = { owner = "zz" } })
        step("table")

    elseif phase == "table" and answer_of(world, "seven").status ~= nil and clock > 0.2 then
        local said = answer_of(world, "seven")
        table_refused = said.status == "failed" and said.message == "not a scope key" and said.scope == nil
        ask(commands, world, "seven", {})
        step("table_back")

    elseif phase == "table_back" and next(answer_of(world, "seven")) == nil then
        ask(commands, world, "seven", { op = "portal", target_sk = string.rep("z", 513) })
        step("long")

    elseif phase == "long" and answer_of(world, "seven").status ~= nil and clock > 0.2 then
        local said = answer_of(world, "seven")
        T("PS5_a_target_that_is_not_a_string_or_too_long_opens_nothing", table_refused and #portals(world) == 2
            and said.status == "failed" and said.message == "not a scope key", tostring(said.message))
        ask(commands, world, "seven", {})
        -- Seven held here before, which the cap counts with the one it opened.
        for i = 1, 6 do
            commands:spawn({
                ["scope/portal"] = { target = "github:zzpanelsrv/held:" .. i },
                ["core/net/owner"] = { client_id = 7 },
                ["core/net/sync"] = false,
                ["zz/held"] = {},
            })
        end
        step("full_back")

    elseif phase == "full_back" and next(answer_of(world, "seven")) == nil and #portals(world, 7) == 8 and clock > 0.2 then
        ask(commands, world, "seven", { op = "portal", target_sk = OTHER })
        ask(commands, world, "eight", { op = "portal", target_sk = OTHER })
        step("full")

    elseif phase == "full" and answer_of(world, "seven").status ~= nil and answer_of(world, "eight").status ~= nil
        and clock > 0.2 then
        local seven, eight = answer_of(world, "seven"), answer_of(world, "eight")
        T("PS6_an_owner_holds_at_most_eight_counting_the_one_it_opened", #portals(world, 7) == 8
            and seven.status == "failed" and seven.message == "8 portals already", tostring(seven.message))
        T("PS6_another_owner_can_still_open_one", #portals(world, 8) == 1 and eight.status == "opened",
            tostring(eight.status))
        mark_reloads = reloads
        reload()
        step("reloading")

    elseif phase == "reloading" and reloads > mark_reloads then
        step("reloaded")

    elseif phase == "reloaded" and clock > 1.5 then
        T("PS8_a_reload_keeps_the_portals_it_opened", #portals(world, 7) == 8 and #portals(world, 8) == 1,
            #portals(world, 7) .. " " .. #portals(world, 8))
        commands:entity(carrier(world, "eight"):id()):remove("git/panel")
        step("removed")

    elseif phase == "removed" and clock > 0.5 then
        local sync = carrier(world, "eight"):get("core/net/sync") or {}
        T("PS7_taking_git_panel_off_takes_its_sync_entries", sync["git/panel/request"] == nil
            and sync["git/panel/response"] == nil and #portals(world, 8) == 1, "")
        phase = "done"
        finish()
    end

    if phase ~= "done" and clock > 10 then
        T("PS0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        finish()
    end
end):in_set("zz/panel_server_suite")
