-- --host
-- A binding with `take = true` takes its key or button in its mode, fed the synthetic messages a
-- device-less source writes.
--
--   IT1 a taking key binding fires and the mode's other binding of that key does not
--   IT2 the same for a mouse button
--   IT3 removing the taking binding gives the key back
--   IT4 two taking bindings of one key both fire, and the other still does not
--   IT5 removing the taking binding while its key is held gives the key back at once
--   IT6 a taking scroll binding takes the wheel: it fires and the mode's other scroll binding does not
--   IT7 removing it gives the wheel back
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local bevy = require("bevy::prelude")
local Net = require("modules/core/net/shared/net.lua")

local suite = helpers.create_suite("InputTakeSuite")
local T = suite.assert_test

local plain = { zz_plain = { esc = { key = "Escape" }, pick = { button = "Left" }, zoom = { scroll = true } } }
local function with(extra)
    local bindings = { zz_plain = plain.zz_plain }
    for group, actions in pairs(extra) do
        bindings[group] = actions
    end
    return bindings
end

-- This client's world net, unconnected: what it owns here is in its `core/net/owns`.
local world_net

app:add_systems(Startup, { World, Commands }, function(world, commands)
    -- declared first, as the net does when it starts: an owner stored before it gets no owner edge
    Net.declare_ownership(world, commands)
    world_net = commands:spawn({
        ["core/world/net"] = { mode = "client" },
        ["core/net"] = { mode = "client", name = "zzint" },
        ["core/net/sync"] = false,
    }):id()
    commands:spawn({
        ["zz/player"] = {},
        input = {},
        ["input/mode"] = { mode = "input/ui" },
        ["input/ui"] = with({ zz_take = { esc = { key = "Escape", take = true }, pick = { button = "Left", take = true } } }),
        ["core/net/owner"] = world_net,
        ["core/net/sync"] = false,
    })
end)

local function player(world)
    return world:query({
        with = { "zz/player" },
        optional = {
            "input/ui/zz_plain/esc",
            "input/ui/zz_plain/pick",
            "input/ui/zz_take/esc",
            "input/ui/zz_take/pick",
            "input/ui/zz_also/esc",
            "input/ui/zz_plain/zoom",
            "input/ui/zz_take/wheel",
        },
    })[1]
end

-- A scroll action is there only on the frames the wheel turns, so each frame says what it saw.
local seen = {}
app:add_systems(Update, { World }, function(world)
    local p = player(world)
    if p == nil then return end
    seen.plain = seen.plain or p:has("input/ui/zz_plain/zoom")
    seen.take = seen.take or p:has("input/ui/zz_take/wheel")
end):in_set("zz/input_take_seen")

local keys, buttons, wheels = {}, {}, {}
local steps, at, t, mark = {}, 1, 0, 0
local function step(ready, act) steps[#steps + 1] = { ready = ready, act = act } end
local function after(seconds) return function() return t - mark > seconds end end
local function key(state) keys[#keys + 1] = { key_code = "Escape", state = state } end
local function button(state) buttons[#buttons + 1] = { button = "Left", state = state } end

step(after(0.3), function()
    key("Pressed")
    button("Pressed")
end)
step(after(0.3), function(world)
    local p = player(world)
    T("IT1_the_taking_key_binding_fires", p:has("input/ui/zz_take/esc"), "")
    T("IT1_the_other_binding_of_the_key_does_not", not p:has("input/ui/zz_plain/esc"), "")
    T("IT2_the_taking_button_binding_fires", p:has("input/ui/zz_take/pick"), "")
    T("IT2_the_other_binding_of_the_button_does_not", not p:has("input/ui/zz_plain/pick"), "")
    key("Released")
    button("Released")
end)
step(after(0.3), function(world, commands)
    commands:entity(player(world):id()):insert({ ["input/ui"] = with({}) })
end)
step(after(0.3), function()
    key("Pressed")
end)
step(after(0.3), function(world, commands)
    T("IT3_without_the_taking_binding_the_key_is_back", player(world):has("input/ui/zz_plain/esc"), "")
    key("Released")
    commands:entity(player(world):id()):insert({
        ["input/ui"] = with({
            zz_take = { esc = { key = "Escape", take = true } },
            zz_also = { esc = { key = "Escape", take = true } },
        }),
    })
end)
step(after(0.3), function()
    key("Pressed")
end)
step(after(0.3), function(world, commands)
    local p = player(world)
    T("IT4_two_taking_bindings_both_fire", p:has("input/ui/zz_take/esc") and p:has("input/ui/zz_also/esc"), "")
    T("IT4_and_the_other_still_does_not", not p:has("input/ui/zz_plain/esc"), "")
    commands:entity(p:id()):insert({ ["input/ui"] = with({}) })
end)
step(after(0.3), function(world, commands)
    T("IT5_removed_while_held_the_key_is_back_at_once", player(world):has("input/ui/zz_plain/esc"), "")
    key("Released")
    commands:entity(player(world):id()):insert({
        ["input/ui"] = with({ zz_take = { wheel = { scroll = true, take = true } } }),
    })
end)
step(after(0.3), function()
    seen = {}
    wheels[#wheels + 1] = { x = 0, y = 2 }
end)
step(after(0.3), function(world, commands)
    T("IT6_a_taking_scroll_binding_takes_the_wheel", seen.take == true and not seen.plain,
        string.format("take %s plain %s", tostring(seen.take), tostring(seen.plain)))
    commands:entity(player(world):id()):insert({ ["input/ui"] = with({}) })
end)
step(after(0.3), function()
    seen = {}
    wheels[#wheels + 1] = { x = 0, y = 2 }
end)
step(after(0.3), function()
    T("IT7_without_it_the_wheel_is_back", seen.plain == true, tostring(seen.plain))
end)

local done = false
app:add_systems(Update, {
    World,
    Commands,
    bevy.MessageWriter["input/synthetic_key"],
    bevy.MessageWriter["input/synthetic_mouse_button"],
    bevy.MessageWriter["input/synthetic_mouse_wheel"],
}, function(world, commands, write_key, write_button, write_wheel)
    t = t + world:delta_time()
    for _, m in ipairs(keys) do write_key:write(m) end
    for _, m in ipairs(buttons) do write_button:write(m) end
    for _, m in ipairs(wheels) do write_wheel:write(m) end
    keys, buttons, wheels = {}, {}, {}
    if done then
        return
    end
    local s = steps[at]
    if s == nil then
        done = true
        suite.finish("InputTakeSuite")
    elseif s.ready(world) then
        s.act(world, commands)
        at, mark = at + 1, t
    elseif t - mark > 15 then
        T("IT0_stuck_at_step_" .. at, false, "")
        done = true
        suite.finish("InputTakeSuite")
    end
end):in_set("zz/input_take_drive")
