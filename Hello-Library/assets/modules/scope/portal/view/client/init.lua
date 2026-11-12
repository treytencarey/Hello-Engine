-- How a portal looks on a client, and the world it shows. A placed portal asks root to observe its
-- target, and root's answer decides: allowed, the target's picture shows through the portal's
-- mesh (`core/compositor/stencil`); refused, the portal is locked and says why. With `"3d"` the
-- view brings its own sphere; with `"none"` the carrier brings its mesh (a glTF door's surface).
-- None of it runs in a world that is itself only being observed; once promoted, it catches up.
--
-- scope/portal/view = {
--     mode = <"3d" | "none">,
-- }

local Assets = require("bevy::asset::Assets")
local Mesh = require("bevy::mesh::Mesh")
local StandardMaterial = require("bevy::pbr::StandardMaterial")
local Sphere = require("bevy::math::primitives::Sphere")
local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")

-- One ask per placed portal, its child: it goes with the portal, and root loads each target once
-- however many ask. `hosted` makes root ask once more after a `not-running` refusal. A portal
-- seen being placed asks with `join_only = false`: root starts its world if nobody runs it and
-- this player may (the Gateway's start gate), and otherwise looks in join-only. So does a door, a
-- portal that arrives with its scene (a `SceneRoot` above it): it is dropped as its map loads. A
-- portal that was placed already when it arrived (an invite's portal, one placed before this
-- client came) asks join-only. The ask is not this file's to reap: a reload that took it would
-- make root drop the observed world and load it again.
app:add_systems(Update, {
    Query[{
        with = { "scope/portal", "scope/portal/view" },
        without = { "placement" },
        optional = { "scope/portal/hosted", "Children" },
    }],
    Query[{ with = { "SceneRoot" } }],
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
    Query[{
        removed = { "placement" },
        with = { "scope/portal" },
    }],
    Commands,
}, function(portals, scenes, asks, records, rows, just_placed, commands)
    local placed = {}
    for _, p in ipairs(just_placed:iter()) do
        placed[#placed + 1] = p:id()
    end
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
        local target = p:get("scope/portal").target
        local hosted = p:has("scope/portal/hosted") or nil
        local start = nil
        for _, id in ipairs(placed) do
            if id == p:id() then start = false end
        end
        if scenes:iter_many(scenes:iter_ancestors(p:id()))[1] ~= nil then start = false end
        local kept
        for _, ask in ipairs(asks:iter_many(p:get("Children") or {})) do
            if kept == nil and target ~= scope and ask:get("core/world/observe").ref == target then
                kept = ask
            else
                commands:entity(ask:id()):despawn()
            end
        end
        if kept ~= nil then
            local was = kept:get("core/world/observe")
            if was.hosted ~= hosted or (start == false and was.join_only ~= false) then
                commands:entity(kept:id()):entry("core/world/observe"):and_modify(function(ask)
                    ask.hosted = hosted
                    if start == false then ask.join_only = false end
                end)
            end
        elseif target ~= scope then
            commands:spawn({
                ["core/world/observe"] = { ref = target, libraries = libraries, hosted = hosted, join_only = start },
                WorldShared = {},
                ["core/net/sync"] = false,
                ["core/script/owner"] = false,
                ChildOf = p:id(),
            })
            print(string.format("[SCOPE/PORTAL/VIEW] asking root to look into %s%s", target,
                start == false and ", starting it if nobody runs it" or ""))
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
    }, function(touched, moved, rows)
        local me = rows:iter()[1]
        local watching = me ~= nil and me:get("core/world/status").observer == true
        return not watching and not (touched:is_empty() and moved:is_empty())
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
    Query[{
        with = { "Mesh3d" },
        optional = { "core/compositor/stencil" },
    }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(portals, answers, meshes, rows, commands)
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
        local target = portal.target
        local answer = target ~= scope and said[target] or nil
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
        if answer ~= nil and answer.state == "allowed" then
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
    }, function(touched, moved, rows, doors)
        local me = rows:iter()[1]
        local watching = me ~= nil and me:get("core/world/status").observer == true
        return not watching and not (touched:is_empty() and moved:is_empty() and doors:is_empty())
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
        if e:get("scope/portal/view").mode == "3d" and target ~= scope then
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
