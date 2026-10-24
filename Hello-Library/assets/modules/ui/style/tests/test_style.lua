-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("StyleSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ ["ui/theme/dark"] = {} })
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
        commands:spawn({
            ["zz/node"] = { name = "icon" },
            Node = {},
            Button = {},
            ["ui/style"] = { background = "icon_bg", hover = "icon_hover", press = "icon_active" },
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
        suite.assert_test("S6_a_button_starts_on_its_background",
            is(node(world, "icon"):get("BackgroundColor"), 0.15, 0.15, 0.18, 1),
            show(node(world, "icon"):get("BackgroundColor")))
        node(world, "icon"):patch({ Interaction = "Hovered" })
        step("hovered")

    elseif phase == "hovered" then
        -- read in the next frame: the pointer system may set Interaction back
        suite.assert_test("S7_hover_uses_the_hover_role",
            is(node(world, "icon"):get("BackgroundColor"), 0.22, 0.22, 0.26, 1),
            show(node(world, "icon"):get("BackgroundColor")))
        node(world, "icon"):patch({ Interaction = "Pressed" })
        step("pressed")

    elseif phase == "pressed" then
        suite.assert_test("S8_press_uses_the_press_role",
            is(node(world, "icon"):get("BackgroundColor"), 0.25, 0.35, 0.5, 1),
            show(node(world, "icon"):get("BackgroundColor")))
        node(world, "icon"):patch({ Interaction = "None" })
        step("released")

    elseif phase == "released" and clock > 0.2 then
        suite.assert_test("S9_leaving_returns_to_the_background",
            is(node(world, "icon"):get("BackgroundColor"), 0.15, 0.15, 0.18, 1),
            show(node(world, "icon"):get("BackgroundColor")))
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
