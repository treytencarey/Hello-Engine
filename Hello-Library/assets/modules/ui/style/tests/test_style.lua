-- --host
-- ui/style: colors by role from the world's theme.
--
-- S1-S5 roles, the theme filling them, a role or the theme changing, alpha
-- S6  a button starts on its background, and a node with a hover role gets `Hovered`, false
-- S7  `Hovered` true (as picking inserts it) paints the hover role
-- S8  a press on the button's label, a child, puts Bevy's `Pressed` on the button, not the label,
--     and paints its press role (pointer events go up). A query naming `Pressed` since before any
--     entity had one sees it.
-- S8b a release on the label takes `Pressed` off, with a `removed` edge: the hover role, as the
--     button is still hovered
-- S8c a press ended by its drag's end (the release was off the button) ends it too
-- S8d a press ended by a cancel ends it too
-- S9  `Hovered` false returns the button to its background
-- S10-S11 removing the style; two themes
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Pointer = require("bevy::picking::prelude::Pointer")
local Press = require("bevy::picking::prelude::Press")
local Release = require("bevy::picking::prelude::Release")
local DragEnd = require("bevy::picking::prelude::DragEnd")
local Cancel = require("bevy::picking::prelude::Cancel")

local suite = helpers.create_suite("StyleSuite")

local NOWHERE = { target = { None = { width = 0, height = 0 } } }

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ ["ui/theme/dark"] = {} })
    -- A pointer event goes up only where Bevy knows `Window` (its traversal reads `Option<&Window>`).
    -- A world VM does, through bevy_ui's focus system; a headless suite has none until one is made.
    local window = commands:spawn({ Window = {} }):id()
    commands:entity(window):despawn()
end)

local function node(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/node" },
        optional = { "BackgroundColor", "TextColor", "BorderColor" },
    })) do
        if e:get("zz/node").name == name then
            return e
        end
    end
end

local function theme(world)
    return world:query({ with = { "ui/theme" } })[1]
end

local function near(a, b) return math.abs(a - b) < 1e-3 end

-- A read-back color against an expected { r, g, b, a }.
local function is(color, r, g, b, a)
    local c = color and color.Srgba
    return c ~= nil and near(c.red, r) and near(c.green, g) and near(c.blue, b) and near(c.alpha, a)
end

local function show(color)
    local c = color and color.Srgba
    return c and string.format("%.2f %.2f %.2f %.2f", c.red, c.green, c.blue, c.alpha) or "none"
end

-- Declared from the first frame, before any entity has `Pressed`.
local seen = { pressed = {}, let_go = 0 }
app:add_systems(Update, {
    Query[{ with = { "zz/node", "Pressed" } }],
    Query[{ removed = { "Pressed" } }],
}, function(pressed, let_go)
    seen.pressed = {}
    for _, e in ipairs(pressed:iter()) do seen.pressed[#seen.pressed + 1] = e:get("zz/node").name end
    seen.let_go = seen.let_go + #let_go:iter()
end):in_set("zz/style_suite/pressed")

local phase, clock = "spawn", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({
            ["zz/node"] = { name = "panel" },
            Node = {},
            ["ui/style"] = { background = "bg", text = "text", border = "border", border_left = "accent" },
        })
        local icon = commands:spawn({
            ["zz/node"] = { name = "icon" },
            Node = {},
            ["ui/style"] = { background = "icon_bg", hover = "icon_hover", press = "icon_active" },
        }):id()
        commands:spawn({
            ["zz/node"] = { name = "label" },
            Node = {},
            Text = "zz",
            ["ui/style"] = { text = "text" },
            ChildOf = icon,
        })
        step("styled")

    elseif phase == "styled" and clock > 0.3 then
        local panel = node(world, "panel")
        local border = panel:get("BorderColor")
        suite.assert_test("S1_a_node_gets_its_roles_colors",
            is(panel:get("TextColor"), 0.85, 0.85, 0.85, 1)
                and is(border.right, 0.08, 0.08, 0.10, 1) and is(border.left, 0.3, 0.6, 1, 1),
            show(panel:get("TextColor")) .. " / " .. show(border.left))
        suite.assert_test("S2_the_theme_mod_fills_the_colors",
            #world:query({ with = { "ui/theme" } }) == 1
                and is(panel:get("BackgroundColor"), 0.12, 0.12, 0.14, 1),
            "themes=" .. #world:query({ with = { "ui/theme" } }) .. " bg " .. show(panel:get("BackgroundColor")))
        panel:patch({ ["ui/style"] = { background = "danger" } })
        step("role changed")

    elseif phase == "role changed" and clock > 0.3 then
        suite.assert_test("S3_changing_a_role_recolors_the_node",
            is(node(world, "panel"):get("BackgroundColor"), 0.8, 0.3, 0.3, 1),
            show(node(world, "panel"):get("BackgroundColor")))
        theme(world):patch({ ["ui/theme"] = { danger = { r = 0, g = 0, b = 1, a = 1 } } })
        step("theme changed")

    elseif phase == "theme changed" and clock > 0.3 then
        suite.assert_test("S4_changing_the_theme_restyles_live",
            is(node(world, "panel"):get("BackgroundColor"), 0, 0, 1, 1),
            show(node(world, "panel"):get("BackgroundColor")))
        node(world, "panel"):patch({ ["ui/style"] = { alpha = 0.5 } })
        step("faded")

    elseif phase == "faded" and clock > 0.3 then
        local panel = node(world, "panel")
        suite.assert_test("S5_alpha_scales_every_color",
            is(panel:get("BackgroundColor"), 0, 0, 1, 0.5) and is(panel:get("TextColor"), 0.85, 0.85, 0.85, 0.5)
                and is(panel:get("BorderColor").left, 0.3, 0.6, 1, 0.5)
                and is(panel:get("BorderColor").right, 0.08, 0.08, 0.10, 0.5),
            show(panel:get("BackgroundColor")))
        local hovers = world:query({ with = { "zz/node", "Hovered" } })
        local hover_names = {}
        for _, h in ipairs(hovers) do
            hover_names[#hover_names + 1] = h:get("zz/node").name .. "=" .. tostring(h.Hovered:get())
        end
        suite.assert_test("S6_a_button_starts_on_its_background_and_gets_hovered_false",
            is(node(world, "icon"):get("BackgroundColor"), 0.15, 0.15, 0.18, 1)
                and #hovers == 1 and hover_names[1] == "icon=false",
            show(node(world, "icon"):get("BackgroundColor")) .. " hovered: " .. table.concat(hover_names, ", "))
        commands:entity(node(world, "icon"):id()):insert({ Hovered = true })
        step("hovered")

    elseif phase == "hovered" and clock > 0.2 then
        suite.assert_test("S7_hovered_uses_the_hover_role",
            is(node(world, "icon"):get("BackgroundColor"), 0.22, 0.22, 0.26, 1),
            show(node(world, "icon"):get("BackgroundColor")))
        commands:trigger(Pointer[Press], {
            entity = node(world, "label"):id(), pointer_location = NOWHERE,
            event = { button = "Primary", hit = { camera = node(world, "label"):id() } },
        })
        step("pressed")

    elseif phase == "pressed" and clock > 0.2 then
        suite.assert_test("S8_a_press_on_the_label_presses_the_button_and_uses_its_press_role",
            is(node(world, "icon"):get("BackgroundColor"), 0.25, 0.35, 0.5, 1)
                and #seen.pressed == 1 and seen.pressed[1] == "icon",
            show(node(world, "icon"):get("BackgroundColor")) .. " pressed: " .. table.concat(seen.pressed, ", "))
        commands:trigger(Pointer[Release], {
            entity = node(world, "label"):id(), pointer_location = NOWHERE,
            event = { button = "Primary", hit = { camera = node(world, "label"):id() } },
        })
        step("released")

    elseif phase == "released" and clock > 0.2 then
        suite.assert_test("S8b_a_release_on_the_label_lets_go_with_a_removed_edge_on_the_hover_role",
            is(node(world, "icon"):get("BackgroundColor"), 0.22, 0.22, 0.26, 1)
                and #seen.pressed == 0 and seen.let_go >= 1,
            string.format("%s pressed: %d, removed edges: %d", show(node(world, "icon"):get("BackgroundColor")),
                #seen.pressed, seen.let_go))
        commands:trigger(Pointer[Press], {
            entity = node(world, "label"):id(), pointer_location = NOWHERE,
            event = { button = "Primary", hit = { camera = node(world, "label"):id() } },
        })
        step("pressed to drag")

    elseif phase == "pressed to drag" and clock > 0.2 then
        local pressed = is(node(world, "icon"):get("BackgroundColor"), 0.25, 0.35, 0.5, 1)
        commands:trigger(Pointer[DragEnd], {
            entity = node(world, "label"):id(), pointer_location = NOWHERE,
            event = { button = "Primary", distance = { x = 40, y = 0 } },
        })
        step(pressed and "drag ended" or "drag ended unpressed")

    elseif (phase == "drag ended" or phase == "drag ended unpressed") and clock > 0.2 then
        suite.assert_test("S8c_a_drag_end_ends_the_press",
            phase == "drag ended" and is(node(world, "icon"):get("BackgroundColor"), 0.22, 0.22, 0.26, 1),
            phase .. ": " .. show(node(world, "icon"):get("BackgroundColor")))
        commands:trigger(Pointer[Press], {
            entity = node(world, "label"):id(), pointer_location = NOWHERE,
            event = { button = "Primary", hit = { camera = node(world, "label"):id() } },
        })
        step("pressed to cancel")

    elseif phase == "pressed to cancel" and clock > 0.2 then
        local pressed = is(node(world, "icon"):get("BackgroundColor"), 0.25, 0.35, 0.5, 1)
        commands:trigger(Pointer[Cancel], {
            entity = node(world, "label"):id(), pointer_location = NOWHERE,
            event = { hit = { camera = node(world, "label"):id() } },
        })
        step(pressed and "cancelled" or "cancelled unpressed")

    elseif (phase == "cancelled" or phase == "cancelled unpressed") and clock > 0.2 then
        suite.assert_test("S8d_a_cancel_ends_the_press",
            phase == "cancelled" and is(node(world, "icon"):get("BackgroundColor"), 0.22, 0.22, 0.26, 1),
            phase .. ": " .. show(node(world, "icon"):get("BackgroundColor")))
        commands:entity(node(world, "icon"):id()):insert({ Hovered = false })
        step("left")

    elseif phase == "left" and clock > 0.2 then
        suite.assert_test("S9_leaving_returns_to_the_background",
            is(node(world, "icon"):get("BackgroundColor"), 0.15, 0.15, 0.18, 1),
            show(node(world, "icon"):get("BackgroundColor")))
        -- One theme per world: a second one is not painted over the first.
        commands:spawn({ ["zz/theme"] = {}, ["ui/theme"] = { icon_bg = { r = 1, g = 0, b = 0, a = 1 } } })
        step("two themes")

    elseif phase == "two themes" and clock > 0.3 then
        local first = world:query({ with = { "ui/theme" } })[1]:get("ui/theme").icon_bg
        suite.assert_test("S11_with_two_themes_a_node_is_painted_from_one",
            #world:query({ with = { "ui/theme" } }) == 2
                and is(node(world, "icon"):get("BackgroundColor"), first.r, first.g, first.b, first.a),
            show(node(world, "icon"):get("BackgroundColor")))
        commands:entity(world:query({ with = { "zz/theme" } })[1]:id()):despawn()
        node(world, "panel"):remove("ui/style")
        step("unstyled")

    elseif phase == "unstyled" and clock > 0.3 then
        local panel = node(world, "panel")
        suite.assert_test("S10_removing_ui_style_takes_off_its_colors",
            panel:get("BackgroundColor") == nil and panel:get("TextColor") == nil and panel:get("BorderColor") == nil, "")
        phase = "done"
        suite.finish("StyleSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("S0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("StyleSuite")
    end
end):in_set("zz/style_suite")
