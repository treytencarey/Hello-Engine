-- How a portal looks on a client, and the world it shows. A placed portal asks root to observe its
-- target, and root's answer decides: allowed, the target's picture shows through the portal's
-- mesh (`core/compositor/stencil`); refused, the portal is locked and says why. With `"3d"` the
-- view brings its own sphere; with `"none"` the carrier brings its mesh (a glTF door's surface).
-- None of it runs in a world that is itself only being observed; once promoted, it catches up.
--
-- Over each portal that shows another world stands its label: the world's name, its branch and
-- how many players are in it, by root's sessions list, turned to face this client's eye.
--
-- scope/portal/view = {
--     mode = <"3d" | "none">,
-- }
--
-- scope/portal/view/label = { target }: the label, a child of the portal: a plane carrying
-- `ui/screen`, kept over the portal by `transform/follow`, with its own sessions ask as its child
--
-- scope/portal/view/line = { part = <"text" | "outline"> }: the label's one line of text on its
-- screen, `"text"`; each `"outline"` is a dark copy of it, set off a few pixels, under it

local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local StandardMaterial = require("bevy::pbr::StandardMaterial")
local Sphere = require("bevy::math::primitives::Sphere")
local Plane3d = require("bevy::math::primitives::Plane3d")
local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")

--- The doors this client's own players came out of, by `Name`, and the worlds they came from
--- (`scope/portal/from`). `players` names `scope/portal/from` and `core/net/owner`; `own` is this
--- client's nets, with `core/net/owns`.
local function ways_back(players, own)
    local back = {}
    for _, n in ipairs(own:iter()) do
        for _, pl in ipairs(players:iter_many(n:get("core/net/owns"))) do
            local from = pl:get("scope/portal/from")
            if from.target ~= nil and from.door ~= nil then back[from.door] = from.target end
        end
    end
    return back
end

--- The world a portal shows: its target, or, for a door without one, the world this client's
--- player came from through it, as the crossing would take the player.
local function shown_target(p, portal, back)
    if portal.target ~= nil then return portal.target end
    if portal.at ~= nil and p:has("Name") then return back[p:get("Name").name] end
end

-- A way back arriving, changing or going.
local WAYS = Query[{ ["or"] = { added = { "scope/portal/from" }, changed = { "scope/portal/from" }, removed = { "scope/portal/from" } } }]

-- One ask per placed portal, its child: it goes with the portal, and root loads each target once
-- however many ask. `hosted` makes root ask once more after a `not-running` refusal. Every ask is
-- `join_only = false`: root starts the target if nobody runs it and this player may (the
-- Gateway's start gate), and otherwise looks in join-only, so a portal standing when a
-- collaborator arrives brings its world up as one being placed does. The ask is not this file's
-- to reap: a reload that took it would make root drop the observed world and load it again.
app:add_systems(Update, {
    Query[{
        with = { "scope/portal", "scope/portal/view" },
        without = { "placement" },
        optional = { "scope/portal/hosted", "Children", "Name" },
    }],
    Query[{
        with = { "core/world/observe" },
        without = { "WorldMirror" },
    }],
    Query[{
        with = { "core/world/library" },
        without = { "WorldMirror" },
        optional = { "core/world/library/cache", "core/world/library/order" },
    }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Query[{ with = { "player", "scope/portal/from", "core/net/owner" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(portals, asks, records, rows, players, own, commands)
    local back = ways_back(players, own)
    local me = rows:iter()[1]
    local scope = me and me:get("core/world/status").scope_key
    local libraries = {}
    for _, r in ipairs(records:iter()) do
        libraries[#libraries + 1] = {
            library = r:get("core/world/library"),
            cache = r:get("core/world/library/cache"),
            order = r:get("core/world/library/order"),
        }
    end
    for _, p in ipairs(portals:iter()) do
        local target = shown_target(p, p:get("scope/portal"), back)
        local hosted = p:has("scope/portal/hosted") or nil
        local kept
        for _, ask in ipairs(asks:iter_many(p:get("Children") or {})) do
            if kept == nil and target ~= nil and target ~= scope and ask:get("core/world/observe").ref == target then
                kept = ask
            else
                commands:entity(ask:id()):despawn()
            end
        end
        if kept ~= nil then
            local was = kept:get("core/world/observe")
            if was.hosted ~= hosted or was.join_only ~= false then
                commands:entity(kept:id()):entry("core/world/observe"):and_modify(function(ask)
                    ask.hosted = hosted
                    ask.join_only = false
                end)
            end
        elseif target ~= nil and target ~= scope then
            commands:spawn({
                ["core/world/observe"] = { ref = target, libraries = libraries, hosted = hosted, join_only = false },
                WorldShared = {},
                ["core/net/sync"] = false,
                ["core/script/owner"] = false,
                ChildOf = p:id(),
            })
            print(string.format("[SCOPE/PORTAL/VIEW] asking root to look into %s, starting it if nobody runs it", target))
        end
    end
end):in_set("scope/portal/view/client")
    :run_if({
        Query[{
            ["or"] = {
                added = { "scope/portal", "scope/portal/view", "scope/portal/hosted" },
                changed = { "scope/portal" },
                removed = { "placement", "scope/portal/hosted" },
            },
        }],
        Query[{
            changed = { "core/world/status" },
            with = { "WorldShared" },
            without = { "WorldMirror" },
        }],
        Query[{
            with = { "core/world/status", "WorldShared" },
            without = { "WorldMirror" },
        }],
        WAYS,
    }, function(touched, moved, rows, ways)
        local me = rows:iter()[1]
        local watching = me ~= nil and me:get("core/world/status").observer == true
        return not watching and not (touched:is_empty() and moved:is_empty() and ways:is_empty())
    end)

-- Only root's answer counts, a mirror from VM 0: this world's own entities, or another world's
-- mirror, could say anything. An answer about this world itself (another world's portal looking
-- here) shows nothing through a portal to it.
-- A `"none"` carrier without a mesh of its own shows the world on its children's: a glTF node's
-- primitives are its children.
-- A door (`at`, on a named node) shows the target from its place there: its stencils name the
-- place, the door's world transform and its view. The insert replaces the stencil whole, which
-- drops the `ref` and `vm` core wrote, so it is written only when one of these differs. A
-- transform read before the door's first propagation is the identity, so the frame follows the
-- door's `GlobalTransform` changes.
app:add_systems(Update, {
    Query[{
        with = { "scope/portal", "scope/portal/view" },
        without = { "placement" },
        optional = { "core/compositor/stencil", "scope/portal/locked", "Mesh3d", "Children", "Name", "GlobalTransform" },
    }],
    Query[{ with = { "core/world/observe/answer", "WorldMirror" } }],
    -- A door's surfaces are its mesh children; its label is a mesh child too, and shows no world.
    Query[{
        with = { "Mesh3d" },
        without = { "scope/portal/view/label" },
        optional = { "core/compositor/stencil" },
    }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Query[{ with = { "player", "scope/portal/from", "core/net/owner" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(portals, answers, meshes, rows, players, own, commands)
    local back = ways_back(players, own)
    local said = {}
    for _, a in ipairs(answers:iter()) do
        if a:get("WorldMirror").world_id == 0 then
            local answer = a:get("core/world/observe/answer")
            said[answer.ref] = answer
        end
    end
    local me = rows:iter()[1]
    local scope = me and me:get("core/world/status").scope_key
    for _, p in ipairs(portals:iter()) do
        local portal = p:get("scope/portal")
        local target = shown_target(p, portal, back)
        local answer = target ~= nil and target ~= scope and said[target] or nil
        local surfaces = { p }
        if p:get("scope/portal/view").mode == "none" and not p:has("Mesh3d") then
            surfaces = meshes:iter_many(p:get("Children") or {})
        end
        local shown = { world = target }
        if portal.at ~= nil and p:has("Name") and p:has("GlobalTransform") then
            local t = p.GlobalTransform:compute_transform()
            shown.at = portal.at
            shown.view = p:get("Name").name
            shown.frame = {
                translation = { x = t.translation.x, y = t.translation.y, z = t.translation.z },
                rotation = { x = t.rotation.x, y = t.rotation.y, z = t.rotation.z, w = t.rotation.w },
                scale = { x = t.scale.x, y = t.scale.y, z = t.scale.z },
            }
        end
        if target == nil then
            -- A door leading nowhere, for this client, shows nothing, and is not locked.
            for _, s in ipairs(surfaces) do
                if s:has("core/compositor/stencil") then
                    commands:entity(s:id()):remove("core/compositor/stencil")
                end
            end
            if p:has("scope/portal/locked") then
                commands:entity(p:id()):remove("scope/portal/locked")
            end
        elseif answer ~= nil and answer.state == "allowed" then
            for _, s in ipairs(surfaces) do
                local stencil = s:get("core/compositor/stencil")
                local frame = stencil and stencil.frame
                local framed = frame == shown.frame or (frame ~= nil and shown.frame ~= nil
                    and Vec3.abs_diff_eq(frame.translation, shown.frame.translation, 1e-4)
                    and Quat.abs_diff_eq(frame.rotation, shown.frame.rotation, 1e-4)
                    and Vec3.abs_diff_eq(frame.scale, shown.frame.scale, 1e-4))
                if not (stencil and stencil.world == target and stencil.at == shown.at and stencil.view == shown.view
                        and framed) then
                    commands:entity(s:id()):insert({ ["core/compositor/stencil"] = shown })
                end
            end
            if p:has("scope/portal/locked") then
                commands:entity(p:id()):remove("scope/portal/locked")
            end
        elseif answer ~= nil and answer.state == "refused" then
            for _, s in ipairs(surfaces) do
                if s:has("core/compositor/stencil") then
                    commands:entity(s:id()):remove("core/compositor/stencil")
                end
            end
            local reason = answer.reason or "refused"
            local locked = p:get("scope/portal/locked")
            if not (locked and locked.reason == reason) then
                commands:entity(p:id()):insert({ ["scope/portal/locked"] = { reason = reason } })
                print(string.format("[SCOPE/PORTAL/VIEW] portal to %s is locked: %s", target, reason))
            end
        end
    end
end):in_set("scope/portal/view/client")
    :run_if({
        Query[{
            ["or"] = {
                added = { "core/world/observe/answer", "scope/portal/view", "Mesh3d" },
                changed = { "core/world/observe/answer" },
                removed = { "placement" },
            },
        }],
        Query[{
            changed = { "core/world/status" },
            with = { "WorldShared" },
            without = { "WorldMirror" },
        }],
        Query[{
            with = { "core/world/status", "WorldShared" },
            without = { "WorldMirror" },
        }],
        Query[{
            ["or"] = { changed = { "scope/portal", "GlobalTransform" } },
            with = { "scope/portal", "scope/portal/view" },
            without = { "placement" },
        }],
        WAYS,
    }, function(touched, moved, rows, doors, ways)
        local me = rows:iter()[1]
        local watching = me ~= nil and me:get("core/world/status").observer == true
        return not watching and not (touched:is_empty() and moved:is_empty() and doors:is_empty() and ways:is_empty())
    end)

-- The `"3d"` look, in PostUpdate so it sees this frame's lock: red and glowing while being placed,
-- dim while locked, plain while waiting. Once the stencil is on, the stencil owns the material. A
-- portal to this world itself shows nothing (a portal's return end, standing where the portal does).
app:add_systems(PostUpdate, {
    Query[{
        ["or"] = {
            added = { "scope/portal/view", "scope/portal/locked" },
            changed = { "scope/portal/locked" },
            removed = { "placement", "scope/portal/locked" },
        },
        with = { "scope/portal", "scope/portal/view" },
        optional = { "placement", "scope/portal/locked", "Mesh3d", "core/compositor/stencil" },
    }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    ResMut[Assets[Mesh]],
    ResMut[Assets[StandardMaterial]],
    Commands,
}, function(portals, rows, meshes, materials, commands)
    local me = rows:iter()[1]
    local scope = me and me:get("core/world/status").scope_key
    for _, e in ipairs(portals:iter()) do
        local target = e:get("scope/portal").target
        if e:get("scope/portal/view").mode == "3d" and target ~= nil and target ~= scope then
            local entity = commands:entity(e:id())
            if not e:has("Mesh3d") then
                entity:insert({ Mesh3d = meshes:add(Sphere.new(1.2)) })
            end
            if e:has("placement") then
                entity:insert({
                    ["MeshMaterial3d<StandardMaterial>"] = materials:add({
                        base_color = { Srgba = { red = 1.0, green = 0.3, blue = 0.1, alpha = 1 } },
                        emissive = { red = 2.0, green = 0.5, blue = 0.1, alpha = 1 },
                    }),
                })
            elseif e:has("scope/portal/locked") then
                entity:insert({
                    ["MeshMaterial3d<StandardMaterial>"] = materials:add({
                        base_color = { Srgba = { red = 0.15, green = 0.15, blue = 0.18, alpha = 1 } },
                    }),
                })
            elseif not e:has("core/compositor/stencil") then
                entity:insert({ ["MeshMaterial3d<StandardMaterial>"] = materials:add({}) })
            end
        end
    end
end):in_set("scope/portal/view/client")
    :run_if({
        Query[{
            with = { "core/world/status", "WorldShared" },
            without = { "WorldMirror" },
        }],
    }, function(rows)
        local me = rows:iter()[1]
        return me == nil or me:get("core/world/status").observer ~= true
    end)

-- `scope/portal/view` was taken off an entity that stays: what it put there goes, and so does
-- the portal's ask. The old value says whether the mesh was the view's own.
app:add_systems(Update, {
    Query[{
        ["or"] = { removed = { "scope/portal/view" } },
        optional = { "scope/portal/view", "Children" },
    }],
    Query[{ with = { "core/world/observe" } }],
    Query[{ with = { "Mesh3d", "core/compositor/stencil" } }],
    Commands,
}, function(removed, asks, shown, commands)
    for _, e in ipairs(removed:iter()) do
        local old = e:get("scope/portal/view")
        local entity = commands:get_entity(e:id())
        if entity ~= nil then
            entity:try_remove("core/compositor/stencil", "scope/portal/locked")
            if old ~= nil and old.mode == "3d" then
                entity:try_remove("Mesh3d", "MeshMaterial3d<StandardMaterial>")
            end
            for _, s in ipairs(shown:iter_many(e:get("Children") or {})) do
                commands:entity(s:id()):try_remove("core/compositor/stencil")
            end
            for _, ask in ipairs(asks:iter_many(e:get("Children") or {})) do
                commands:entity(ask:id()):despawn()
            end
        end
    end
end):in_set("scope/portal/view/client")

-- The label's text: the target's repository name (and its folder) on the first line; its branch and
-- how many players are in it on the second, by root's sessions list. A world the list names no
-- session for has no one in it; until root answers, or while root says it can't list, the second
-- line is the branch alone. A scope not in the canonical form is shown as it is.
local function canonical(key)
    local path, branch = tostring(key):match("^github:([^:]+):(.+)$")
    if path == nil then return tostring(key) end
    local owner, name, folder = path:match("^([^/]+)/([^/]+)/?(.*)$")
    if owner == nil then return tostring(key) end
    return "github:" .. owner:lower() .. "/" .. name:lower() .. (folder ~= "" and ("/" .. folder) or "") .. ":" .. branch
end

local function label_text(target, said)
    local path, branch = tostring(target):match("^github:([^:]+):(.+)$")
    local title = path and (path:match("^[^/]+/(.+)$") or path) or tostring(target)
    if said == nil or said.sessions == nil or said.error ~= nil then
        return branch and (title .. "  ·  " .. branch) or title
    end
    local active = 0
    for _, s in ipairs(said.sessions) do
        if canonical(s.scope) == canonical(target) then active = tonumber(s.active) or 0 end
    end
    local count = active == 0 and "no one here" or (active == 1 and "1 player" or (active .. " players"))
    return title .. "  ·  " .. (branch and (branch .. "  ·  " .. count) or count)
end

-- The outline: dark copies of the line, each set off this many pixels, drawn under it.
local OUTLINE = { { -2, -2 }, { 0, -2 }, { 2, -2 }, { -2, 0 }, { 2, 0 }, { -2, 2 }, { 0, 2 }, { 2, 2 } }
local OUTLINE_COLOR = { r = 0, g = 0, b = 0, a = 0.85 }
-- One line: a long one runs past the screen's edges rather than onto a second line.
local NO_WRAP = { linebreak = "NoWrap", justify = "Center" }

-- One label per portal that shows another world, its child: a plane facing its +Z, with a
-- transparent screen 1440 x 60 pixels, 4.8 x 0.2 m, wide enough for a long line, which never
-- wraps. A label naming another target (the portal's changed) or a second one goes. Each label asks root for the sessions list itself: root keeps one list however many
-- ask, and the ask goes with its label.
app:add_systems(Update, {
    Query[{
        with = { "scope/portal", "scope/portal/view" },
        without = { "placement" },
        optional = { "Children", "Name" },
    }],
    Query[{ with = { "scope/portal/view/label" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Query[{ with = { "player", "scope/portal/from", "core/net/owner" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    ResMut[Assets[Mesh]],
    Commands,
}, function(portals, labels, rows, players, own, meshes, commands)
    local back = ways_back(players, own)
    local me = rows:iter()[1]
    local scope = me and me:get("core/world/status").scope_key
    for _, p in ipairs(portals:iter()) do
        local target = shown_target(p, p:get("scope/portal"), back)
        local kept
        for _, l in ipairs(labels:iter_many(p:get("Children") or {})) do
            if kept == nil and target ~= nil and target ~= scope and l:get("scope/portal/view/label").target == target then
                kept = l
            else
                commands:entity(l:id()):despawn()
            end
        end
        if kept == nil and target ~= nil and target ~= scope then
            local label = commands:spawn({
                ["scope/portal/view/label"] = { target = target },
                Mesh3d = meshes:add(Plane3d.new({ x = 0, y = 0, z = 1 }, { x = 2.4, y = 0.1 })),
                ["ui/screen"] = { width = 1440, height = 60, transparent = true },
                Transform = {},
                ["transform/follow"] = { rotation = { x = 0, y = 0, z = 0, w = 1 }, offset = { x = 0, y = 1.7, z = 0 } },
                Visibility = "Visible",
                ["core/net/sync"] = false,
                ChildOf = p:id(),
            }):id()
            commands:spawn({ ["core/registry/sessions"] = {}, Request = {}, ChildOf = label })
        end
    end
end):in_set("scope/portal/view/label")
    :run_if({
        Query[{
            ["or"] = {
                added = { "scope/portal", "scope/portal/view" },
                changed = { "scope/portal" },
                removed = { "placement" },
            },
        }],
        Query[{
            changed = { "core/world/status" },
            with = { "WorldShared" },
            without = { "WorldMirror" },
        }],
        Query[{
            with = { "core/world/status", "WorldShared" },
            without = { "WorldMirror" },
        }],
        WAYS,
    }, function(touched, moved, rows, ways)
        local me = rows:iter()[1]
        local watching = me ~= nil and me:get("core/world/status").observer == true
        return not watching and not (touched:is_empty() and moved:is_empty() and ways:is_empty())
    end)

-- Each frame, as a camera follows: the label stands 0.5 m over the top of its portal (its own mesh
-- and its mesh children, the label left out; 1.2 m for a 3d portal and 2 m for a door until their
-- bounds are known), turned about Y so its face looks at this client's eye.
app:add_systems(Update, {
    Query[{ with = { "scope/portal/view/label", "ChildOf", Mut["transform/follow"] } }],
    Query[{
        with = { "scope/portal/view", "GlobalTransform" },
        optional = { "Aabb", "Children" },
    }],
    Query[{
        with = { "Mesh3d", "Aabb", "Transform" },
        without = { "scope/portal/view/label" },
    }],
    Query[{ with = { "camera/3d/eye", "GlobalTransform" } }],
}, function(labels, portals, surfaces, eyes)
    local eye = eyes:iter()[1]
    local seen = eye and eye.GlobalTransform:compute_transform().translation
    for _, l in ipairs(labels:iter_mut()) do
        local p = portals:get(l:get("ChildOf"))
        if p ~= nil then
            local top
            if p:has("Aabb") then
                local box = p:get("Aabb")
                top = box.center.y + box.half_extents.y
            end
            for _, s in ipairs(surfaces:iter_many(p:get("Children") or {})) do
                local box, at = s:get("Aabb"), s:get("Transform").translation
                local y = at.y + box.center.y + box.half_extents.y
                if top == nil or y > top then top = y end
            end
            top = top or (p:get("scope/portal/view").mode == "3d" and 1.2 or 2.0)
            local offset = { x = 0, y = top + 0.5, z = 0 }
            local follow = l:get("transform/follow")
            local rotation = follow.rotation
            if seen ~= nil then
                local at = p.GlobalTransform:compute_transform().translation
                local dx, dz = seen.x - at.x, seen.z - at.z
                if dx * dx + dz * dz > 1e-6 then
                    rotation = Quat.from_rotation_y((math.atan2 or math.atan)(dx, dz))
                end
            end
            local was = follow.offset or {}
            if was.y == nil or math.abs(was.y - offset.y) > 1e-3 or was.x ~= 0 or was.z ~= 0
                    or follow.rotation == nil or not Quat.abs_diff_eq(follow.rotation, rotation, 1e-4) then
                local f = l:get_mut("transform/follow")
                f.offset = offset
                f.rotation = rotation
            end
        end
    end
end):in_set("scope/portal/view/label_face")

-- The label's screen: once `ui/screen` made its root, one line of text with no background, over
-- its outline. Each copy fills the root and centres its text, the outline's set off by its pixels;
-- the copies say again what they say when the label or its sessions reply changes.
app:add_systems(Update, {
    Query[{ with = { "scope/portal/view/label" }, optional = { "Children", "ui/screen" } }],
    Query[{ with = { "ui/screen/camera" } }],
    Query[{
        with = { "ui/screen/root", "UiTargetCamera", Mut["Node"] },
        optional = { "Children" },
    }],
    Query[{ with = { "scope/portal/view/line", Mut["Text"] } }],
    Query[{
        with = { "core/registry/sessions", "Request" },
        optional = { "core/registry/sessions/reply" },
    }],
    Commands,
}, function(labels, cameras, roots, lines, asks, commands)
    for _, l in ipairs(labels:iter()) do
        local kids = l:get("Children") or {}
        local camera = cameras:iter_many(kids)[1]
        local ask = asks:iter_many(kids)[1]
        local said = ask and ask:has("core/registry/sessions/reply") and ask:get("core/registry/sessions/reply") or nil
        local text = label_text(l:get("scope/portal/view/label").target, said)
        if camera ~= nil then
            for _, r in ipairs(roots:iter_mut()) do
                if r:get("UiTargetCamera") == camera:id() then
                    local shown = lines:iter_many_mut(lines:iter_descendants(r:id()))
                    if #shown == 0 then
                        local function layer(dx, dy)
                            return commands:spawn({
                                Node = {
                                    position_type = "Absolute",
                                    left = { Px = dx }, top = { Px = dy },
                                    width = { Percent = 100 }, height = { Percent = 100 },
                                    justify_content = "Center", align_items = "Center",
                                },
                                Pickable = { should_block_lower = false, is_hoverable = false },
                                ChildOf = r:id(),
                            }):id()
                        end
                        for _, at in ipairs(OUTLINE) do
                            commands:spawn({ ["scope/portal/view/line"] = { part = "outline" }, Text = { text = text },
                                TextFont = { font_size = 34 }, TextLayout = NO_WRAP, TextColor = { color = OUTLINE_COLOR },
                                ChildOf = layer(at[1], at[2]) })
                        end
                        commands:spawn({ ["scope/portal/view/line"] = { part = "text" }, Text = { text = text },
                            TextFont = { font_size = 34 }, TextLayout = NO_WRAP, ["ui/style"] = { text = "text" }, ChildOf = layer(0, 0) })
                    elseif shown[1]:get("Text") ~= text then
                        for _, line in ipairs(shown) do
                            line:get_mut("Text"):set_if_neq(text)
                        end
                        -- The transparent screen is never cleared: a new image, so the old text
                        -- doesn't stay under the new.
                        local screen = l:get("ui/screen")
                        if screen ~= nil then
                            commands:entity(l:id()):insert({ ["ui/screen"] = {
                                width = screen.width, height = screen.height, transparent = screen.transparent,
                                fresh = (screen.fresh or 0) + 1,
                            } })
                        end
                    end
                end
            end
        end
    end
end):in_set("scope/portal/view/label_text")
    :run_if({
        Query[{
            ["or"] = {
                added = { "ui/screen/root", "scope/portal/view/label" },
                changed = { "scope/portal/view/label", "core/registry/sessions/reply" },
            },
        }],
    }, function(touched)
        return not touched:is_empty()
    end)
