-- --host
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local On = require("bevy::ecs::prelude::On")
local Time = require("bevy::time::Time")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("NoisemakerServerSuite")

-- A body as a walker has one: Rapier moves it from a `Velocity3d` something writes every frame.
local function body(commands, name, z, linvel, noisemaker)
    commands:spawn({
        ["zz/name"] = { name = name },
        ["zz/driven"] = { linvel = linvel },
        ["ai/noisemaker"] = noisemaker,
        Transform = { translation = { x = 0, y = 0, z = z } },
        RigidBody3d = "Dynamic",
        Collider3d = { ball = { radius = 0.2 } },
        GravityScale3d = { value = 0 },
        Velocity3d = { linvel = linvel, angvel = { x = 0, y = 0, z = 0 } },
        ["core/net/sync"] = false,
    })
end

-- A body only physics writes: gravity changes its `Velocity3d` and no system touches it.
local function falling(commands, name, z, x)
    commands:spawn({
        ["zz/name"] = { name = name },
        ["ai/noisemaker"] = { interval = 0.2 },
        Transform = { translation = { x = 0, y = 0, z = z } },
        RigidBody3d = "Dynamic",
        Collider3d = { ball = { radius = 0.2 } },
        Velocity3d = { linvel = { x = x, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
        ["core/net/sync"] = false,
    })
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    body(commands, "plain", 400, { x = 0, y = 0, z = 0 }, {})
    -- 3 m/s only when x and z both count
    body(commands, "walker", 100, { x = 1.8, y = 0, z = 2.4 },
        { interval = 0.4, loudness = 0.8, kind = "creak", run_interval = 0.5 })
    body(commands, "runner", 120, { x = 6, y = 0, z = 0 },
        { interval = 0.4, loudness = 0.8, kind = "creak", run_interval = 0.5 })
    body(commands, "slow", 140, { x = 2, y = 0, z = 0 }, { interval = 0.1 })
    body(commands, "faint", 160, { x = 0.5, y = 0, z = 0 }, { quiet_speed = 0, interval = 100 })
    -- a timer that outlasts the suite: one sound, ever
    body(commands, "hush", 180, { x = 3, y = 0, z = 0 }, { interval = 1000, kind = "hush" })
    falling(commands, "drop", 200, 0)
    falling(commands, "barrel", 220, 3)
    -- Keeps one velocity, and nothing writes it.
    commands:spawn({
        ["zz/name"] = { name = "coast" },
        ["ai/noisemaker"] = { interval = 0.2 },
        Transform = { translation = { x = 0, y = 0, z = 260 } },
        RigidBody3d = "Dynamic",
        Collider3d = { ball = { radius = 0.2 } },
        GravityScale3d = { value = 0 },
        Velocity3d = { linvel = { x = 3, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
        ["core/net/sync"] = false,
    })
    -- As `player/spawner` builds a server's player: kinematic, a `Velocity3d` nothing writes,
    -- and its Transform eased along from outside.
    commands:spawn({
        ["zz/name"] = { name = "player" },
        ["zz/slid"] = { speed = 6 },
        ["ai/noisemaker"] = { interval = 0.2 },
        Transform = { translation = { x = 0, y = 0, z = 240 } },
        RigidBody3d = "KinematicPositionBased",
        Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
        LockedAxes3d = "ROTATION_LOCKED",
        Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
        ["core/net/sync"] = false,
    })
end)

app:add_systems(Update, {
    Query[{ with = { "zz/driven", Mut["Velocity3d"] } }],
}, function(driven)
    for _, e in ipairs(driven:iter_mut()) do
        e:patch({ Velocity3d = { linvel = e:get("zz/driven").linvel } })
    end
end):in_set("zz/noisemaker_suite_drive")

app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "zz/slid", Mut["Transform"] } }],
}, function(time, slid)
    for _, e in ipairs(slid:iter_mut()) do
        local at = e:get("Transform").translation
        e:patch({ Transform = { translation = { x = at.x + e:get("zz/slid").speed * time:delta_secs() } } })
    end
end):in_set("zz/noisemaker_suite_slide")

-- Every sound, by who made it, with where that entity was as it was heard.
local sounds = {}
app:add_observer(On["ai/noisemaker/sound"], {
    Query[{ with = { "zz/name", "Transform" } }],
}, function(event, names)
    local e = names:get(event.entity)
    local name = e and e:get("zz/name").name or "unknown"
    sounds[name] = sounds[name] or {}
    table.insert(sounds[name], {
        x = event.x,
        y = event.y,
        z = event.z,
        loudness = event.loudness,
        kind = event.kind,
        at = e and e:get("Transform").translation,
    })
end)

-- The watcher says when it saw the mod's file change: this is how a case knows the reload ran. A
-- reload writes nothing to a row that misses no field.
local refills = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("ai/noisemaker/server/init.lua", 1, true) then
            refills = refills + 1
        end
    end
end):in_set("zz/noisemaker_suite_refills")

local function count(name) return #(sounds[name] or {}) end

local function near(a, b, tolerance) return a ~= nil and math.abs(a - b) < (tolerance or 1e-3) end

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/name" },
        optional = { "ai/noisemaker", "ai/noisemaker/state", "Velocity3d", "Transform" },
    })) do
        if e:get("zz/name").name == name then
            return e
        end
    end
end

local phase, clock = "filled", 0
local counted, refills_before = {}, 0

app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "filled" and named(world, "plain") and named(world, "plain"):get("ai/noisemaker").interval ~= nil
        and named(world, "walker"):get("ai/noisemaker").interval ~= nil then
        local plain = named(world, "plain"):get("ai/noisemaker")
        local walker = named(world, "walker"):get("ai/noisemaker")
        suite.assert_test("N1_missing_fields_get_defaults",
            plain.interval == 0.5 and plain.loudness == 1 and plain.kind == "footstep" and plain.quiet_speed == 2.5
                and plain.run_speed == 5 and near(plain.min_loudness, 0.3) and near(plain.run_interval, 0.7), "")
        suite.assert_test("N2_fields_given_stay_beside_the_defaults",
            near(walker.interval, 0.4) and near(walker.loudness, 0.8) and walker.kind == "creak"
                and near(walker.run_interval, 0.5) and walker.quiet_speed == 2.5, "")
        sounds = {}
        step("listening")

    elseif phase == "listening" and clock > 2.1 then
        local walker = sounds.walker or {}
        local first = walker[1] or {}
        suite.assert_test("N3_moving_above_quiet_speed_makes_a_sound_of_its_kind",
            #walker > 0 and first.kind == "creak", "walker sounds " .. #walker)
        suite.assert_test("N4_a_sound_says_where_it_was_made",
            first.at ~= nil and near(first.x, first.at.x, 1) and near(first.y, first.at.y, 1) and near(first.z, first.at.z, 1)
                and first.z > 99,
            string.format("x=%s y=%s z=%s", tostring(first.x), tostring(first.y), tostring(first.z)))
        suite.assert_test("N5_loudness_grows_with_speed_up_to_run_speed", near(first.loudness, 0.8 * 3 / 5, 1e-2),
            "walker loudness " .. tostring(first.loudness))
        local runner = (sounds.runner or {})[1] or {}
        suite.assert_test("N6_at_run_speed_it_is_as_loud_as_it_gets", near(runner.loudness, 0.8),
            "runner loudness " .. tostring(runner.loudness))
        local faint = (sounds.faint or {})[1] or {}
        suite.assert_test("N7_it_never_drops_below_min_loudness", near(faint.loudness, 0.3),
            "faint loudness " .. tostring(faint.loudness))
        suite.assert_test("N8_below_quiet_speed_it_is_silent", count("slow") == 0, "slow sounds " .. count("slow"))
        suite.assert_test("N9_standing_still_is_silent", count("plain") == 0, "plain sounds " .. count("plain"))
        -- 2.1 s at 0.4 s apart, and at 0.2 s apart running
        suite.assert_test("N10_it_waits_its_interval_between_sounds", #walker >= 4 and #walker <= 6,
            "walker sounds " .. #walker)
        suite.assert_test("N11_running_repeats_faster", count("runner") >= 9 and count("runner") <= 11,
            "runner sounds " .. count("runner"))
        suite.assert_test("N12_rising_or_falling_is_not_moving", count("drop") == 0, "drop sounds " .. count("drop"))
        suite.assert_test("N13_a_velocity_only_physics_writes_makes_sounds_too", count("barrel") >= 8 and count("barrel") <= 11,
            "barrel sounds " .. count("barrel"))
        suite.assert_test("N13b_a_server_player_moved_only_through_its_transform_makes_sounds",
            count("player") >= 8 and count("player") <= 16, "player sounds " .. count("player"))
        suite.assert_test("N13c_only_a_change_runs_it", count("coast") <= 1, "coast sounds " .. count("coast"))
        suite.assert_test("N14_one_timer_per_entity", count("hush") == 1, "hush sounds " .. count("hush"))
        counted.walker, counted.hush = count("walker"), count("hush")
        refills_before = refills
        -- The mod's own file is written again with the same bytes: the watcher reloads it.
        local path = "assets/modules/ai/noisemaker/server/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloaded")

    -- The watcher polls the file every 5 s.
    elseif phase == "reloaded" and refills > refills_before then
        counted.walker = count("walker")
        step("after reload")

    elseif phase == "after reload" and clock > 2.1 then
        local hush = named(world, "hush")
        suite.assert_test("N15_a_reload_keeps_the_fields_given", hush:get("ai/noisemaker").interval == 1000
            and hush:get("ai/noisemaker").kind == "hush", "interval " .. tostring(hush:get("ai/noisemaker").interval))
        suite.assert_test("N16_a_reload_keeps_the_timer", count("hush") == counted.hush, "hush sounds " .. count("hush"))
        local since = count("walker") - counted.walker
        suite.assert_test("N17_after_a_reload_it_sounds_at_the_same_rate", since >= 4 and since <= 6,
            "walker sounds since the reload " .. since)
        commands:entity(named(world, "walker"):id()):remove("ai/noisemaker")
        counted.runner = count("runner")
        step("removed")

    elseif phase == "removed" and clock > 0.6 then
        local walker = named(world, "walker")
        counted.walker = count("walker")
        suite.assert_test("N18_removing_it_takes_its_state_and_leaves_the_body",
            not walker:has("ai/noisemaker") and not walker:has("ai/noisemaker/state") and walker:has("Velocity3d"), "")
        suite.assert_test("N19_the_others_keep_sounding", count("runner") > counted.runner, "")
        step("quiet")

    elseif phase == "quiet" and clock > 0.6 then
        suite.assert_test("N20_removed_it_is_silent", count("walker") == counted.walker,
            "walker sounds " .. count("walker") .. " after " .. counted.walker)
        phase = "done"
        suite.finish("NoisemakerServerSuite")
    end

    if phase ~= "done" and clock > 12 then
        suite.assert_test("N0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 12 s")
        phase = "done"
        suite.finish("NoisemakerServerSuite")
    end
end):in_set("zz/noisemaker_suite")
