-- --host
-- A portal's label on a client: the world it leads to and how many players are in it, over the
-- portal, facing this client's eye. This VM plays a client world (never root), so the sessions
-- reply and root's observe answer are the suite's, written as root's arrive. The screen's colours
-- need a theme and a window, so only its text is checked.
--
--   L1  a placed portal to another world gets one label, its child, kept over it by
--       `transform/follow`, with a screen and its own sessions ask
--   L2  a portal to this world's own scope, and one being placed, get none
--   L3  before root answers, the label names the repository and the branch
--   L4  root's sessions list gives the count, matched in canonical form; a world it names no session
--       for has no one in it
--   L5  the label stands over a 3d portal, and turns about Y to face the eye; the eye moved, it turns
--   L6  a door's label stands over its mesh children, and the door's stencils never land on it
--   L7  the portal's target changed, its label names the new one
--   L8  the target taken away, the label and its ask go
--   L9  the label is one line, "<name>  |  <branch>  |  <count>", over eight dark copies set off
--       around it (its outline), on a transparent screen with no background; a changed line gets a
--       fresh image
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local Cuboid = require("bevy::math::primitives::Cuboid")
local Quat = require("bevy::math::Quat")

local suite = helpers.create_suite("ScopePortalViewLabelSuite")
local T = suite.assert_test

world_id = 7

local HERE = "github:zzlabel/here:main"
local OTHER = "github:ZzLabel/Other-World:dev"
local DOOR = "github:zzlabel/door/Hello:main"
local LATER = "github:zzlabel/later:main"

local eye
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net"] = { mode = "client", name = "zzlabel" },
        ["core/net/sync"] = false })
    commands:spawn({
        ["core/world/status"] = { scope_key = HERE, mode = "client", status = "ready", observer = false },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    eye = commands:spawn({ ["camera/3d/eye"] = {}, Transform = { translation = { x = 5, y = 1.6, z = 0 } },
        ["core/net/sync"] = false }):id()
end)

local function portal(world, name)
    for _, e in ipairs(world:query({ with = { "zz/label/p" }, optional = { "Children" } })) do
        if e:get("zz/label/p").name == name then return e end
    end
end

local function labels_of(world, p)
    local out = {}
    for _, child in ipairs(p and p:get("Children") or {}) do
        local e = world:get_entity(child)
        if e ~= nil and e:has("scope/portal/view/label") then out[#out + 1] = e end
    end
    return out
end

local function sessions_ask(world, label)
    for _, child in ipairs(label and label:get("Children") or {}) do
        local e = world:get_entity(child)
        if e ~= nil and e:has("core/registry/sessions") then return e end
    end
end

-- The label's line and its outline, read from under its screen's root: `text`, the line's text;
-- `outlines`, how many outline copies say the same; `copies`, how many there are; `root`, the root.
local function lines_of(world, label)
    local camera
    for _, child in ipairs(label and label:get("Children") or {}) do
        local e = world:get_entity(child)
        if e ~= nil and e:has("ui/screen/camera") then camera = e:id() end
    end
    local said = { outlines = 0, copies = 0 }
    for _, r in ipairs(world:query({ with = { "ui/screen/root", "UiTargetCamera" }, optional = { "Children" } })) do
        if camera ~= nil and r:get("UiTargetCamera") == camera then
            said.root = r
            local copies = {}
            for _, id in ipairs(world:descendants(r:id())) do
                local line = world:get_entity(id)
                if line ~= nil and line:has("scope/portal/view/line") then
                    if line:get("scope/portal/view/line").part == "text" then
                        said.text = line:get("Text")
                    else
                        copies[#copies + 1] = line:get("Text")
                    end
                end
            end
            said.copies = #copies
            for _, t in ipairs(copies) do
                if t == said.text then said.outlines = said.outlines + 1 end
            end
        end
    end
    return said
end

local function yaw_of(follow)
    return follow and follow.rotation and Quat.to_euler(follow.rotation, "YXZ")[1]
end

local function near(a, b, e) return type(a) == "number" and math.abs(a - b) < (e or 1e-3) end

local phase, clock = "spawn", 0
local door_kid, old_label, old_ask

app:add_systems(Update, { World, Commands, ResMut[Assets[Mesh]] }, function(world, commands, meshes)
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end

    if phase == "spawn" then
        commands:spawn({ ["scope/portal"] = { target = OTHER }, ["scope/portal/view"] = { mode = "3d" },
            Transform = {}, ["core/net/sync"] = false, ["zz/label/p"] = { name = "a" } })
        commands:spawn({ ["scope/portal"] = { target = HERE }, ["scope/portal/view"] = { mode = "3d" },
            Transform = { translation = { x = -5, y = 0, z = 0 } }, ["core/net/sync"] = false, ["zz/label/p"] = { name = "self" } })
        commands:spawn({ ["scope/portal"] = { target = LATER }, ["scope/portal/view"] = { mode = "3d" }, placement = {},
            Transform = { translation = { x = 0, y = 0, z = -5 } }, ["core/net/sync"] = false, ["zz/label/p"] = { name = "placing" } })
        local door = commands:spawn({ ["scope/portal"] = { target = DOOR }, ["scope/portal/view"] = { mode = "none" },
            Transform = { translation = { x = 0, y = 0, z = 10 } }, ["core/net/sync"] = false, ["zz/label/p"] = { name = "door" } }):id()
        door_kid = commands:spawn({ Mesh3d = meshes:add(Cuboid.new(1, 2, 0.2)),
            Aabb = { center = { x = 0, y = 1, z = 0 }, half_extents = { x = 0.5, y = 1, z = 0.1 } },
            Transform = { translation = { x = 0, y = 0.5, z = 0 } }, ["core/net/sync"] = false, ChildOf = door }):id()
        step("labelled")

    elseif phase == "labelled" and #labels_of(world, portal(world, "a")) == 1 and lines_of(world, labels_of(world, portal(world, "a"))[1]).text ~= nil
        and clock > 0.3 then
        local label = labels_of(world, portal(world, "a"))[1]
        local follow = label:get("transform/follow")
        T("L1_a_placed_portal_to_another_world_gets_one_label", label:get("scope/portal/view/label").target == OTHER
            and label:has("ui/screen") and follow ~= nil, tostring(label:get("scope/portal/view/label").target))
        T("L1_with_its_own_sessions_ask", sessions_ask(world, label) ~= nil)
        T("L2_a_portal_to_this_world_gets_none", #labels_of(world, portal(world, "self")) == 0)
        T("L2_nor_one_being_placed", #labels_of(world, portal(world, "placing")) == 0)
        local said = lines_of(world, label)
        T("L3_before_root_answers_the_repository_and_the_branch", said.text == "Other-World  |  dev", tostring(said.text))
        T("L9_one_line_over_its_outline_saying_the_same", said.copies == 8 and said.outlines == 8,
            said.copies .. " " .. said.outlines)
        T("L9_on_a_transparent_screen_with_no_background", label:get("ui/screen").transparent == true
            and not said.root:has("ui/style") and not said.root:has("BackgroundColor"))
        T("L5_it_stands_over_a_3d_portal", near(follow.offset.y, 1.7) and near(follow.offset.x, 0),
            tostring(follow.offset.y))
        T("L5_and_faces_the_eye", near(yaw_of(follow), math.pi / 2), tostring(yaw_of(follow)))
        local door_label = labels_of(world, portal(world, "door"))[1]
        local door_follow = door_label and door_label:get("transform/follow")
        T("L6_a_door_s_label_stands_over_its_mesh_children", door_follow ~= nil and near(door_follow.offset.y, 3.0),
            tostring(door_follow and door_follow.offset.y))
        commands:entity(sessions_ask(world, label):id()):insert({ ["core/registry/sessions/reply"] = { sessions = {
            { scope = "github:zzlabel/other-world:dev", scope_root = "github:zzlabel/other-world", active = 2, background = 1 },
            { scope = "github:zzlabel/other-world:main", scope_root = "github:zzlabel/other-world", active = 5, background = 0 },
        } } })
        commands:entity(sessions_ask(world, door_label):id()):insert({ ["core/registry/sessions/reply"] = { sessions = {} } })
        commands:spawn({ ["core/world/observe/answer"] = { ref = DOOR, state = "allowed" },
            WorldMirror = { world_id = 0 }, ["core/net/sync"] = false })
        commands:entity(eye):insert({ Transform = { translation = { x = 0, y = 1.6, z = 5 } } })
        step("counted")

    elseif phase == "counted" and clock > 0.5 then
        local label = labels_of(world, portal(world, "a"))[1]
        local said = lines_of(world, label)
        T("L4_root_s_list_gives_the_count", said.text == "Other-World  |  dev  |  2 players" and said.outlines == 8,
            tostring(said.text) .. " " .. said.outlines)
        T("L9_a_changed_line_gets_a_fresh_empty_image", label:get("ui/screen").fresh == 1
            and label:has("pointer/target") and label:get("pointer/target").fresh == 1, tostring(label:get("ui/screen").fresh))
        local door_label = labels_of(world, portal(world, "door"))[1]
        local door_said = lines_of(world, door_label)
        T("L4_a_world_with_no_session_has_no_one_in_it", door_said.text == "door/Hello  |  main  |  no one here",
            tostring(door_said.text))
        T("L5_the_eye_moved_the_label_turns", near(yaw_of(label:get("transform/follow")), 0),
            tostring(yaw_of(label:get("transform/follow"))))
        local kid = world:get_entity(door_kid)
        T("L6_the_door_s_stencil_lands_on_its_surface", kid ~= nil and kid:has("core/compositor/stencil"))
        T("L6_and_never_on_its_label", not door_label:has("core/compositor/stencil"))
        old_label = label:id()
        commands:entity(portal(world, "a"):id()):insert({ ["scope/portal"] = { target = LATER } })
        step("retargeted")

    elseif phase == "retargeted" and #labels_of(world, portal(world, "a")) == 1
        and labels_of(world, portal(world, "a"))[1]:get("scope/portal/view/label").target == LATER
        and lines_of(world, labels_of(world, portal(world, "a"))[1]).text ~= nil and clock > 0.3 then
        local label = labels_of(world, portal(world, "a"))[1]
        T("L7_a_changed_target_s_label_names_the_new_one", tostring(lines_of(world, label).text):match("^later  |  ") ~= nil
            and world:get_entity(old_label) == nil, tostring(lines_of(world, label).text))
        old_label = label:id()
        old_ask = sessions_ask(world, label):id()
        commands:entity(portal(world, "a"):id()):insert({ ["scope/portal"] = {} })
        step("untargeted")

    elseif phase == "untargeted" and clock > 0.5 then
        T("L8_the_target_taken_away_the_label_goes", #labels_of(world, portal(world, "a")) == 0
            and world:get_entity(old_label) == nil)
        T("L8_and_its_ask", world:get_entity(old_ask) == nil)
        phase = "done"
        suite.finish("ScopePortalViewLabelSuite")
    end

    if phase ~= "done" and clock > 10 then
        T("L0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 10 s")
        phase = "done"
        suite.finish("ScopePortalViewLabelSuite")
    end
end):in_set("zz/label_suite")
