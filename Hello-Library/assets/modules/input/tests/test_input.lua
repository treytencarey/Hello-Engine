-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("InputSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
end)

local ACTIONS = {
    "input/game/movement/forward",
    "input/game/movement/jump",
    "input/game/look/zoom",
    "input/ui/menu/pick",
    "input/ui/menu/point",
}

local function player(world)
    for _, e in ipairs(world:query({
        with = { "zz/player" },
        optional = { "input", "input/held", "input/actions", table.unpack(ACTIONS) },
    })) do
        return e
    end
end

-- A consumer reading the edges, as movement and a camera would.
local pressed, changes, max_dy = 0, 0, 0
app:add_systems(Update, { World }, function(world)
    pressed = pressed + #world:query({ added = { "input/game/movement/forward" }, with = { "zz/player" } })
    changes = changes + #world:query({ changed = { "input/game/movement/forward" }, with = { "zz/player" } })
    for _, e in ipairs(world:query({ changed = { "input/game/look/zoom" } })) do
        max_dy = math.max(max_dy, e:get("input/game/look/zoom").dy)
    end
end):in_set("zz/input_suite_consumer")

local phase, clock = "spawn", 0
local events = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    for _, ev in ipairs(events) do world:write_event(ev[1], ev[2]) end
    events = {}
    local p = player(world)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function key(code, state) events[#events + 1] = { "SyntheticKeyInput", { key_code = code, state = state } } end

    if phase == "spawn" then
        commands:spawn({
            ["zz/player"] = {},
            ["core/net/local"] = {},
            ["core/net/sync"] = false,
            input = { sensitivity = 2.0, mode = "input/game" },
            ["input/game"] = {
                movement = {
                    forward = { key = "KeyW" },
                    jump = { key = "Space" },
                },
                look = {
                    zoom = { scroll = true },
                },
            },
            ["input/ui"] = {
                menu = {
                    pick = { key = "KeyE" },
                    point = { button = "Left" },
                },
            },
        })
        step("ready")

    elseif phase == "ready" and p and clock > 0.3 then
        suite.assert_test("I1_nothing_held_means_no_action_components",
            not p:has("input/game/movement/forward") and not p:has("input/ui/menu/pick"), "")
        key("KeyW", "Pressed")
        key("KeyE", "Pressed")
        events[#events + 1] = { "SyntheticMouseInput", { button = "Left", state = "Pressed" } }
        events[#events + 1] = { "SyntheticMouseWheel", { x = 0, y = 3 } }
        step("held")

    elseif phase == "held" and p:has("input/game/movement/forward") and clock > 0.3 then
        suite.assert_test("I2_a_held_key_is_a_component_added_once",
            p:get("input/game/movement/forward").value == 1 and pressed == 1 and changes == 1
                and not p:has("input/game/movement/jump"),
            "pressed=" .. pressed .. " changes=" .. changes)
        suite.assert_test("I3_another_modes_action_stays_absent", not p:has("input/ui/menu/pick"), "")
        suite.assert_test("I4_a_scroll_arrives_scaled_for_one_frame",
            max_dy == 6 and not p:has("input/game/look/zoom"), "max dy=" .. max_dy)
        events[#events + 1] = { "AnalogInput", { key_code = "KeyW", value = 0.5 } }
        step("analog")

    elseif phase == "analog" and clock > 0.2 then
        suite.assert_test("I5_an_analog_value_replaces_the_press",
            p:get("input/game/movement/forward").value == 0.5,
            "value=" .. tostring(p:get("input/game/movement/forward").value))
        p:patch({ input = { mode = "input/ui", show_cursor = true } })
        step("ui")

    elseif phase == "ui" and clock > 0.2 then
        suite.assert_test("I6_switching_mode_removes_held_actions_and_held_keys_wait_for_release",
            not p:has("input/game/movement/forward") and not p:has("input/ui/menu/pick")
                and not p:has("input/ui/menu/point"), "")
        key("KeyE", "Released")
        events[#events + 1] = { "SyntheticMouseInput", { button = "Left", state = "Released" } }
        step("e released")

    elseif phase == "e released" and clock > 0.2 then
        key("KeyE", "Pressed")
        events[#events + 1] = { "SyntheticMouseInput", { button = "Left", state = "Pressed" } }
        step("e pressed")

    elseif phase == "e pressed" and clock > 0.2 then
        suite.assert_test("I6b_a_key_pressed_again_acts_in_the_new_mode",
            p:has("input/ui/menu/pick") and p:has("input/ui/menu/point"), "")
        p:patch({ input = { mode = "input/game", show_cursor = false } })
        step("game again")

    elseif phase == "game again" and clock > 0.2 then
        suite.assert_test("I6c_a_key_held_back_into_a_mode_waits_too", not p:has("input/game/movement/forward"), "")
        key("KeyW", "Released")
        step("w released")

    elseif phase == "w released" and clock > 0.2 then
        key("KeyW", "Pressed")
        step("w pressed")

    elseif phase == "w pressed" and p:has("input/game/movement/forward") and clock > 0.2 then
        p:patch({ ["input/game/movement/forward"] = null })
        step("output removed")

    elseif phase == "output removed" and clock > 0.2 then
        suite.assert_test("I7_an_action_removed_while_held_comes_back", p:has("input/game/movement/forward"), "")
        key("KeyW", "Released")
        step("released")

    elseif phase == "released" and clock > 0.2 then
        suite.assert_test("I8_releasing_removes_the_action", not p:has("input/game/movement/forward"), "")
        key("KeyW", "Pressed")
        step("rebind")

    elseif phase == "rebind" and p:has("input/game/movement/forward") and clock > 0.2 then
        p:patch({ ["input/game"] = { movement = null } })
        step("unbound")

    elseif phase == "unbound" and clock > 0.2 then
        suite.assert_test("I9_unbinding_removes_the_groups_actions", not p:has("input/game/movement/forward"), "")
        p:patch({ ["input/game"] = { movement = { forward = { key = "KeyW" } } } })
        step("bound again")

    elseif phase == "bound again" and p:has("input/game/movement/forward") and clock > 0.2 then
        p:remove("input")
        step("input removed")

    elseif phase == "input removed" and clock > 0.3 then
        suite.assert_test("I10_removing_input_removes_every_action_and_its_state",
            not p:has("input/game/movement/forward") and not p:has("input/held") and not p:has("input/actions"),
            string.format("forward=%s held=%s", tostring(p:has("input/game/movement/forward")), tostring(p:has("input/held"))))
        phase = "done"
        suite.finish("InputSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("I0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("InputSuite")
    end
end):in_set("zz/input_suite")
