-- The client half of a console: this client's copy of a door follows the server's record of its
-- re-point, and goes back to its authored value when the record goes. Each side spawns its own copy
-- of the scene, so the door's `Name` is what the record names. The console's screen is this
-- client's own: its node's mesh carries `ui/screen`, and the rows go under the screen's root. The
-- player points at it with `pointer`, and lists, picks or makes a branch. A repository the Hello Engine app
-- isn't installed on says so, with Install, through root's `vault/open_url`.
--
-- scope/portal/console/state = {
--     listed = <whether root has answered the branch list>,
--     branches = { <branch name>, ... },
--     error = <root's or the load's reason, shown on the screen>,
--     missing = { repo, install_url } <root's branch list said the Hello Engine app isn't installed
--         on the repository; install_url is root's, when it names one>,
--     typing = <the new branch's name while its field is open>,
-- }: on the console node, this client only
--
-- scope/portal/console/row = { target } | { new = true } | { install = <url> } | {}: a row that acts
-- when clicked: a branch, "New branch" (or "Create" while the field is open), "Install" (root's
-- install page, through `vault/open_url`), or "List branches"

local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local Scroll = require("bevy::picking::prelude::Scroll")
local KeyboardInput = require("bevy::input::keyboard::KeyboardInput")
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

-- This world's place in its repository, its own row's `scope_key` without the branch (the last
-- colon starts it): `scope_root` drops the subpath of a world in a folder of its repository
-- ("github:<owner>/<name>/Hello"). The repository's owner and name are `scope_root`'s.
local function repository(rows)
    local me = rows:iter()[1]
    local status = me and me:get("core/world/status")
    local key, root = status and status.scope_key, status and status.scope_root
    local here = type(key) == "string" and key:match("^(.+):[^:]+$") or nil
    local owner, name = nil, nil
    if type(root) == "string" then owner, name = root:match("^github:([^/]+)/(.+)$") end
    return here, owner, name
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

-- The screen: once the console's mesh has its `Aabb` (Bevy computes it after the mesh loads), a
-- `ui/screen` of its size.
app:add_systems(Update, {
    Query[{ with = { "scope/portal/console" } }],
    Query[{
        with = { "Mesh3d", "Aabb", "GlobalTransform" },
        optional = { "ui/screen" },
    }],
    Commands,
}, function(consoles, meshes, commands)
    for _, c in ipairs(consoles:iter()) do
        local mesh = meshes:iter_many({ c:id() })[1] or meshes:iter_many(meshes:iter_descendants(c:id()))[1]
        if mesh ~= nil and not mesh:has("ui/screen") then
            local w, h = screen_size(mesh)
            if w > 0 and h > 0 then
                commands:entity(mesh:id()):insert({ ["ui/screen"] = { width = w, height = h } })
            end
        end
    end
end):in_set("scope/portal/console/client"):run_if({
    Query[{ added = { "scope/portal/console" } }],
    Query[{ added = { "Aabb" } }],
}, function(consoles, bounds)
    return not (consoles:is_empty() and bounds:is_empty())
end)

-- A console taken off a node that stays: its mesh's screen goes.
app:add_systems(First, {
    Query[{ removed = { "scope/portal/console" } }],
    Query[{ with = { "ui/screen" } }],
    Commands,
}, function(removed, screens, commands)
    for _, c in ipairs(removed:iter()) do
        if commands:get_entity(c:id()) ~= nil then
            local mesh = screens:iter_many({ c:id() })[1] or screens:iter_many(screens:iter_descendants(c:id()))[1]
            if mesh ~= nil then commands:entity(mesh:id()):try_remove("ui/screen") end
        end
    end
end):in_set("scope/portal/console/client")

-- The screen's root, once `ui/screen` made it: the console's column on its background.
app:add_systems(Update, {
    Query[{ added = { "ui/screen/root" }, with = { "UiTargetCamera", Mut["Node"] } }],
    Query[{ with = { "ui/screen/camera" } }],
    Query[{ with = { "scope/portal/console" } }],
    Commands,
}, function(roots, cameras, consoles, commands)
    for _, r in ipairs(roots:iter_mut()) do
        local camera = r:get("UiTargetCamera")
        if cameras:contains(camera) and consoles:iter_many(consoles:iter_ancestors(camera))[1] ~= nil then
            local node = r:get_mut("Node")
            node.flex_direction = "Column"
            node.row_gap = { Px = 8 }
            -- Every UI in the world shares one pixel space for the pointer, so the rows keep clear of
            -- the HUD's left bar.
            node.padding = { left = { Px = 64 }, right = { Px = 16 }, top = { Px = 16 }, bottom = { Px = 16 } }
            commands:entity(r:id()):insert({ ["ui/style"] = { background = "bg" } })
        end
    end
end):in_set("scope/portal/console/root"):before("scope/portal/console/client")

-- The rows, rebuilt whole from the console's state and its door when either changes. A rebuild takes
-- the buttons the pointer may be on, which a click does not mind.
app:add_systems(Update, {
    Query[{
        with = { "ui/screen/root", "UiTargetCamera" },
        optional = { "Children" },
    }],
    Query[{ with = { "ui/screen/camera" } }],
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
            local function row(text, data, parent)
                local r = commands:spawn({
                    ["scope/portal/console/row"] = data,
                    Button = {},
                    Node = { padding = { left = { Px = 12 }, right = { Px = 12 }, top = { Px = 6 }, bottom = { Px = 6 } } },
                    ["ui/style"] = { background = "row_bg", hover = "row_hover", text = "text" },
                    Text = { text = text },
                    TextFont = { font_size = 28 },
                    ChildOf = parent or v:id(),
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
                        if what.install ~= nil then
                            -- Root's install page, through root's dialog, which shows the address
                            -- first; root's answer closes the ask.
                            click_commands:spawn({
                                ["vault/open_url"] = { url = what.install },
                                Request = {},
                                ["core/script/owner"] = false,
                                ChildOf = c:id(),
                            })
                        elseif what.target ~= nil and player ~= nil then
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
                            s.error, s.missing = nil, nil
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
            if state.missing ~= nil then
                line("⚠ the Hello Engine app isn't installed on " .. tostring(state.missing.repo), "text_bad")
                if state.missing.install_url ~= nil then row("Install", { install = state.missing.install_url }) end
            end
            if not state.listed then
                row("List branches", {})
            else
                -- The branches in a column of their own, which the wheel scrolls when they do not fit, as
                -- the sidebar's lists do; what follows them stays in view below.
                local list = commands:spawn({
                    Node = {
                        flex_direction = "Column",
                        row_gap = { Px = 8 },
                        flex_grow = 1,
                        flex_shrink = 1,
                        min_height = { Px = 0 },
                        overflow = { x = "Visible", y = "Scroll" },
                    },
                    ScrollPosition = { x = 0, y = 0 },
                    ChildOf = v:id(),
                })
                -- `ScrollPosition` is written whole: a field set on its working copy is dropped.
                list:observe(On[Pointer[Scroll]], {
                    Query[{ with = { Mut["ScrollPosition"] }, optional = { "ComputedNode" } }],
                }, function(event, lists)
                    event:propagate(false)
                    for _, l in ipairs(lists:iter_many_mut({ event.entity })) do
                        local node = l:get("ComputedNode")
                        local room = node and math.max(0, node.content_size.y - node.size.y) or 0
                        local at = l:get("ScrollPosition").y
                        l:get_mut("ScrollPosition"):set_if_neq({ x = 0, y = math.max(0, math.min(room, at - event.event.y * 40)) })
                    end
                end)
                for _, b in ipairs(state.branches or {}) do
                    row((b == branch and "● " or "") .. tostring(b), { target = root .. ":" .. tostring(b) }, list:id())
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
    Query[{ added = { "ui/screen/root" } }],
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
            local wish = r:get("vault/github/branches")
            local s = c:get_mut("scope/portal/console/state")
            s.listed = said.error == nil
            s.branches = said.branches or {}
            s.error, s.missing = said.error, nil
            -- The Hello Engine app isn't on this repository: the screen says so, with Install when
            -- root names the app's install page, in place of root's error.
            if said.reason == "not-installed" then
                s.error = nil
                s.missing = {
                    repo = tostring(wish.owner) .. "/" .. tostring(wish.name),
                    install_url = type(said.install_url) == "string" and said.install_url or nil,
                }
            end
            commands:entity(r:id()):despawn()
        end
    end
end):in_set("scope/portal/console/client")

-- An install ask under a console answered, opened or refused: root's dialog has gone, and the ask
-- closes.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            added = { "vault/open_url/reply" },
            changed = { "vault/open_url/reply" },
        },
        with = { "vault/open_url", "Request", "ChildOf" },
    }],
    Query[{ with = { "scope/portal/console" } }],
    Commands,
}, function(answered, consoles, commands)
    for _, ask in ipairs(answered:iter()) do
        if consoles:contains(ask:get("ChildOf")) then
            commands:entity(ask:id()):despawn()
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
