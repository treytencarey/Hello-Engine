-- --host
-- `input` goes with `player`, in a world that is both sides, and takes `input/game` and `input/ui` with
-- it, on every one of a crowd taken off a frame apart. The cleanups of what `player` also takes off run
-- around that: each must leave those alone once `input` has gone, and it depends on the order they run
-- in, so a run shows it on some entities or none. The same with everything taken off at once from a
-- system in First, among those cleanups. And where `input` stays and only a mod leaves, the mod's
-- bindings really do go, and no one else's. A mod that arrives on an entity with no `input` binds
-- nothing until `input` comes.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("PlayerInputGoneSuite")

local CAMERAS = {
    { "camera/first_person", "first_person" },
    { "camera/third_person", "third_person" },
    { "camera/2d", "camera_2d" },
}

local LEAVERS = {
    { "abilities", "abilities" },
    { "movement", "movement" },
    { "camera/first_person", "first_person" },
    { "camera/third_person", "third_person" },
    { "sidebar", "sidebar" },
    { "camera/2d", "camera_2d" },
}

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "both" }, ["core/net/sync"] = false })
    for i = 1, 20 do
        commands:spawn({
            ["zz/crowd"] = { n = i },
            player = { client_id = i, spawn_index = 1 },
            ["core/net/local"] = {},
            ["core/net/sync"] = false,
            Transform = { translation = { x = i * 10, y = 1, z = 0 } },
        })
    end
    -- All of what binds, on each, taken off together in First. An entity has one camera at a time.
    for i = 1, 21 do
        commands:spawn({
            ["zz/together"] = { n = i },
            abilities = { zzkey = { key = "KeyZ" } },
            movement = {},
            [CAMERAS[i % 3 + 1][1]] = {},
            sidebar = {},
            input = {},
            ["input/mode"] = { mode = "input/game" },
            ["core/net/local"] = {},
            ["core/net/sync"] = false,
            Transform = { translation = { x = i * 10, y = 1, z = 300 } },
        })
    end
    -- The sidebar open when `input` goes on its own, and closed after.
    commands:spawn({
        ["zz/closer"] = {},
        sidebar = {},
        input = {},
        ["input/mode"] = { mode = "input/game" },
        ["core/net/local"] = {},
        ["core/net/sync"] = false,
        Transform = { translation = { x = 0, y = 1, z = 600 } },
    })
    -- Input stays on these, with a group of someone else's.
    for _, leaver in ipairs(LEAVERS) do
        commands:spawn({
            ["zz/leaver"] = { name = leaver[1] },
            [leaver[1]] = leaver[1] == "abilities" and { zzkey = { key = "KeyZ" } } or {},
            input = {},
            ["input/mode"] = { mode = "input/game" },
            ["input/game"] = { zzother = { go = { key = "KeyO" } } },
            ["core/net/local"] = {},
            ["core/net/sync"] = false,
            Transform = { translation = { x = -100, y = 1, z = 0 } },
        })
    end
    -- Opened with no `input`.
    commands:spawn({
        ["zz/opener"] = {},
        sidebar = {},
        ["core/net/local"] = {},
        ["core/net/sync"] = false,
        Transform = { translation = { x = -300, y = 1, z = 0 } },
    })
    -- No `input` on these yet.
    for _, leaver in ipairs(LEAVERS) do
        commands:spawn({
            ["zz/bare"] = { name = leaver[1] },
            [leaver[1]] = leaver[1] == "abilities" and { zzkey = { key = "KeyZ" } } or {},
            ["core/net/local"] = {},
            ["core/net/sync"] = false,
            Transform = { translation = { x = -200, y = 1, z = 0 } },
        })
    end
end)

local function leaver_row(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/leaver" },
        optional = { "input", "input/game" },
    })) do
        if e:get("zz/leaver").name == name then
            return e
        end
    end
end

local function bare_row(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/bare" },
        optional = { "input/game" },
    })) do
        if e:get("zz/bare").name == name then
            return e
        end
    end
end

local phase, clock, i = "wait", 0, 0
local bound = 0

local together_n = nil
app:add_systems(First, {
    Query[{ with = { "zz/together" } }],
    Commands,
}, function(together, commands)
    if together_n == nil then
        return
    end
    together_n = together_n + 1
    for _, e in ipairs(together:iter()) do
        local n = e:get("zz/together").n
        if n == together_n then
            commands:entity(e:id()):remove("abilities", "movement", CAMERAS[n % 3 + 1][1], "sidebar", "input")
        end
    end
end):in_set("zz/player_input_gone_together")

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + world:delta_time()
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "wait" and clock > 3 then
        local crowd = world:query({ with = { "zz/crowd" }, optional = { "input/game", "input/ui" } })
        bound = 0
        for _, e in ipairs(crowd) do
            local game = e:get("input/game") or {}
            if game.abilities and game.movement and game.third_person and game.sidebar and e:has("input/ui") then
                bound = bound + 1
            end
        end
        suite.assert_test("IG1_the_crowd_has_every_group_bound", bound == 20, "bound " .. bound)
        for _, leaver in ipairs(LEAVERS) do
            local game = leaver_row(world, leaver[1]):get("input/game") or {}
            suite.assert_test("IG2_" .. leaver[2] .. "_binds_its_group", game[leaver[2]] ~= nil, "")
            commands:entity(leaver_row(world, leaver[1]):id()):remove(leaver[1])
            local bare = bare_row(world, leaver[1])
            suite.assert_test("IG10_" .. leaver[2] .. "_with_no_input_binds_nothing", not bare:has("input/game"), "")
            commands:entity(bare:id()):patch({ input = {} })
        end
        local together = world:query({ with = { "zz/together" }, optional = { "input/game" } })
        local all = 0
        for _, e in ipairs(together) do
            local game = e:get("input/game") or {}
            if game.movement and game[CAMERAS[e:get("zz/together").n % 3 + 1][2]] and game.sidebar and game.abilities then
                all = all + 1
            end
        end
        suite.assert_test("IG1b_those_taken_off_together_have_every_group_bound", all == 21, "bound " .. all)
        together_n = 0
        local closer = world:query({ with = { "zz/closer" } })[1]
        commands:entity(closer:id()):patch({ ["sidebar/open"] = {} })
        commands:entity(world:query({ with = { "zz/opener" } })[1]:id()):patch({ ["sidebar/open"] = {} })
        step("strip")

    elseif phase == "strip" then
        i = i + 1
        for _, e in ipairs(world:query({ with = { "zz/crowd" } })) do
            if e:get("zz/crowd").n == i then
                commands:entity(e:id()):remove("player")
            end
        end
        if i == 5 then
            commands:entity(world:query({ with = { "zz/closer" } })[1]:id()):remove("input")
        elseif i == 10 then
            commands:entity(world:query({ with = { "zz/closer" } })[1]:id()):remove("sidebar/open")
        end
        if i >= 21 then
            step("after")
        end

    elseif phase == "after" and clock > 2 then
        local game_back, ui_back, input_left = 0, 0, 0
        for _, e in ipairs(world:query({ with = { "zz/crowd" }, optional = { "input", "input/game", "input/ui" } })) do
            if e:has("input") then
                input_left = input_left + 1
            elseif e:has("input/game") then
                game_back = game_back + 1
            end
            if not e:has("input") and e:has("input/ui") then
                ui_back = ui_back + 1
            end
        end
        suite.assert_test("IG3_input_goes_with_the_player", input_left == 0, "left " .. input_left)
        suite.assert_test("IG4_and_input_game_stays_gone", game_back == 0, game_back .. " of 20 came back")
        suite.assert_test("IG5_and_input_ui_too", ui_back == 0, ui_back .. " of 20 came back")
        local input_t, game_t, ui_t = 0, 0, 0
        for _, e in ipairs(world:query({ with = { "zz/together" }, optional = { "input", "input/game", "input/ui" } })) do
            input_t = input_t + (e:has("input") and 1 or 0)
            game_t = game_t + (e:has("input/game") and 1 or 0)
            ui_t = ui_t + (e:has("input/ui") and 1 or 0)
        end
        suite.assert_test("IG8_taken_off_together_in_first_nothing_comes_back", input_t == 0 and game_t == 0 and ui_t == 0,
            string.format("input %d, game %d, ui %d of 21", input_t, game_t, ui_t))
        local closer = world:query({ with = { "zz/closer" }, optional = { "input", "input/game", "input/ui", "input/mode" } })[1]
        suite.assert_test("IG9_closing_the_sidebar_brings_no_input_back", not closer:has("input") and not closer:has("input/game") and not closer:has("input/ui"), "")
        suite.assert_test("IG9b_and_gives_no_game_input_back", (closer:get("input/mode") or {}).mode ~= "input/game", "")
        local opener = world:query({ with = { "zz/opener" }, optional = { "input/mode" } })[1]
        suite.assert_test("IG12_opening_with_no_input_writes_no_mode", not opener:has("input/mode"), "")
        for _, leaver in ipairs(LEAVERS) do
            local e = leaver_row(world, leaver[1])
            local game = e:get("input/game") or {}
            suite.assert_test("IG6_" .. leaver[2] .. "_gone_with_input_staying_its_group_goes", e:has("input") and game[leaver[2]] == nil, "")
            suite.assert_test("IG7_" .. leaver[2] .. "_and_the_others_stay", game.zzother ~= nil, "")
            suite.assert_test("IG11_" .. leaver[2] .. "_binds_when_input_comes", (bare_row(world, leaver[1]):get("input/game") or {})[leaver[2]] ~= nil, "")
        end
        phase = "done"
        suite.finish("PlayerInputGoneSuite")
    end

    if phase ~= "done" and clock > 12 then
        suite.assert_test("IG0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 12 s")
        phase = "done"
        suite.finish("PlayerInputGoneSuite")
    end
end):in_set("zz/player_input_gone_suite")
