-- --host (windowed: UI layout needs a window)
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("NotificationSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:spawn({ Camera2d = {}, Camera = { order = 0 } })
end)

-- What a script spawns is linked to its file. Another mod spawns a notification; moved
-- under the overlay, it becomes the notification mod's. The link names that other mod's file.
local Instances = require("modules/core/instances.lua")
local NOTICE = "modules/zz_notice/init.lua"
Instances.mark_mod_script(NOTICE)
local function notice(commands, name, config)
    return commands:spawn({ ["zz/note"] = { name = name }, notification = config, ["core/script/owner"] = Instances.script_entity(NOTICE) })
end

local function note(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/note" },
        optional = { "notification", "notification/alive", "notification/fade", "ui/style", "Node", "ChildOf" },
    })) do
        if e:get("zz/note").name == name then
            return e
        end
    end
end

local function line(world, name)
    for _, t in ipairs(world:query({ with = { "zz/line" }, optional = { "ui/style" } })) do
        if t:get("zz/line").name == name then
            return t
        end
    end
end

local function overlays(world) return #world:query({ with = { "notification/overlay" } }) end
local function overlay_id(world) return world:query({ with = { "notification/overlay" } })[1]:id() end

local phase, clock = "spawn", 0
local min_alpha, mid_alpha, mid_samples = 1, 0, 0

-- Watch the fade as it happens: the lowest alpha the slow card's text reaches, and the
-- highest alpha seen in the middle of the fade (an ease-out is already low there).
app:add_systems(Last, { World }, function(world)
    local t = line(world, "slow")
    local style = t and t:get("ui/style")
    local slow = note(world, "slow")
    local fade = slow and slow:get("notification/fade")
    if style and style.alpha then
        min_alpha = math.min(min_alpha, style.alpha)
        if fade and fade.elapsed / fade.duration >= 0.35 and fade.elapsed / fade.duration <= 0.65 then
            mid_alpha = math.max(mid_alpha, style.alpha)
            mid_samples = mid_samples + 1
        end
    end
end):in_set("zz/notification_suite_watch")

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        notice(commands, "quick", { timeout = 1.0 })
        notice(commands, "kept", { width = 320, accent = "text_good" })
        notice(commands, "slow", { fade = 0.5 })
        step("shown")

    elseif phase == "shown" and clock > 0.3 then
        local quick, kept = note(world, "quick"), note(world, "kept")
        local n = kept:get("notification")
        suite.assert_test("N1_a_notification_becomes_a_card_with_defaults",
            quick:get("Node") ~= nil and quick:get("notification").width == 260
                and quick:get("notification").accent == "accent" and quick:get("notification").fade == 0.25
                and quick:get("ui/style").border_left == "accent", "")
        suite.assert_test("N2_config_sets_width_and_accent",
            kept:get("Node").width.Px == 320 and kept:get("ui/style").border_left == "text_good"
                and n.width == 320, "")
        local pick = world:query({ with = { "notification/overlay", "Pickable" } })[1]
        suite.assert_test("N3c_the_overlay_lets_the_pointer_through",
            pick ~= nil and pick:get("Pickable").should_block_lower == false and pick:get("Pickable").is_hoverable == false,
            "pickable=" .. tostring(pick ~= nil))
        suite.assert_test("N3_notifications_share_one_overlay",
            overlays(world) == 1 and quick:get("ChildOf") == overlay_id(world) and kept:get("ChildOf") == overlay_id(world)
                and note(world, "slow"):get("ChildOf") == overlay_id(world), "overlays=" .. overlays(world))
        suite.assert_test("N4_a_timeout_runs_as_a_cooldown", quick:has("notification/alive")
            and not kept:has("notification/alive"), "")
        local text = commands:spawn({
            ["zz/line"] = { name = "slow" },
            Text = { text = "hello" },
            ["ui/style"] = { text = "text" },
        }):id()
        commands:entity(note(world, "slow"):id()):add_child(text)
        notice(commands, "late", {})
        step("late")

    elseif phase == "late" and clock > 0.3 then
        suite.assert_test("N3b_a_later_notification_joins_the_same_overlay",
            overlays(world) == 1 and note(world, "late"):get("ChildOf") == overlay_id(world),
            "overlays=" .. overlays(world))
        commands:entity(note(world, "late"):id()):despawn()
        step("timing out")

    elseif phase == "timing out" and clock > 1.0 then
        suite.assert_test("N5_it_goes_when_the_timeout_and_fade_are_over",
            note(world, "quick") == nil and note(world, "kept") ~= nil, "")
        note(world, "slow"):patch({ notification = { dismiss = true } })
        step("dismissing")

    elseif phase == "dismissing" and clock > 0.25 then
        local slow = note(world, "slow")
        local fade = slow:get("notification/fade")
        local height = slow:get("Node").height
        suite.assert_test("N6_dismiss_fades_the_card_and_its_styled_content_and_shrinks_it",
            fade ~= nil and min_alpha < 0.9 and height ~= nil and height.Px ~= nil and height.Px < fade.height,
            string.format("alpha=%.2f", min_alpha))
        -- the extending mod keeps updating it: the fade must not start over
        note(world, "slow"):patch({ notification = { width = 300 } })
        step("dismissed")

    elseif phase == "dismissed" and clock > 0.45 then
        suite.assert_test("N6b_the_fade_eases_out", mid_samples > 0 and mid_alpha < 0.35,
            string.format("mid alpha=%.2f over %d samples", mid_alpha, mid_samples))
        suite.assert_test("N7_a_dismissed_notification_goes_after_its_fade",
            note(world, "slow") == nil and line(world, "slow") == nil, "")
        local kept = note(world, "kept")
        suite.assert_test("N8_without_a_timeout_it_stays", kept ~= nil and kept:has("Node"), "")
        commands:entity(kept:id()):despawn()
        step("despawned")

    elseif phase == "despawned" and clock > 0.3 then
        suite.assert_test("N9_despawning_the_last_notification_removes_the_overlay",
            #world:query({ with = { "notification" } }) == 0 and overlays(world) == 0, "overlays=" .. overlays(world))
        notice(commands, "again", { timeout = 5 })
        notice(commands, "other", {})
        step("again")

    elseif phase == "again" and clock > 0.3 then
        suite.assert_test("N10_a_new_notification_gets_a_new_overlay",
            overlays(world) == 1 and note(world, "again"):get("ChildOf") == overlay_id(world), "")
        note(world, "again"):remove("notification")
        step("removed")

    elseif phase == "removed" and clock > 0.3 then
        suite.assert_test("N11_removing_notification_removes_the_card",
            note(world, "again") == nil and note(world, "other") ~= nil and overlays(world) == 1,
            "overlays=" .. overlays(world))
        commands:entity(note(world, "other"):id()):despawn()
        step("last gone")

    elseif phase == "last gone" and clock > 0.3 then
        suite.assert_test("N12_the_overlay_goes_with_the_last_notification",
            overlays(world) == 0 and #world:query({ with = { "zz/note" } }) == 0, "overlays=" .. overlays(world))
        phase = "done"
        suite.finish("NotificationSuite")
    end

    if phase ~= "done" and clock > 10 then
        suite.assert_test("N0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("NotificationSuite")
    end
end):in_set("zz/notification_suite")
