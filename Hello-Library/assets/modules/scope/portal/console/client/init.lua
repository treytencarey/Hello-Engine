-- The client half of a console: this client's copy of a door follows the server's record of its
-- re-point, and goes back to its authored value when the record goes. Each side spawns its own copy
-- of the scene, so the door's `Name` is what the record names. The console's screen is this
-- client's own, drawn as the VR panels are: its node's mesh shows an image a camera of the console
-- draws its UI into. The player points at it with the mouse, and lists, picks or makes a branch.
--
-- scope/portal/console/state = {
--     listed = <whether root has answered the branch list>,
--     branches = { <branch name>, ... },
--     error = <root's or the load's reason, shown on the screen>,
--     typing = <the new branch's name while its field is open>,
-- }: on the console node, this client only
--
-- scope/portal/console/camera = { image }: the camera drawing the screen, a child of the screen's mesh;
-- the image it draws into, kept here as a handle read back from the material does not build a
-- `PointerInput`
-- scope/portal/console/view = {}: the screen's UI root, drawn by that camera
-- scope/portal/console/row = { target } | { new = true } | {}: a row that acts when clicked: a
-- branch, "New branch" (or "Create" while the field is open), or "List branches"

local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local Assets = require("bevy::asset::Assets")
local AssetServer = require("bevy::asset::AssetServer")
local AnimationClip = require("bevy::animation::AnimationClip")
local Image = require("bevy::image::Image")
local StandardMaterial = require("bevy::pbr::StandardMaterial")
local MeshRayCast = require("bevy::picking::prelude::MeshRayCast")
local PointerInput = require("bevy::picking::pointer::PointerInput")
local KeyboardInput = require("bevy::input::keyboard::KeyboardInput")
local Quat = require("bevy::math::Quat")
local bevy = require("bevy::prelude")
local Door = require("modules/scope/portal/console/shared/door.lua")

-- The screen's pixels: its mesh's size at its world scale, 0.0008 m a pixel, as a VR panel's. Its
-- width is along the mesh's own X, its height the larger of its Y and Z.
local function screen_size(mesh)
    local half = mesh:get("Aabb").half_extents
    local scale = mesh.GlobalTransform:compute_transform().scale
    local width = 2 * math.abs(half.x * scale.x)
    local height = 2 * math.max(math.abs(half.y * scale.y), math.abs(half.z * scale.z))
    return math.floor(width / 0.0008), math.floor(height / 0.0008)
end

-- This world's repository, from its own row's `scope_root` ("github:<owner>/<name>").
local function repository(rows)
    local me = rows:iter()[1]
    local root = me and me:get("core/world/status").scope_root
    local owner, name = nil, nil
    if type(root) == "string" then owner, name = root:match("^github:([^/]+)/(.+)$") end
    return root, owner, name
end

-- The one place a console asks the server to re-point its door, on this client's own player.
local function repoint(commands, player, door, target)
    commands:entity(player:id()):insert({ ["scope/portal/console/request"] = { door = door, target = target } })
end

-- Typing gives the player the cursor and UI input, as the sidebar does; closing the field gives game
-- input back. Only an `input/mode` still there is written.
local function input_mode(commands, player, typing)
    commands:entity(player:id()):entry("input/mode"):and_modify(function(mode)
        mode.mode = typing and "input/ui" or "input/game"
        mode.show_cursor = typing
    end)
end

-- A new branch's name: what a branch name may hold, and no more than 100 characters of it.
local function valid_name(name)
    return type(name) == "string" and #name > 0 and #name <= 100 and name:match("^[%w%-%._/]+$") ~= nil
end

-- On a record's arrival or change, and on a door arriving (a late scene, one written again), the
-- door takes the record's target and `at`. Written only when it differs: the view asks again on
-- every change.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            added = { "scope/portal/console/target" },
            changed = { "scope/portal/console/target" },
        },
    }],
    Query[{
        added = { "scope/portal" },
        with = { "Name" },
        without = { "placement" },
    }],
    Query[{
        with = { Mut["scope/portal"], "Name" },
        without = { "placement" },
    }],
    Query[{ with = { "scope/portal/console/target" } }],
}, function(changed, arrived, doors, records)
    local wanted = {}
    for _, r in ipairs(records:iter()) do
        local record = r:get("scope/portal/console/target")
        wanted[record.door] = record
    end
    local touched = {}
    for _, r in ipairs(changed:iter()) do
        local record = r:get("scope/portal/console/target")
        touched[record.door] = true
    end
    for _, d in ipairs(doors:iter_mut()) do
        local name = d:get("Name").name
        local record = wanted[name]
        if record ~= nil and (touched[name] or arrived:contains(d:id())) then
            local portal = d:get("scope/portal")
            if portal.target ~= record.target or portal.at ~= record.at then
                local p = d:get_mut("scope/portal")
                p.target, p.at = record.target, record.at
            end
        end
    end
end):in_set("scope/portal/console/client"):run_if({
    Query[{
        ["or"] = {
            added = { "scope/portal/console/target" },
            changed = { "scope/portal/console/target" },
        },
    }],
    Query[{
        added = { "scope/portal" },
        with = { "Name" },
        without = { "placement" },
    }],
}, function(changed, arrived)
    return not (changed:is_empty() and arrived:is_empty())
end)

-- A record gone (the door pointed back, or the server stopping): the door named in its last value
-- takes its authored value again, unless another record names it now.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            removed = { "scope/portal/console/target" },
        },
        optional = { "scope/portal/console/target" },
    }],
    Query[{
        with = { Mut["scope/portal"], "Name" },
        without = { "placement" },
        optional = { "GltfExtras" },
    }],
    Query[{ with = { "scope/portal/console/target" } }],
}, function(gone, doors, records)
    local named = {}
    for _, r in ipairs(gone:iter()) do
        local was = r:get("scope/portal/console/target")
        if was ~= nil then named[was.door] = true end
    end
    for _, r in ipairs(records:iter()) do
        named[r:get("scope/portal/console/target").door] = nil
    end
    for _, d in ipairs(doors:iter_mut()) do
        if named[d:get("Name").name] then
            local authored = Door.authored(d)
            local portal = d:get("scope/portal")
            if authored ~= nil and (portal.target ~= authored.target or portal.at ~= authored.at) then
                local p = d:get_mut("scope/portal")
                p.target, p.at = authored.target, authored.at
            end
        end
    end
end):in_set("scope/portal/console/client")

-- A console arriving gets its state; one it already holds (a reload) stays.
app:add_systems(First, {
    Query[{
        added = { "scope/portal/console" },
        optional = { "scope/portal/console/state" },
    }],
    Commands,
}, function(consoles, commands)
    for _, c in ipairs(consoles:iter()) do
        if not c:has("scope/portal/console/state") then
            commands:entity(c:id()):insert({ ["scope/portal/console/state"] = { listed = false, branches = {} } })
        end
    end
end):in_set("scope/portal/console/client")

-- The click is bound on this client's own player in both modes: game input while the player walks,
-- UI input while the name field is open.
app:add_systems(First, {
    Query[{ with = { "core/net", "core/net/owns" } }],
    Query[{ with = { "player", "input" } }],
    Commands,
}, function(own, players, commands)
    for _, n in ipairs(own:iter()) do
        for _, p in ipairs(players:iter_many(n:get("core/net/owns"))) do
            for _, mode in ipairs({ "input/game", "input/ui" }) do
                commands:entity(p:id()):entry(mode):or_default():and_modify(function(bindings)
                    bindings.portal_console = { press = { button = "Left" } }
                end)
            end
        end
    end
end):in_set("scope/portal/console/client"):run_if({
    Query[{ added = { "scope/portal/console" } }],
    Query[{
        ["or"] = {
            added = { "input", "core/net/owns" },
            changed = { "core/net/owns" },
        },
    }],
}, function(consoles, owners)
    return not (consoles:is_empty() and owners:is_empty())
end)

-- The last console gone: the click is unbound, from an `input` still there.
app:add_systems(First, {
    Query[{ removed = { "scope/portal/console" } }],
    Query[{ with = { "scope/portal/console" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Query[{ with = { "player", "input" } }],
    Commands,
}, function(removed, consoles, own, players, commands)
    for _, _ in ipairs(removed:iter()) do
        if consoles:is_empty() then
            for _, n in ipairs(own:iter()) do
                for _, p in ipairs(players:iter_many(n:get("core/net/owns"))) do
                    for _, mode in ipairs({ "input/game", "input/ui" }) do
                        commands:entity(p:id()):entry(mode):and_modify(function(bindings)
                            bindings.portal_console = nil
                        end)
                    end
                end
            end
        end
        break
    end
end):in_set("scope/portal/console/client")

-- The screen: once the console's mesh has its `Aabb` (Bevy computes it after the mesh loads), an
-- image of its size, a camera drawing into it, the UI root on that camera, and the image unlit on
-- the mesh. The UI root is a root of its own: a UI node under the scene would not be laid out.
app:add_systems(Update, {
    Query[{ with = { "scope/portal/console" } }],
    Query[{
        with = { "Mesh3d", "Aabb", "GlobalTransform" },
        optional = { "Children" },
    }],
    Query[{ with = { "scope/portal/console/camera" } }],
    ResMut[Assets[Image]],
    ResMut[Assets[StandardMaterial]],
    Commands,
}, function(consoles, meshes, cameras, images, materials, commands)
    for _, c in ipairs(consoles:iter()) do
        local mesh = meshes:iter_many({ c:id() })[1] or meshes:iter_many(meshes:iter_descendants(c:id()))[1]
        if mesh ~= nil and cameras:iter_many(mesh:get("Children") or {})[1] == nil then
            local w, h = screen_size(mesh)
            if w > 0 and h > 0 then
                local image = images:add(Image.new_target_texture(w, h, "bgra8unorm-srgb"))
                local camera = commands:spawn({
                    ["scope/portal/console/camera"] = { image = image },
                    Camera2d = {},
                    Camera = { order = -210, target = { Image = image } },
                    ChildOf = mesh:id(),
                }):id()
                commands:spawn({
                    ["scope/portal/console/view"] = {},
                    Node = {
                        width = { Px = w },
                        height = { Px = h },
                        flex_direction = "Column",
                        row_gap = { Px = 8 },
                        -- Every UI in the world shares one pixel space for the pointer, so the
                        -- rows keep clear of the HUD's left bar.
                        padding = { left = { Px = 64 }, right = { Px = 16 }, top = { Px = 16 }, bottom = { Px = 16 } },
                    },
                    ["ui/style"] = { background = "bg" },
                    UiTargetCamera = { entity = camera },
                })
                commands:entity(mesh:id()):insert({
                    ["MeshMaterial3d<StandardMaterial>"] = materials:add({ base_color_texture = image, unlit = true }),
                })
            end
        end
    end
end):in_set("scope/portal/console/client"):run_if({
    Query[{ added = { "scope/portal/console" } }],
    Query[{ added = { "Aabb" } }],
}, function(consoles, bounds)
    return not (consoles:is_empty() and bounds:is_empty())
end)

-- A screen's camera gone (its scene written again, or the console taken off): its UI root goes too.
app:add_systems(Update, {
    Query[{ removed = { "scope/portal/console/camera" } }],
    Query[{ with = { "scope/portal/console/view", "UiTargetCamera" } }],
    Query[{ with = { "scope/portal/console/camera" } }],
    Commands,
}, function(removed, views, cameras, commands)
    for _, _ in ipairs(removed:iter()) do
        for _, v in ipairs(views:iter()) do
            if not cameras:contains(v:get("UiTargetCamera")) then
                commands:entity(v:id()):try_despawn()
            end
        end
        break
    end
end):in_set("scope/portal/console/client")

-- The rows, rebuilt whole from the console's state and its door when either changes. A rebuild takes
-- the buttons the pointer may be on, which a click does not mind.
app:add_systems(Update, {
    Query[{
        with = { "scope/portal/console/view", "UiTargetCamera" },
        optional = { "Children" },
    }],
    Query[{ with = { "scope/portal/console/camera" } }],
    Query[{ with = { "scope/portal/console", "scope/portal/console/state" } }],
    Query[{ with = { "scope/portal", "Name" }, without = { "placement" } }],
    Query[{ with = { "core/world/load", "WorldShared" }, without = { "WorldMirror" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(views, cameras, consoles, doors, loads, rows, commands)
    local root = repository(rows)
    local loading = {}
    for _, l in ipairs(loads:iter()) do
        local ask = l:get("core/world/load")
        if ask.status ~= "failed" then loading[ask.scope] = true end
    end
    for _, v in ipairs(views:iter()) do
        local camera = v:get("UiTargetCamera")
        local console = cameras:contains(camera) and consoles:iter_many(consoles:iter_ancestors(camera))[1] or nil
        if console ~= nil then
            local cfg = console:get("scope/portal/console")
            local state = console:get("scope/portal/console/state")
            local target = nil
            for _, d in ipairs(doors:iter()) do
                if d:get("Name").name == cfg.door then target = d:get("scope/portal").target end
            end
            local branch = target
            if root ~= nil and type(target) == "string" and target:sub(1, #root + 1) == root .. ":" then
                branch = target:sub(#root + 2)
            end
            for _, child in ipairs(v:get("Children") or {}) do
                commands:entity(child):despawn()
            end
            local id = console:id()
            local function line(text, role)
                commands:spawn({
                    Text = { text = text },
                    TextFont = { font_size = 28 },
                    ["ui/style"] = { text = role },
                    ChildOf = v:id(),
                })
            end
            local function row(text, data)
                local r = commands:spawn({
                    ["scope/portal/console/row"] = data,
                    Button = {},
                    Node = { padding = { left = { Px = 12 }, right = { Px = 12 }, top = { Px = 6 }, bottom = { Px = 6 } } },
                    ["ui/style"] = { background = "row_bg", hover = "row_hover", text = "text" },
                    Text = { text = text },
                    TextFont = { font_size = 28 },
                    ChildOf = v:id(),
                })
                r:observe(On[Pointer[Click]], {
                    Query[{ with = { "scope/portal/console/row" } }],
                    Query[{ with = { "scope/portal/console", Mut["scope/portal/console/state"] } }],
                    Query[{ with = { "core/net", "core/net/owns" } }],
                    Query[{ with = { "player" }, optional = { "input/mode" } }],
                    Query[{
                        with = { "core/world/status", "WorldShared" },
                        without = { "WorldMirror" },
                    }],
                    Commands,
                }, function(event, clicked, owners, own, players, world_rows, click_commands)
                    local pressed = clicked:get(event.entity)
                    local c = owners:iter_many_mut({ id })[1]
                    if pressed ~= nil and c ~= nil then
                        local what = pressed:get("scope/portal/console/row")
                        local s = c:get_mut("scope/portal/console/state")
                        local repo_root, owner, name = repository(world_rows)
                        local player = nil
                        for _, n in ipairs(own:iter()) do
                            player = player or players:iter_many(n:get("core/net/owns"))[1]
                        end
                        if what.target ~= nil and player ~= nil then
                            repoint(click_commands, player, c:get("scope/portal/console").door, what.target)
                        elseif what.new and s.typing == nil and player ~= nil then
                            s.typing, s.error = "", nil
                            input_mode(click_commands, player, true)
                        elseif what.new and valid_name(s.typing) and repo_root ~= nil then
                            click_commands:spawn({
                                ["core/world/load"] = { scope = repo_root .. ":" .. s.typing },
                                WorldShared = {},
                                ["core/net/sync"] = false,
                            })
                        elseif not what.new and what.target == nil and owner ~= nil then
                            s.error = nil
                            click_commands:spawn({
                                ["vault/github/branches"] = { owner = owner, name = name },
                                Request = {},
                                ["core/script/owner"] = false,
                                ChildOf = c:id(),
                            })
                        end
                    end
                end)
            end
            line("Points to " .. tostring(branch or "nothing"), "text")
            if state.error ~= nil then line("⚠ " .. tostring(state.error), "text_bad") end
            if not state.listed then
                row("List branches", {})
            else
                for _, b in ipairs(state.branches or {}) do
                    row((b == branch and "● " or "") .. tostring(b), { target = root .. ":" .. tostring(b) })
                end
                if state.typing == nil then
                    row("New branch", { new = true })
                else
                    line("Name: " .. state.typing .. "_", "accent")
                    local busy = root ~= nil and loading[root .. ":" .. state.typing]
                    row(busy and "..." or "Create", { new = true })
                end
            end
        end
    end
end):in_set("scope/portal/console/client"):run_if({
    Query[{ added = { "scope/portal/console/view" } }],
    Query[{ changed = { "scope/portal/console/state" } }],
    Query[{ changed = { "scope/portal" }, with = { "Name" } }],
    Query[{
        ["or"] = {
            changed = { "core/world/load" },
            removed = { "core/world/load" },
        },
    }],
}, function(views, states, doors, loads)
    return not (views:is_empty() and states:is_empty() and doors:is_empty() and loads:is_empty())
end)

-- Root's branch list, on the console's own ask: the screen shows it, or why not, and the ask goes.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            added = { "vault/github/branches/reply" },
            changed = { "vault/github/branches/reply" },
        },
        with = { "vault/github/branches", "Request", "ChildOf" },
    }],
    Query[{ with = { "scope/portal/console", Mut["scope/portal/console/state"] } }],
    Commands,
}, function(replies, consoles, commands)
    for _, r in ipairs(replies:iter()) do
        local c = consoles:iter_many_mut({ r:get("ChildOf") })[1]
        if c ~= nil then
            local said = r:get("vault/github/branches/reply")
            local s = c:get_mut("scope/portal/console/state")
            s.listed = said.error == nil
            s.branches = said.branches or {}
            s.error = said.error
            commands:entity(r:id()):despawn()
        end
    end
end):in_set("scope/portal/console/client")

-- The name field: what the player types while it is open. Enter makes the branch, as Create does;
-- Escape closes the field. Runs only while a field is open.
app:add_systems(Update, {
    bevy.MessageReader[KeyboardInput],
    Query[{ with = { "scope/portal/console", Mut["scope/portal/console/state"] } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Query[{ with = { "player" }, optional = { "input/mode" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(keys, consoles, own, players, rows, commands)
    local root = repository(rows)
    local player = nil
    for _, n in ipairs(own:iter()) do
        player = player or players:iter_many(n:get("core/net/owns"))[1]
    end
    local events = keys:read()
    for _, c in ipairs(consoles:iter_mut()) do
        local s = c:get_mut("scope/portal/console/state")
        for _, ev in ipairs(events) do
            if s.typing ~= nil and ev.state == "Pressed" then
                local key = ev.logical_key
                -- A character key reads back as a one-item list (measured), its `SmolStr` inside.
                local typed = type(key) == "table" and key.Character ~= nil and (key.Character[1] or key.Character) or nil
                if type(typed) == "string" then
                    if #s.typing < 100 and typed:match("^[%w%-%._/]$") then
                        s.typing = s.typing .. typed
                    end
                elseif key == "Backspace" then
                    s.typing = s.typing:sub(1, -2)
                elseif key == "Escape" then
                    s.typing = nil
                    if player ~= nil then input_mode(commands, player, false) end
                elseif key == "Enter" and valid_name(s.typing) and root ~= nil then
                    commands:spawn({
                        ["core/world/load"] = { scope = root .. ":" .. s.typing },
                        WorldShared = {},
                        ["core/net/sync"] = false,
                    })
                end
            end
        end
    end
end):in_set("scope/portal/console/client"):run_if({
    Query[{ with = { "scope/portal/console/state" } }],
}, function(states)
    for _, row in ipairs(states:iter()) do
        if row:get("scope/portal/console/state").typing ~= nil then return true end
    end
    return false
end)

-- A new branch's load: once root says its world is up, the door is re-pointed at it and the load
-- goes; a failure says why on the screen and the field stays open. Root's resolve makes the branch
-- (behind its own dialog), as for any load a world asks.
app:add_systems(Update, {
    Query[{
        changed = { "core/world/load" },
        with = { "WorldShared" },
        without = { "WorldMirror" },
    }],
    Query[{ with = { "scope/portal/console", Mut["scope/portal/console/state"] } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Query[{ with = { "player" }, optional = { "input/mode" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(loads, consoles, own, players, rows, commands)
    local root = repository(rows)
    local player = nil
    for _, n in ipairs(own:iter()) do
        player = player or players:iter_many(n:get("core/net/owns"))[1]
    end
    for _, l in ipairs(loads:iter()) do
        local ask = l:get("core/world/load")
        for _, c in ipairs(consoles:iter_mut()) do
            local s = c:get("scope/portal/console/state")
            if root ~= nil and s.typing ~= nil and ask.scope == root .. ":" .. s.typing then
                if ask.status == "ready" and player ~= nil then
                    repoint(commands, player, c:get("scope/portal/console").door, ask.scope)
                    commands:entity(l:id()):despawn()
                    c:get_mut("scope/portal/console/state").typing = nil
                    input_mode(commands, player, false)
                elseif ask.status == "failed" then
                    commands:entity(l:id()):despawn()
                    c:get_mut("scope/portal/console/state").error = tostring(ask.reason or "failed")
                end
            end
        end
    end
end):in_set("scope/portal/console/client")

-- Pointing: a click casts a ray from this player's eye through the cursor (the eye's forward while
-- the cursor is held), and if the first thing within 3 m is a console's screen, Bevy's picking hears
-- the mouse at that pixel of its image. A world VM's camera draws into an image the size of the
-- window's physical pixels, so the cursor is read in those. The player and what hangs under it
-- never stand in the way. The mouse pointer is reused: a pointer of its own would be
-- `PointerId::Custom`, which Lua cannot build.
local function aimed(ray_cast, p, own, eyes, windows, screens, cameras)
    local mine = false
    for _, n in ipairs(own:iter()) do
        for _, e in ipairs(n:get("core/net/owns")) do
            mine = mine or e == p:id()
        end
    end
    local eye = mine and eyes:iter_many(p:get("Children") or {})[1] or nil
    if eye == nil then return nil end
    local ray
    local window = windows:iter()[1]
    local cursor = window and window.Window:physical_cursor_position() or nil
    -- It fails while the camera has no target size yet.
    local ok, seen = pcall(function() return cursor ~= nil and eye.Camera:viewport_to_world(cursor) or nil end)
    if ok and seen then
        -- A `Dir3` may read back as its one field.
        ray = { origin = seen.origin, direction = seen.direction[1] or seen.direction }
    else
        local t = eye.GlobalTransform:compute_transform()
        ray = { origin = t.translation, direction = Quat.mul_vec3(t.rotation, { x = 0, y = 0, z = -1 }) }
    end
    local me = p:id()
    local hit = ray_cast:cast_ray(ray, {
        visibility = "Visible",
        filter = function(entity)
            return screens:root_ancestor(entity) ~= me
        end,
    })[1]
    local screen = hit and screens:get(hit.entity) or nil
    local uv = hit and hit.ray_mesh_hit.uv or nil
    local camera = screen and cameras:iter_many(screen:get("Children") or {})[1] or nil
    local image = camera and camera:get("scope/portal/console/camera").image
    if image == nil or uv == nil or hit.ray_mesh_hit.distance > 3 then return nil end
    local w, h = screen_size(screen)
    return { target = { Image = image }, position = { x = uv.x * w, y = uv.y * h } }
end

-- The button down moves the mouse there and presses; up releases. Bevy clicks on a release only
-- what the pointer hovered the frame before, so the three in one frame would click nothing.
app:add_systems(Update, {
    MeshRayCast,
    Query[{
        ["or"] = {
            added = { "input/game/portal_console/press", "input/ui/portal_console/press" },
        },
        with = { "player" },
        optional = { "Children" },
    }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Query[{ with = { "camera/3d/eye", "Camera", "GlobalTransform" } }],
    Query[{ with = { "Window" } }],
    Query[{
        with = { "Mesh3d", "Aabb", "GlobalTransform", "MeshMaterial3d<StandardMaterial>" },
        optional = { "Children" },
    }],
    Query[{ with = { "scope/portal/console/camera" } }],
    bevy.MessageWriter[PointerInput],
}, function(ray_cast, pressed, own, eyes, windows, screens, cameras, pointer)
    for _, p in ipairs(pressed:iter()) do
        local location = aimed(ray_cast, p, own, eyes, windows, screens, cameras)
        if location ~= nil then
            pointer:write({ pointer_id = "Mouse", location = location, action = { Move = { delta = { x = 0.001, y = 0.001 } } } })
            pointer:write({ pointer_id = "Mouse", location = location, action = { Press = "Primary" } })
        end
    end
end):in_set("scope/portal/console/client")

app:add_systems(Update, {
    MeshRayCast,
    Query[{
        ["or"] = {
            removed = { "input/game/portal_console/press", "input/ui/portal_console/press" },
        },
    }],
    Query[{ with = { "player" }, optional = { "Children" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Query[{ with = { "camera/3d/eye", "Camera", "GlobalTransform" } }],
    Query[{ with = { "Window" } }],
    Query[{
        with = { "Mesh3d", "Aabb", "GlobalTransform", "MeshMaterial3d<StandardMaterial>" },
        optional = { "Children" },
    }],
    Query[{ with = { "scope/portal/console/camera" } }],
    bevy.MessageWriter[PointerInput],
}, function(ray_cast, released, players, own, eyes, windows, screens, cameras, pointer)
    for _, r in ipairs(released:iter()) do
        local p = players:iter_many({ r:id() })[1]
        local location = p and aimed(ray_cast, p, own, eyes, windows, screens, cameras)
        if location ~= nil then
            pointer:write({ pointer_id = "Mouse", location = location, action = { Release = "Primary" } })
        end
    end
end):in_set("scope/portal/console/client")

-- The door's own animation, on the nearest node at or above the door carrying `animation/clip` (a
-- map's rig around its door), played on each client from the record. A pick closes the door if it
-- stands open at all, then opens it; a door with no record stays shut. A client that joins where a
-- record already stands sees the door open: its clip is set at its end, not played.

--- The node carrying the door's clip: the door's own, or its nearest ancestor's. Its query's
--- `animation/clip` column is `Mut`.
local function rig_of(rigs, door)
    return rigs:iter_many_mut({ door })[1] or rigs:iter_many_mut(rigs:iter_ancestors(door))[1]
end

--- The rig's AnimationPlayer once it has its graph, and how far along its clips stand (the
--- furthest of them). Its query names `AnimationPlayer` (`Mut` to seek).
local function opened(players, rig)
    local player = players:iter_many({ rig:id() })[1] or players:iter_many(players:iter_descendants(rig:id()))[1]
    local graph = rig:get("animation/clip/graph")
    if player == nil or graph == nil then return nil, nil end
    local at = 0
    for _, index in pairs(graph.nodes) do
        local active = player.AnimationPlayer:animation(index)
        if active then at = math.max(at, active.seek_time) end
    end
    return player, at
end

-- A pick, live: the record arriving, changing or going while the door's clip already plays here.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            added = { "scope/portal/console/target" },
            changed = { "scope/portal/console/target" },
            removed = { "scope/portal/console/target" },
        },
        optional = { "scope/portal/console/target" },
    }],
    Query[{ with = { "scope/portal", "Name" }, without = { "placement" } }],
    Query[{ with = { Mut["animation/clip"] }, optional = { "animation/clip/graph" } }],
    Query[{ with = { "AnimationPlayer", "AnimationGraphHandle" } }],
}, function(picked, doors, rigs, players)
    local named = {}
    for _, r in ipairs(picked:iter()) do
        local record = r:get("scope/portal/console/target")
        if record ~= nil then named[record.door] = true end
    end
    if next(named) == nil then return end
    for _, d in ipairs(doors:iter()) do
        if named[d:get("Name").name] then
            local rig = rig_of(rigs, d:id())
            local player, at = nil, nil
            if rig then player, at = opened(players, rig) end
            if player ~= nil then
                local clip = rig:get_mut("animation/clip")
                clip.speed = at > 0 and -1 or 1
                clip["repeat"] = false
            end
        end
    end
end):in_set("scope/portal/console/client")

-- Closing for a pick: once shut, it opens. Moving, so it polls the doors' rigs while one closes.
app:add_systems(Update, {
    Query[{ with = { "scope/portal", "Name" }, without = { "placement" } }],
    Query[{ with = { "scope/portal/console" } }],
    Query[{ with = { Mut["animation/clip"] }, optional = { "animation/clip/graph" } }],
    Query[{ with = { "AnimationPlayer", "AnimationGraphHandle" } }],
}, function(doors, consoles, rigs, players)
    local named = {}
    for _, c in ipairs(consoles:iter()) do named[c:get("scope/portal/console").door] = true end
    for _, d in ipairs(doors:iter()) do
        if named[d:get("Name").name] then
            local rig = rig_of(rigs, d:id())
            if rig and rig:get("animation/clip").speed < 0 then
                local player, at = opened(players, rig)
                if player ~= nil and at <= 0 then rig:get_mut("animation/clip").speed = 1 end
            end
        end
    end
end):in_set("scope/portal/console/client"):run_if({
    Query[{ with = { "scope/portal/console" } }],
}, function(consoles)
    return not consoles:is_empty()
end)

-- Joining where a record stands: when the door's clip first has its player, the door is open, at
-- the end of its clip.
app:add_systems(Update, {
    Query[{ added = { "AnimationGraphHandle" }, with = { "AnimationPlayer" } }],
    Query[{ with = { "scope/portal/console/target" } }],
    Query[{ with = { "scope/portal", "Name" }, without = { "placement" } }],
    Query[{ with = { Mut["animation/clip"], "animation/clip/graph" } }],
    Query[{ with = { Mut["AnimationPlayer"], "AnimationGraphHandle" } }],
    Res[Assets[AnimationClip]],
    Res[AssetServer],
}, function(linked, records, doors, rigs, players, clips, asset_server)
    local named = {}
    for _, r in ipairs(records:iter()) do named[r:get("scope/portal/console/target").door] = true end
    local fresh = {}
    for _, p in ipairs(linked:iter()) do fresh[p:id()] = true end
    for _, d in ipairs(doors:iter()) do
        if named[d:get("Name").name] then
            local rig = rig_of(rigs, d:id())
            local player = rig and (players:iter_many_mut({ rig:id() })[1]
                or players:iter_many_mut(players:iter_descendants(rig:id()))[1])
            if player ~= nil and fresh[player:id()] then
                for clip, index in pairs(rig:get("animation/clip/graph").nodes) do
                    local asset = clips:get(asset_server:load(clip))
                    player.AnimationPlayer:play(index, { seek_to = asset and asset.duration or 0 })
                end
                local c = rig:get_mut("animation/clip")
                c.speed = 1
                c["repeat"] = false
            end
        end
    end
end):in_set("scope/portal/console/client"):run_if({
    Query[{ added = { "AnimationGraphHandle" }, with = { "AnimationPlayer" } }],
}, function(linked)
    return not linked:is_empty()
end)
