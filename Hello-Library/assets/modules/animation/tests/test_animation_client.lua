-- --host (windowed: a headless run has no AnimationPlugin, so no AnimationGraph)
-- `animation` on a client, with the Placeholder-Character model.
--
--   AN1 each character gets its own model, a child holding its scene (`animation/model`)
--   AN2 each gets its own graph, with a node per clip and the clip each node plays
--   AN3 the scene's AnimationPlayer is linked: marked `animation/player`, given the graph
--   AN4 standing still it plays idle; moving across, walk (faster for faster); rising, jump;
--       dropping, fall
--   AN4b walking on past the clip's length, speeding up halfway, it keeps walking: the clip
--        loops at its new speed and is not restarted while the state stays the same
--   AN4c a character moved by physics (its body's velocity, stepped at a fixed rate) walks
--        steadily: its state does not flicker between frames that moved and frames that did not
--   AN5 `animation/action` wins while it is there; without it the motion's state returns
--   AN10 a later change to `animation` that names nothing new (`walk_speed`) replaces nothing
--   AN11 a new scene replaces the model; a new clip rebuilds the graph, and the model stays
--   AN12 a clip taken out rebuilds the graph without it (which graph a linked player holds
--        cannot be read: a created asset's handle reads back as an opaque reflect value)
--   AN6 a changed clip file rebuilds nothing: Bevy refills the clip in place, and every
--       character keeps its model and graph
--   AN9 the mod itself is edited (hot reload): each character still has one model, a graph
--       and a linked player, and plays
--   AN7 taken off an entity that stays: its model and its parts go
require("modules/core/init.lua")
local AssetServer = require("bevy::asset::AssetServer")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("AnimationClientSuite")
local watcher = require("modules/core/hot_reload/watcher.lua")
local Time = require("bevy::time::Time")

-- An immediate watcher, for AN9's edit.
local fw = define_resource("_FileWatcherState", {})
fw.poll_interval = 0
fw.debounce = 0

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
end)

local function named(world, name)
    for _, e in ipairs(world:query({
        with = { "zz/char" },
        optional = { "animation/graph", "animation/playing", "Transform" },
    })) do
        if e:get("zz/char").name == name then return e end
    end
end

local function parts(world, carrier, comp)
    return world:query({ with = { comp }, iter_many = world:descendants(carrier) })
end

--- How long the player's running clip has played (`start()` resets it to 0).
local function elapsed_of(world, player)
    local ap = world:get_entity(player:id()):get("AnimationPlayer") or {}
    for _, active in pairs(ap.active_animations or {}) do return active.elapsed end
end

--- The watcher's key for a file it has Bevy reload.
local function key_of(file)
    for path in pairs(fw.bevy_assets or {}) do
        if path:sub(-#file) == file then return path end
    end
end

local phase, clock = "spawn", 0
local moving = nil   -- { name, velocity } moved every frame
local before = {}

-- The suite's clock is the mod's: Bevy's `Time`, so what it moves in a frame is what
-- `animation/state` measures over that frame.
app:add_systems(Update, { World, Res[Time], Res[AssetServer], Commands }, function(world, time, asset_server, commands)
    local dt = time:delta_secs()
    clock = clock + dt
    local function step(next_phase) phase, clock = next_phase, 0 end

    if moving then
        local e = named(world, moving.name)
        local t = e and e:get("Transform")
        if t then
            local v = moving.velocity
            e:patch({ Transform = { translation = {
                x = t.translation.x + v.x * dt, y = t.translation.y + v.y * dt, z = t.translation.z + v.z * dt,
            } } })
        end
    end

    if phase == "spawn" then
        commands:spawn({ ["zz/char"] = { name = "a" }, animation = {}, Transform = { translation = { x = 0, y = 1, z = 0 } } })
        commands:spawn({ ["zz/char"] = { name = "b" }, animation = {}, Transform = { translation = { x = 5, y = 1, z = 0 } } })
        step("loaded")

    elseif phase == "loaded" then
        local a, b = named(world, "a"), named(world, "b")
        local linked = a and b and #parts(world, a:id(), "animation/player") > 0 and #parts(world, b:id(), "animation/player") > 0
        if not linked and clock < 10 then return end
        local ok1 = true
        for _, c in ipairs({ a, b }) do
            local models = parts(world, c:id(), "animation/model")
            ok1 = ok1 and #models == 1
                and models[1]:get("animation/model").scene == "Placeholder-Character/Model-Idle.glb#Scene0"
        end
        suite.assert_test("AN1_each_character_gets_its_own_model", ok1,
            string.format("a: models=%d", #parts(world, a:id(), "animation/model")))
        local ga, gb = a:get("animation/graph") or {}, b:get("animation/graph") or {}
        local count = 0
        for _ in pairs(ga.nodes or {}) do count = count + 1 end
        suite.assert_test("AN2_each_gets_its_own_graph_with_a_node_per_clip",
            count == 4 and ga.nodes.walk ~= nil and gb.handle ~= nil and ga.handle ~= gb.handle
                and (ga.clips or {}).walk == "Placeholder-Character/Model-Walk.glb#Animation0",
            "nodes=" .. count .. " walk=" .. tostring((ga.clips or {}).walk))
        local player = parts(world, a:id(), "animation/player")[1]
        local full = player and world:get_entity(player:id())
        suite.assert_test("AN3_the_scenes_player_is_linked",
            full ~= nil and full:get("AnimationGraphHandle") ~= nil and full:get("AnimationTransitions") ~= nil, "")
        step("idle")

    elseif phase == "idle" then
        if clock < 0.3 then return end
        before.idle = (named(world, "a"):get("animation/playing") or {}).state
        moving = { name = "a", velocity = { x = 3, y = 0, z = 0 } }
        step("walk")

    elseif phase == "walk" then
        if clock < 0.3 then return end
        local a = named(world, "a")
        local p = a:get("animation/playing") or {}
        before.walk, before.walk_speed = p.state, p.speed
        -- The player itself plays the walk node, not only the state saying so.
        local player = parts(world, a:id(), "animation/player")[1]
        local ok_p, on = pcall(function()
            return world:get_entity(player:id()).AnimationPlayer:is_playing_animation(a:get("animation/graph").nodes.walk)
        end)
        before.walk_playing = ok_p and on
        before.walk_changes = 0
        before.walk_elapsed = elapsed_of(world, player)
        step("walk_long")

    elseif phase == "walk_long" then
        for _ in ipairs(world:query({ changed = { "animation/playing" }, with = { "zz/char" } })) do
            before.walk_changes = before.walk_changes + 1
        end
        -- Halfway, it speeds up: a new speed for the same clip.
        if clock >= 1.2 and not before.sped_up then
            before.sped_up = true
            moving = { name = "a", velocity = { x = 4.5, y = 0, z = 0 } }
        end
        if clock < 2.5 then return end
        local a = named(world, "a")
        local player = parts(world, a:id(), "animation/player")[1]
        local node = a:get("animation/graph").nodes.walk
        local ok_p, on = pcall(function()
            return world:get_entity(player:id()).AnimationPlayer:is_playing_animation(node)
        end)
        -- Not restarted: the clip has run the whole time it walked.
        local ran = (elapsed_of(world, player) or 0) - (before.walk_elapsed or 0)
        local now_speed
        for _, active in pairs((world:get_entity(player:id()):get("AnimationPlayer") or {}).active_animations or {}) do
            now_speed = active.speed
        end
        suite.assert_test("AN4b_it_keeps_walking_past_the_clips_length",
            ok_p and on and ran > 2.0 and math.abs((now_speed or 0) - 0.75) < 0.05,
            string.format("playing=%s ran=%.2f speed=%s state_changes=%d", tostring(ok_p and on), ran,
                tostring(now_speed), before.walk_changes))
        moving = nil
        -- As a player moves: a dynamic body, its velocity stepped by physics.
        commands:spawn({
            ["zz/char"] = { name = "c" }, animation = {},
            Transform = { translation = { x = -5, y = 1, z = 0 } },
            RigidBody3d = "Dynamic",
            Collider3d = { capsule_y = { radius = 0.4, half_height = 0.5 } },
            LockedAxes3d = "ROTATION_LOCKED",
            GravityScale3d = 0,
            Velocity3d = { linvel = { x = 3, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
        })
        before.c_changes = 0
        step("physics_walk")

    elseif phase == "physics_walk" then
        for _, e in ipairs(world:query({ changed = { "animation/playing" }, with = { "zz/char" } })) do
            if e:get("zz/char").name == "c" then before.c_changes = before.c_changes + 1 end
        end
        if clock < 3.0 then return end
        local c = named(world, "c")
        local p = c and c:get("animation/playing") or {}
        -- One change at most: from nothing to walk once its model has loaded.
        suite.assert_test("AN4c_a_character_moved_by_physics_walks_steadily",
            p.state == "walk" and before.c_changes <= 2,
            string.format("state=%s changes=%d", tostring(p.state), before.c_changes))
        world:get_entity(c:id()):patch({ Velocity3d = { linvel = { x = 0, y = 0, z = 0 } } })
        moving = { name = "a", velocity = { x = 0, y = 4, z = 0 } }
        step("jump")

    elseif phase == "jump" then
        if clock < 0.3 then return end
        before.jump = (named(world, "a"):get("animation/playing") or {}).state
        moving = { name = "a", velocity = { x = 0, y = -4, z = 0 } }
        step("fall")

    elseif phase == "fall" then
        if clock < 0.3 then return end
        local fall = (named(world, "a"):get("animation/playing") or {}).state
        moving = nil
        suite.assert_test("AN4_its_motion_picks_the_clip",
            before.idle == "idle" and before.walk == "walk" and before.walk_playing == true
                and math.abs((before.walk_speed or 0) - 0.5) < 0.1
                and before.jump == "jump" and fall == "fall",
            string.format("idle=%s walk=%s(%.2f, playing %s) jump=%s fall=%s", tostring(before.idle), tostring(before.walk),
                before.walk_speed or -1, tostring(before.walk_playing), tostring(before.jump), tostring(fall)))
        world:get_entity(named(world, "b"):id()):patch({ ["animation/action"] = { state = "jump", speed = 2 } })
        step("action")

    elseif phase == "action" then
        if clock < 0.3 then return end
        local p = named(world, "b"):get("animation/playing") or {}
        before.action = p.state .. "@" .. tostring(p.speed)
        world:get_entity(named(world, "b"):id()):patch({ ["animation/action"] = null })
        step("action_gone")

    elseif phase == "action_gone" then
        if clock < 0.3 then return end
        local b = named(world, "b")
        local p = b:get("animation/playing") or {}
        suite.assert_test("AN5_an_action_wins_while_it_is_there",
            before.action == "jump@2" and p.state == "idle", "action=" .. tostring(before.action) .. " after=" .. tostring(p.state))
        before.b_model = parts(world, b:id(), "animation/model")[1]:id()
        before.b_graph = b:get("animation/graph").handle
        -- A later change to `animation` (the server updating it) that names nothing new.
        world:get_entity(b:id()):patch({ animation = { walk_speed = 7 } })
        step("config_changed")

    elseif phase == "config_changed" then
        if clock < 0.5 then return end
        local b = named(world, "b")
        local models = parts(world, b:id(), "animation/model")
        local same_model = #models == 1 and models[1]:id() == before.b_model
        local same_graph = b:get("animation/graph").handle == before.b_graph
        suite.assert_test("AN10_a_change_naming_nothing_new_replaces_nothing", same_model and same_graph,
            string.format("models=%d same_model=%s same_graph=%s", #models, tostring(same_model), tostring(same_graph)))
        -- A new scene, and a new walk clip.
        world:get_entity(b:id()):patch({ animation = {
            scene = "-Walk.glb#Scene0",
            clips = { walk = "-Jump.glb#Animation0" },
        } })
        step("model_changed")

    elseif phase == "model_changed" then
        if clock < 1.0 then return end
        local b = named(world, "b")
        local models = parts(world, b:id(), "animation/model")
        local graph = b:get("animation/graph") or {}
        local clips = graph.clips or {}
        local player = parts(world, b:id(), "animation/player")[1]
        local linked = player and world:get_entity(player:id()):get("AnimationGraphHandle")
        local scene = models[1] and models[1]:get("animation/model").scene
        suite.assert_test("AN11_a_new_scene_replaces_the_model_and_a_new_clip_rebuilds_the_graph",
            #models == 1 and models[1]:id() ~= before.b_model and scene == "Placeholder-Character/Model-Walk.glb#Scene0"
                and graph.handle ~= before.b_graph and clips.walk == "Placeholder-Character/Model-Jump.glb#Animation0"
                and clips.idle == "Placeholder-Character/Model-Idle.glb#Animation0" and linked ~= nil,
            string.format("models=%d scene=%s walk=%s idle=%s linked=%s", #models, tostring(scene), tostring(clips.walk),
                tostring(clips.idle), tostring(linked ~= nil)))
        before.b_graph = graph.handle
        world:get_entity(b:id()):patch({ animation = { clips = { fall = null } } })
        step("clip_removed")

    elseif phase == "clip_removed" then
        if clock < 0.5 then return end
        local b = named(world, "b")
        local graph = b:get("animation/graph") or {}
        suite.assert_test("AN12_a_clip_taken_out_rebuilds_the_graph_without_it",
            graph.handle ~= before.b_graph and (graph.clips or {}).fall == nil and (graph.nodes or {}).fall == nil
                and (graph.clips or {}).idle ~= nil,
            string.format("new_graph=%s fall=%s node=%s", tostring(graph.handle ~= before.b_graph),
                tostring((graph.clips or {}).fall), tostring((graph.nodes or {}).fall)))
        before.models = {}
        for _, n in ipairs({ "a", "b" }) do
            local c = named(world, n)
            before.models[n] = parts(world, c:id(), "animation/model")[1]:id()
            before[n .. "_graph"] = c:get("animation/graph").handle
        end
        -- The walk clip's file is written again: Bevy reloads it in place.
        before.walk_key = key_of("Model-Walk.glb")
        if before.walk_key then
            write_file_bytes("assets/" .. before.walk_key, read_file_bytes("assets/" .. before.walk_key))
            watcher.process_changed_path(before.walk_key, world, asset_server)
        end
        step("refired")

    elseif phase == "refired" then
        if clock < 0.5 then return end
        local ok, detail = before.walk_key ~= nil, {}
        for _, n in ipairs({ "a", "b" }) do
            local c = named(world, n)
            local models = parts(world, c:id(), "animation/model")
            local same_model = #models == 1 and models[1]:id() == before.models[n]
            local same_graph = c:get("animation/graph").handle == before[n .. "_graph"]
            ok = ok and same_model and same_graph
            detail[#detail + 1] = string.format("%s: same_model=%s same_graph=%s", n, tostring(same_model), tostring(same_graph))
        end
        detail[#detail + 1] = "walk key=" .. tostring(before.walk_key)
        suite.assert_test("AN6_a_changed_clip_file_rebuilds_nothing", ok, table.concat(detail, "; "))
        -- The client half is edited (the same bytes written again): the watcher reloads it.
        local path = "assets/modules/animation/client/init.lua"
        write_file_bytes(path, read_file_bytes(path))
        step("reloaded")

    elseif phase == "reloaded" then
        if clock < 2.0 then return end
        local ok, detail = true, {}
        for _, n in ipairs({ "a", "b" }) do
            local c = named(world, n)
            local models = #parts(world, c:id(), "animation/model")
            local player = parts(world, c:id(), "animation/player")[1]
            local graph = c:get("animation/graph")
            local playing = c:get("animation/playing") or {}
            local on = false
            if player and graph and playing.state then
                local ok_p, r = pcall(function()
                    return world:get_entity(player:id()).AnimationPlayer:is_playing_animation(graph.nodes[playing.state])
                end)
                on = ok_p and r
            end
            ok = ok and models == 1 and on
            detail[#detail + 1] = string.format("%s: models=%d playing=%s", n, models, tostring(on))
        end
        suite.assert_test("AN9_editing_the_mod_keeps_every_character_drawn_and_playing", ok, table.concat(detail, "; "))
        world:get_entity(named(world, "a"):id()):patch({ animation = null })
        step("removed")

    elseif phase == "removed" then
        if clock < 0.5 then return end
        local a = named(world, "a")
        local full = a and world:get_entity(a:id())
        suite.assert_test("AN7_taken_off_its_model_and_parts_go",
            a ~= nil and #parts(world, a:id(), "animation/model") == 0
                and full:get("animation/graph") == nil and full:get("animation/playing") == nil,
            string.format("model=%d", #parts(world, a:id(), "animation/model")))
        suite.finish("ANIMATION_CLIENT")
        phase = "done"
    end
end):in_set("zz/animation_client_suite")
