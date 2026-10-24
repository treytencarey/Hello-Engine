-- Keys, mouse buttons, motion and scroll, turned into one component per bound action
-- that exists only while it is active. A mod binds by writing its group into a mode
-- (`input/game`, `input/ui`), and reads `with` (held), `added` (pressed), `removed`
-- (released) or `changed`. Each player's `mode` names the bindings that apply. Every
-- key event reaches every local player: there is no per-player device routing yet.
--
-- input = {
--     mode = <the component holding the bindings that apply, e.g. "input/game">,
--     show_cursor = <boolean>,
--     sensitivity = <number>,
-- }
--
-- input/game = {
--     <group> = {
--         <action> = { key = <KeyCode> } or { button = <MouseButton> } or { motion = true } or { scroll = true },
--     },
-- }
--
-- input/ui = <same shape as input/game>
--
-- <mode>/<group>/<action> = { value = <1, or the analog strength> } or { dx = <number>, dy = <number> }
--
-- input/held = {
--     keys = { <KeyCode> = <1 or analog strength> },
--     buttons = { <MouseButton> = 1 },
--     mode = <the mode the actions were last built for>,
--     through = {
--         keys = { <KeyCode> = 1 },
--         buttons = { <MouseButton> = 1 },
--     },
-- }
--
-- `through` holds what was held when the mode last changed: it does not act in the new
-- mode until released, so the Escape that opens a menu does not also close it.
--
-- input/actions = { <action component> = true }


local bevy = require("bevy::prelude")
local LuaCustomEvent = require("bevy_lua_ecs::custom_events::LuaCustomEvent")
local KeyboardInput = require("bevy::input::keyboard::KeyboardInput")
local MouseButtonInput = require("bevy::input::mouse::MouseButtonInput")
local MouseMotion = require("bevy::input::mouse::MouseMotion")
local MouseWheel = require("bevy::input::mouse::MouseWheel")

app:add_systems(First, {
    bevy.MessageReader[KeyboardInput],
    bevy.MessageReader[MouseButtonInput],
    bevy.MessageReader[LuaCustomEvent],
    Query[{
        with = { "input", "core/net/local" },
        optional = { "input/held" },
    }],
    Commands,
}, function(keyboard, mouse_buttons, lua_messages, players, commands)
    local keys = keyboard:read()
    local buttons = mouse_buttons:read()
    local analog = {}
    for _, m in ipairs(lua_messages:read()) do
        if m.name == "SyntheticKeyInput" then
            keys[#keys + 1] = m.data
        elseif m.name == "SyntheticMouseInput" then
            buttons[#buttons + 1] = m.data
        elseif m.name == "AnalogInput" then
            analog[#analog + 1] = m.data
        end
    end

    for _, e in ipairs(players:iter()) do
        local held = e:get("input/held") or {}
        local before = held.keys or {}
        local held_keys, held_buttons = {}, {}
        local released_keys, released_buttons = {}, {}
        for _, ev in ipairs(keys) do
            held_keys[ev.key_code] = ev.state == "Pressed" and 1 or null
            released_keys[ev.key_code] = ev.state ~= "Pressed" and null or nil
        end
        for _, ev in ipairs(analog) do
            if held_keys[ev.key_code] == 1 or (held_keys[ev.key_code] == nil and before[ev.key_code]) then
                held_keys[ev.key_code] = ev.value
            end
        end
        for _, ev in ipairs(buttons) do
            held_buttons[ev.button] = ev.state == "Pressed" and 1 or null
            released_buttons[ev.button] = ev.state ~= "Pressed" and null or nil
        end
        if next(held_keys) or next(held_buttons) or not e:has("input/held") then
            commands:entity(e:id()):patch({
                ["input/held"] = {
                    keys = held_keys,
                    buttons = held_buttons,
                    through = {
                        keys = released_keys,
                        buttons = released_buttons,
                    },
                },
            })
        end
    end
end):in_set("input/held")

-- The action components the player's mode calls for, added, updated or removed so
-- that only what is active exists.
app:add_systems(PreUpdate, {
    bevy.MessageReader[MouseMotion],
    bevy.MessageReader[MouseWheel],
    bevy.MessageReader[LuaCustomEvent],
    Query[{
        with = { "input", "core/net/local" },
        optional = { "input/actions" },
    }],
    Query[{
        with = { "input", "input/held", "core/net/local" },
        optional = { "input/actions" },
    }],
    Commands,
}, function(mouse_motion, mouse_wheel, lua_messages, players, held_players, commands)
    local motion, scroll = { x = 0, y = 0 }, { x = 0, y = 0 }
    for _, ev in ipairs(mouse_motion:read()) do
        motion.x = motion.x + (ev.delta and ev.delta.x or 0)
        motion.y = motion.y + (ev.delta and ev.delta.y or 0)
    end
    for _, ev in ipairs(mouse_wheel:read()) do
        scroll.x = scroll.x + (ev.x or 0)
        scroll.y = scroll.y + (ev.y or 0)
    end
    for _, m in ipairs(lua_messages:read()) do
        if m.name == "SyntheticMouseWheel" then
            scroll.x = scroll.x + (m.data.x or 0)
            scroll.y = scroll.y + (m.data.y or 0)
        end
    end

    -- The columns this pass reads come from data: each player's mode and the actions
    -- already added.
    local columns = {}
    for _, e in ipairs(players:iter()) do
        local input = e:get("input")
        local added = e:get("input/actions") or {}
        columns[#columns + 1] = input.mode
        for name in pairs(added) do columns[#columns + 1] = name end
    end

    for _, e in ipairs(held_players:with_columns({ optional = columns }):iter()) do
        local input = e:get("input")
        local held = e:get("input/held")
        local bindings = input.mode and e:get(input.mode) or {}
        local added = e:get("input/actions") or {}
        local sensitivity = input.sensitivity or 1.0
        local held_keys = held.keys or {}
        local held_buttons = held.buttons or {}
        local through = held.through or {}
        local through_keys = through.keys or {}
        local through_buttons = through.buttons or {}
        local player = commands:entity(e:id())
        if held.mode ~= input.mode then
            -- The mode changed: what is held now waits for its release.
            through_keys, through_buttons = held_keys, held_buttons
            player:patch({
                ["input/held"] = {
                    mode = input.mode,
                    through = {
                        keys = held_keys,
                        buttons = held_buttons,
                    },
                },
            })
        end
        local wanted = {}
        for group, actions in pairs(bindings) do
            for action, b in pairs(actions) do
                local delta = (b.motion and motion) or (b.scroll and scroll)
                local value = (b.key and not through_keys[b.key] and held_keys[b.key])
                    or (b.button and not through_buttons[b.button] and held_buttons[b.button])
                if delta and (delta.x ~= 0 or delta.y ~= 0) then
                    wanted[input.mode .. "/" .. group .. "/" .. action] = { dx = delta.x * sensitivity, dy = delta.y * sensitivity }
                elseif value then
                    wanted[input.mode .. "/" .. group .. "/" .. action] = { value = value }
                end
            end
        end

        local patch, actions, gone = {}, {}, {}
        for name in pairs(added) do
            if not wanted[name] then
                gone[#gone + 1] = name
                actions[name] = null
            end
        end
        for name, v in pairs(wanted) do
            local cur = e:get(name)
            if not cur or cur.value ~= v.value or cur.dx ~= v.dx or cur.dy ~= v.dy then
                patch[name] = v
            end
            actions[name] = true
        end
        if next(patch) or #gone > 0 then
            patch["input/actions"] = actions
            player:patch(patch)
            if #gone > 0 then
                player:remove(gone)
            end
        end
    end
end):in_set("input")

app:add_systems(PreUpdate, {
    Query[{
        changed = { "input" },
        with = { "core/net/local" },
    }],
    Query[{ with = { "Window", Mut["CursorOptions"] } }],
}, function(players, windows)
    for _, e in ipairs(players:iter()) do
        local input = e:get("input")
        local shown = input.show_cursor == true
        for _, w in ipairs(windows:iter_mut()) do
            w:set({
                CursorOptions = shown and { visible = true, grab_mode = "None" }
                    or { visible = false, grab_mode = { Confined = true } },
            })
        end
    end
end):in_set("input/cursor")
