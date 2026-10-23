-- --host
-- The client half of `abilities`, on the local player. A press is written the way `input`
-- writes one: the action component appears.
--
--   C1 each ability's key is bound into `input/game` under `abilities`
--   C2 an ability that went is unbound, and a changed key is rebound
--   C3 bindings come back when `input` is added again
--   C4 a local press starts the cooldown at once, on the client
--   C5 `abilities` taken off: the keys are unbound
--   C6 another player's copy is not bound
local app = require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("AbilitiesClientSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
end)

local function the_player(world)
    return world:query({
        with = { "zz/player" },
        optional = { "abilities", "input/game", "abilities/fireball/cooling" },
    })[1]
end

local function bound(p)
    return ((p and p:get("input/game")) or {}).abilities or {}
end

local phase, clock = "spawn", 0
local player_id

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local p = player_id and the_player(world)

    if phase == "spawn" then
        player_id = commands:spawn({
            ["zz/player"] = {},
            ["core/net/local"] = {},
            ["core/net/sync"] = false,
            input = { mode = "input/game" },
            abilities = {
                fireball = { key = "KeyQ", cooldown = 5 },
                slow = { key = "KeyE" },
            },
        }):id()
        -- Another player's copy, here only as a replica.
        commands:spawn({
            ["zz/other"] = {},
            ["core/net/sync"] = false,
            input = { mode = "input/game" },
            abilities = { fireball = { key = "KeyQ" } },
        })
        step("bound")

    elseif phase == "bound" then
        if clock < 0.3 then return end
        local b = bound(p)
        suite.assert_test("C1_each_key_is_bound",
            (b.fireball or {}).key == "KeyQ" and (b.slow or {}).key == "KeyE", "")
        local other = world:query({ with = { "zz/other" }, optional = { "input/game" } })[1]
        suite.assert_test("C6_only_the_local_player_is_bound",
            other ~= nil and next(bound(other)) == nil, "")
        world:get_entity(player_id):patch({ abilities = { slow = null, fireball = { key = "KeyR" } } })
        step("rebound")

    elseif phase == "rebound" then
        if clock < 0.3 then return end
        local b = bound(p)
        suite.assert_test("C2_a_gone_ability_is_unbound_and_a_changed_key_rebound",
            b.slow == nil and (b.fireball or {}).key == "KeyR",
            "slow=" .. tostring(b.slow ~= nil) .. " fireball=" .. tostring((b.fireball or {}).key))
        world:get_entity(player_id):patch({ input = null, ["input/game"] = null })
        step("input_gone")

    elseif phase == "input_gone" then
        if clock < 0.2 then return end
        world:get_entity(player_id):patch({ input = { mode = "input/game" } })
        step("input_back")

    elseif phase == "input_back" then
        if clock < 0.3 then return end
        suite.assert_test("C3_bindings_come_back_with_input", (bound(p).fireball or {}).key == "KeyR", "")
        world:get_entity(player_id):patch({ ["input/game/abilities/fireball"] = { value = 1 } })
        step("pressed")

    elseif phase == "pressed" then
        if clock < 0.3 then return end
        suite.assert_test("C4_a_local_press_starts_the_cooldown", p:has("abilities/fireball/cooling"), "")
        world:get_entity(player_id):patch({ abilities = null })
        step("removed")

    elseif phase == "removed" then
        if clock < 0.3 then return end
        suite.assert_test("C5_taken_off_the_keys_are_unbound", next(bound(p)) == nil, "")
        suite.finish("ABILITIES_CLIENT")
        phase = "done"
    end
end):in_set("zz/abilities_client_suite")
