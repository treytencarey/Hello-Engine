-- --host
-- A real `player` on a headless server, with all its mods, so `First` holds what it holds in play.
-- A mod taking its own sync entries off on its `removed` edge writes `core/net/sync` beside the
-- registry, which writes it on the same edge. Neither write may undo the other.
--
-- PROBABILISTIC: the two systems' order changes between runs, and only one order shows the fault. A
-- World row's patch in the registry failed this in 2 of 16 runs, so a pass here proves little alone.
--
--   SO1 a real player carries the mod, with its entries and the registry's
--   SO2 the mod taken off: all of them go, the others stay
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("PlayerSyncOffSuite")
local PANEL = "player/tests/fixtures/zz_panel"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local phase, clock, player_id = "spawn", 0, nil

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local p = player_id and world:get_entity(player_id)
    local sync = p and p:get("core/net/sync") or {}
    if phase == "spawn" then
        player_id = commands:spawn({
            player = { client_id = 7 },
            [PANEL] = {},
            ["core/net/owner"] = { client_id = 7 },
            ["core/net/sync"] = { Transform = { authority = "client" } },
        }):id()
        phase, clock = "loaded", 0
    elseif phase == "loaded" then
        if not (sync["zz/panel/request"] and sync[PANEL]) then return end
        if clock < 1.0 then return end
        suite.assert_test("SO1_it_carries_the_mod_and_the_entries", sync["zz/panel/answer"] ~= nil, "")
        commands:entity(player_id):remove(PANEL)
        phase, clock = "off", 0
    elseif phase == "off" then
        if clock < 0.5 then return end
        suite.assert_test("SO2_the_mods_entries_go", sync["zz/panel/request"] == nil and sync["zz/panel/answer"] == nil,
            "request " .. tostring(sync["zz/panel/request"] ~= nil))
        suite.assert_test("SO2_the_registrys_entry_goes", sync[PANEL] == nil, "")
        suite.assert_test("SO2_the_others_stay", sync.Transform ~= nil and sync.player ~= nil, "")
        suite.finish("PLAYER_SYNC_OFF")
        phase = "done"
    end
end):in_set("zz/player_sync_off")
