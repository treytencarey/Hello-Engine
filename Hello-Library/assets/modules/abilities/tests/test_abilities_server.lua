-- --host
-- The generic `abilities`, on the server, headless. A press is written the way core/net
-- applies a client's synced action on the server: the action is added, then taken off. A
-- fire is the cooldown starting (`abilities/<name>/cooling` added), counted here.
--
--   A1 each ability's action is declared for sync: client authority, the owner only
--   A2 a missing cooldown gets its default, and the rest is kept
--   A3 a press fires: the cooldown starts
--   A4 a press while it cools does not fire
--   A5 holding the key fires once
--   A6 another ability pressed while the first is held fires only the new one
--   A7 a press after the cooldown fires again
--   A8 one entry taken out while it cools: its action sync and its cooldown go, the others stay
--   A9 `abilities` taken off: the action syncs and the cooldowns go
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("AbilitiesServerSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local fires = { zzball = 0, zzslow = 0 }

local function the_player(world)
    return world:query({
        with = { "zz/player" },
        optional = { "abilities", "core/net/sync", "cooldown", "abilities/zzball/cooling", "abilities/zzslow/cooling" },
    })[1]
end

local phase, clock = "spawn", 0
local player_id

-- The suite's clock is the mods': Bevy's `Time`.
app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local p = player_id and the_player(world)
    local function press(patch) world:get_entity(player_id):patch(patch) end

    if phase == "spawn" then
        player_id = commands:spawn({
            ["zz/player"] = {},
            abilities = {
                zzball = { key = "KeyQ", cooldown = 0.5 },
                zzslow = { key = "KeyE" },
            },
            ["core/net/owner"] = { client_id = 7 },
            ["core/net/sync"] = { Transform = { authority = "client" } },
        }):id()
        step("declared")

    elseif phase == "declared" then
        if clock < 0.3 then return end
        local sync = p:get("core/net/sync") or {}
        local entry = sync["input/game/abilities/zzball"] or {}
        suite.assert_test("A1_each_action_is_declared_for_sync",
            entry.authority == "client" and entry.target == "owner" and (sync["input/game/abilities/zzslow"] or {}).authority == "client",
            "zzball entry: " .. tostring(entry.authority) .. "/" .. tostring(entry.target))
        local slow = (p:get("abilities") or {}).zzslow or {}
        suite.assert_test("A2_a_missing_cooldown_gets_its_default", slow.cooldown == 1 and slow.key == "KeyE",
            "zzslow: cooldown=" .. tostring(slow.cooldown))
        press({ ["input/game/abilities/zzball"] = { value = 1 } })
        step("fired")

    elseif phase == "fired" then
        if clock < 0.2 then return end
        suite.assert_test("A3_a_press_fires", fires.zzball == 1 and p:has("abilities/zzball/cooling"), "fires=" .. fires.zzball)
        commands:entity(player_id):remove("input/game/abilities/zzball")
        step("released")

    elseif phase == "released" then
        press({ ["input/game/abilities/zzball"] = { value = 1 } })
        step("pressed_cooling")

    elseif phase == "pressed_cooling" then
        if clock < 0.1 then return end
        suite.assert_test("A4_a_press_while_cooling_does_not_fire", fires.zzball == 1, "fires=" .. fires.zzball)
        step("held")

    elseif phase == "held" then
        if clock < 0.8 then return end
        suite.assert_test("A5_holding_the_key_fires_once", fires.zzball == 1 and not p:has("abilities/zzball/cooling"),
            "fires=" .. fires.zzball)
        press({ ["input/game/abilities/zzslow"] = { value = 1 } })
        step("other_pressed")

    elseif phase == "other_pressed" then
        if clock < 0.2 then return end
        suite.assert_test("A6_another_press_fires_only_that_ability", fires.zzball == 1 and fires.zzslow == 1,
            "zzball=" .. fires.zzball .. " zzslow=" .. fires.zzslow)
        commands:entity(player_id):remove("input/game/abilities/zzball", "input/game/abilities/zzslow")
        step("released_again")

    elseif phase == "released_again" then
        press({ ["input/game/abilities/zzball"] = { value = 1 } })
        step("pressed_ready")

    elseif phase == "pressed_ready" then
        if clock < 0.1 then return end
        suite.assert_test("A7_a_press_after_the_cooldown_fires_again", fires.zzball == 2, "fires=" .. fires.zzball)
        -- Taken out while it still cools (0.5 s from this press).
        world:get_entity(player_id):patch({ abilities = { zzball = null } })
        step("entry_removed")

    elseif phase == "entry_removed" then
        if clock < 0.1 then return end
        local sync = p:get("core/net/sync") or {}
        local timers = p:get("cooldown") or {}
        suite.assert_test("A8_one_entry_taken_out_takes_its_sync_and_cooldown",
            sync["input/game/abilities/zzball"] == nil and timers["abilities/zzball/cooling"] == nil and not p:has("abilities/zzball/cooling")
                and sync["input/game/abilities/zzslow"] ~= nil and ((p:get("abilities") or {}).zzslow or {}).key == "KeyE",
            "sync=" .. tostring(sync["input/game/abilities/zzball"] ~= nil) .. " timer=" .. tostring(timers["abilities/zzball/cooling"] ~= nil)
                .. " cooling=" .. tostring(p:has("abilities/zzball/cooling")))
        press({ ["input/game/abilities/zzslow"] = { value = 1 } })
        step("slow_cooling")

    elseif phase == "slow_cooling" then
        if clock < 0.1 then return end
        commands:entity(player_id):remove("abilities")
        step("removed")

    elseif phase == "removed" then
        if clock < 0.1 then return end
        local sync = p:get("core/net/sync") or {}
        local timers = p:get("cooldown") or {}
        suite.assert_test("A9_taken_off_the_action_syncs_and_cooldowns_go",
            sync["input/game/abilities/zzslow"] == nil and sync.Transform ~= nil and timers["abilities/zzslow/cooling"] == nil and not p:has("abilities/zzslow/cooling"),
            "sync=" .. tostring(sync["input/game/abilities/zzslow"] ~= nil) .. " timer=" .. tostring(timers["abilities/zzslow/cooling"] ~= nil))
        suite.finish("ABILITIES_SERVER")
        phase = "done"
    end
end):in_set("zz/abilities_server_suite")

-- What a sub-mod reacts to: the cooldown starting.
app:add_systems(Update, { World }, function(world)
    for _, e in ipairs(world:query({ ["or"] = { added = { "abilities/zzball/cooling", "abilities/zzslow/cooling" } } })) do
        if e:is_added("abilities/zzball/cooling") then fires.zzball = fires.zzball + 1 end
        if e:is_added("abilities/zzslow/cooling") then fires.zzslow = fires.zzslow + 1 end
    end
end):in_set("zz/abilities_server_fires")
