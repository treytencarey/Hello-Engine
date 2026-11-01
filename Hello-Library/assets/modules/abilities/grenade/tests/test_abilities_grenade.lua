-- --host
-- `abilities/grenade` on the server, headless, with `abilities` and `abilities/projectile`.
--
--   G1 missing fields get defaults
--   G2 it registers itself in `abilities`
--   G6 a cooldown started by something else (a debuff) lobs nothing
--   G3 a press lobs a launch from 1 m above the player, with its fields, and it falls
--      (gravity) and does not explode on contact
--   G4 taken off while it cools: its entry and its cooldown go
--   G5 ...and another ability's entry stays
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("AbilitiesGrenadeSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local function the_player(world)
    return world:query({
        with = { "zz/player" },
        optional = { "abilities/grenade", "abilities", "cooldown", "abilities/grenade/cooling" },
    })[1]
end

local phase, clock = "spawn", 0
local player_id

-- The suite's clock is the mods': Bevy's `Time`.
app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local p = player_id and the_player(world)
    local function patch(t) world:get_entity(player_id):patch(t) end

    if phase == "spawn" then
        player_id = commands:spawn({
            ["zz/player"] = {},
            ["abilities/grenade"] = { cooldown = 2 },
            abilities = { zzother = { key = "KeyE" } },
            Transform = { translation = { x = 3, y = 50, z = 0 } },
            camera = { yaw = 0, pitch = 0 },
            ["core/net/owner"] = { client_id = 7 },
            ["core/net/sync"] = { Transform = { authority = "client" } },
        }):id()
        step("registered")

    elseif phase == "registered" then
        if clock < 0.5 then return end
        local g = p:get("abilities/grenade") or {}
        suite.assert_test("G1_missing_fields_get_defaults",
            g.key == "KeyG" and g.cooldown == 2 and g.speed == 20 and g.radius == 0.2 and g.color ~= nil, "")
        local a = (p:get("abilities") or {}).grenade or {}
        suite.assert_test("G2_it_registers_in_abilities", a.key == "KeyG" and a.cooldown == 2,
            "entry key=" .. tostring(a.key))
        -- A short debuff starts the cooldown with no press.
        patch({ cooldown = { ["abilities/grenade/cooling"] = { remaining = 0.3 } } })
        step("debuff")

    elseif phase == "debuff" then
        if clock < 0.6 then return end
        suite.assert_test("G6_a_cooldown_started_by_something_else_lobs_nothing",
            #world:query({ with = { "abilities/projectile" } }) == 0 and not p:has("abilities/grenade/cooling"),
            "launches=" .. #world:query({ with = { "abilities/projectile" } }) .. " cooling=" .. tostring(p:has("abilities/grenade/cooling")))
        patch({ ["input/game/abilities/grenade"] = { value = 1 } })
        step("fired")

    elseif phase == "fired" then
        if clock < 0.3 then return end
        local list = world:query({
            with = { "abilities/projectile" },
            optional = { "projectile", "ChildOf", "projectile/explode" },
        })
        local launch = list[1] and list[1]:get("abilities/projectile") or {}
        local shot = list[1] and list[1]:get("projectile") or {}
        suite.assert_test("G3_a_press_lobs_a_falling_launch_from_the_player",
            #list == 1 and (launch.at or {}).x == 3 and (launch.at or {}).y == 51
                and launch.speed == 20 and launch.radius == 0.2 and (shot.gravity or 0) > 0
                and list[1]:get("projectile/explode") == nil and p:has("abilities/grenade/cooling"),
            "launches=" .. #list .. " gravity=" .. tostring(shot.gravity))
        commands:entity(player_id):remove("abilities/grenade")
        step("removed")

    elseif phase == "removed" then
        if clock < 0.3 then return end
        local timers = p:get("cooldown") or {}
        local list = p:get("abilities") or {}
        suite.assert_test("G4_taken_off_its_entry_and_cooldown_go",
            list.grenade == nil and timers["abilities/grenade/cooling"] == nil and not p:has("abilities/grenade/cooling"),
            "entry=" .. tostring(list.grenade ~= nil) .. " timer=" .. tostring(timers["abilities/grenade/cooling"] ~= nil)
                .. " cooling=" .. tostring(p:has("abilities/grenade/cooling")))
        suite.assert_test("G5_another_abilitys_entry_stays", (list.zzother or {}).key == "KeyE", "")
        suite.finish("ABILITIES_GRENADE")
        phase = "done"
    end
end):in_set("zz/abilities_grenade_suite")
