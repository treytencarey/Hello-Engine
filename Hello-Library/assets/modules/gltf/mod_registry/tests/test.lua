-- Blender custom properties become components, by change detection.
--
-- Fixture: tests/fixtures/markers.glb, a Blender export with Include: Custom
-- Properties. fx_box `collider/bb`, fx_floor `collider/mesh`, fx_start `player/spawner/point`,
-- fx_view `fx/view = { order = 1, fov }`, fx_json `fx/json` as a JSON string, fx_light
-- `fx/light`, and the scene's own `fx/look`. The suite loads a copy of it, so it can
-- re-export the copy. Server side.
--
-- G1 every key lands on its node as a component with its config, the scene's on the scene's node
-- G2 a JSON-object string is decoded
-- G3 Name reads back as written, with no quotes to strip
-- G4 extras changed in place: a new key lands; scalar values never become components
-- G5 a re-export respawns the nodes and applies them again; a key renamed in the file leaves the
--    old name on no node
-- G6 added to a scene that already loaded, it applies that scene
-- G7 taken off a carrier that stays: the nodes stay, and their extras' components go
-- G8 the mod's file is edited (hot reload): the main scene's nodes keep their components, and
--    fx_box still has one box
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local AssetServer = require("bevy::asset::AssetServer")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("GltfModRegistrySuite")
local T = suite.assert_test

local SOURCE = read_file_bytes("assets/modules/gltf/mod_registry/tests/fixtures/markers.glb")
local COPY = "modules/gltf/mod_registry/tests/fixtures/zz_markers_copy.glb"
write_file_bytes("assets/" .. COPY, SOURCE)

app:add_systems(Startup, { Commands, Res[AssetServer] }, function(commands, asset_server)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        ["zz/root"] = { name = "late" },
        SceneRoot = asset_server:load("modules/gltf/mod_registry/tests/fixtures/markers.glb#Scene0"),
        Transform = { translation = { x = 50, y = 0, z = 0 } },
    })
end)

local function root(world, name)
    for _, e in ipairs(world:query({ with = { "zz/root" } })) do
        if e:get("zz/root").name == name then
            return e
        end
    end
end

-- The node, not its mesh primitive, which can share its Name: the node has the extras.
local function node(world, root_name, name)
    local r = root(world, root_name)
    if r == nil then
        return nil
    end
    for _, e in ipairs(world:query({
        iter_many = world:descendants(r:id()),
        with = { "Name" },
        any_of = { "GltfExtras", "GltfSceneExtras" },
        optional = { "player/spawner/point", "fx/view", "collider/bb", "collider/mesh", "fx/look",
            "fx/json", "fx/nosj", "fx/other", "fx/scalar", "fx/text" },
    })) do
        if e:get("Name").name == name then
            return e
        end
    end
end

local function scene_node(world, root_name)
    local r = root(world, root_name)
    return r and world:query({
        iter_many = world:descendants(r:id()),
        with = { "GltfSceneExtras" },
        optional = { "fx/look" },
    })[1]
end

local function quoted_names(world)
    local n = 0
    for _, e in ipairs(world:query({ with = { "Name", "GltfExtras" } })) do
        if e:get("Name").name:sub(1, 1) == '"' then
            n = n + 1
        end
    end
    return n
end

local reloaded = {}

app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        reloaded[#reloaded + 1] = tostring(event.path)
    end
end):in_set("zz/gltf_suite_reloads")

local function was_reloaded(file)
    for _, path in ipairs(reloaded) do
        if path:find(file, 1, true) then
            return true
        end
    end
    return false
end

local function touch(file)
    local path = "assets/" .. file
    write_file_bytes(path, read_file_bytes(path))
end

local phase, clock, frames = "wait", 0, 0
local first_start

app:add_systems(Update, { World, Commands, Res[AssetServer] }, function(world, commands, asset_server)
    clock = clock + (world:delta_time() or 0)
    frames = frames + 1
    local function step(next_phase) phase, clock, frames = next_phase, 0, 0 end

    -- Bevy's watcher reports the copy's creation a moment later, and a scene loaded by then
    -- would respawn once.
    if phase == "wait" and clock > 1.5 then
        commands:spawn({
            ["zz/root"] = { name = "main" },
            SceneRoot = asset_server:load(COPY .. "#Scene0"),
            Transform = {},
            ["gltf/mod_registry"] = {},
        })
        step("applied")

    elseif phase == "applied" then
        local start = node(world, "main", "fx_start")
        local json = node(world, "main", "fx_json")
        -- Bevy's scene spawner ignores a change in the frames just after a scene's spawn.
        if start and start:has("player/spawner/point") and json and json:has("fx/json") and frames > 10 then
            T("G1_fx_start_has_player_spawner_point", true, "")
            local view = node(world, "main", "fx_view")
            local vp = view and view:get("fx/view")
            T("G1_fx_view_keeps_its_config", vp ~= nil and vp.order == 1
                and type(vp.fov) == "number" and vp.fov > 0.3 and vp.fov < 0.5,
                "viewpoint " .. tostring(vp and vp.order) .. " " .. tostring(vp and vp.fov))
            local box = node(world, "main", "fx_box")
            T("G1_fx_box_has_collider_bb", box ~= nil and box:has("collider/bb"), "missing")
            local floor = node(world, "main", "fx_floor")
            T("G1_fx_floor_has_collider_mesh", floor ~= nil and floor:has("collider/mesh"), "missing")
            local scene = scene_node(world, "main")
            local look = scene and scene:get("fx/look")
            T("G1_the_scene_extras_land_on_the_scene_node", look ~= nil and look.tonemapping == "AgX",
                "fx/look " .. tostring(look and look.tonemapping))
            local fj = json:get("fx/json")
            T("G2_a_json_string_is_decoded", fj.a == 1 and fj.b == "two",
                "a=" .. tostring(fj.a) .. " b=" .. tostring(fj.b))
            T("G3_names_read_as_written", quoted_names(world) == 0, quoted_names(world) .. " quoted")
            first_start = start:id()
            commands:entity(json:id()):insert({
                GltfExtras = { value = '{"fx/other": {"k": 2}, "fx/scalar": 1, "fx/text": "x"}' },
            })
            step("changed")
        end

    elseif phase == "changed" then
        local json = node(world, "main", "fx_json")
        local other = json and json:get("fx/other")
        if other ~= nil then
            T("G4_a_new_key_lands", other.k == 2, "k=" .. tostring(other.k))
            T("G4_scalars_are_not_components", not json:has("fx/scalar") and not json:has("fx/text"),
                "a scalar became a component")
            -- Same length, so the binary chunk's offsets stay right.
            write_file_bytes("assets/" .. COPY, (SOURCE:gsub("fx/json", "fx/nosj")))
            step("reexported")
        end

    elseif phase == "reexported" then
        local start = node(world, "main", "fx_start")
        local json = node(world, "main", "fx_json")
        if start and start:id() ~= first_start and start:has("player/spawner/point") and json and json:has("fx/nosj") then
            T("G5_a_reexport_applies_the_new_nodes", true, "")
            T("G5_a_renamed_key_leaves_the_old_name_on_no_node",
                #world:query({ with = { "fx/json" } }) == 0 and not json:has("fx/other"),
                "fx/json on " .. #world:query({ with = { "fx/json" } }))
            local late = node(world, "late", "fx_start")
            T("G6_setup_nothing_without_the_component", late ~= nil and not late:has("player/spawner/point"),
                "applied too early")
            commands:entity(root(world, "late"):id()):insert({ ["gltf/mod_registry"] = {} })
            step("late")
        end

    elseif phase == "late" then
        local late = node(world, "late", "fx_start")
        if late and late:has("player/spawner/point") then
            T("G6_added_to_a_loaded_scene_it_applies_it", true, "")
            commands:entity(root(world, "late"):id()):remove("gltf/mod_registry")
            step("removed")
        end

    elseif phase == "removed" then
        local start = node(world, "late", "fx_start")
        local box = node(world, "late", "fx_box")
        if start and not start:has("player/spawner/point") and box and not box:has("collider/bb") then
            T("G7_taken_off_its_nodes_lose_their_components", true, "")
            T("G7_the_main_scene_keeps_its_own", node(world, "main", "fx_start"):has("player/spawner/point"), "lost")
            touch("modules/gltf/mod_registry/init.lua")
            step("reload")
        end

    elseif phase == "reload" and was_reloaded("gltf/mod_registry/init.lua") then
        step("reloaded")

    elseif phase == "reloaded" and clock > 1.5 then
        local start, box, floor = node(world, "main", "fx_start"), node(world, "main", "fx_box"), node(world, "main", "fx_floor")
        local scene = scene_node(world, "main")
        local boxes = box and #world:query({ iter_many = world:descendants(box:id()), with = { "collider/bb/shape" } }) or 0
        T("G8_after_a_reload_the_nodes_keep_their_components_and_one_box",
            start:has("player/spawner/point") and box:has("collider/bb") and floor:has("collider/mesh")
                and scene:has("fx/look") and boxes == 1,
            "boxes=" .. boxes)
        os.remove("assets/" .. COPY)
        phase = "done"
        suite.finish("GltfModRegistrySuite")
    end

    if phase ~= "done" and clock > 15 then
        T("G0_reached_" .. phase, false, "stuck for 15 s")
        os.remove("assets/" .. COPY)
        phase = "done"
        suite.finish("GltfModRegistrySuite")
    end
end):in_set("zz/gltf_suite")
