-- The eye of a 3D camera: a Camera3d child of the carrier, turned to the carrier's
-- `camera` yaw and pitch and placed at `camera/3d.offset` from it. The eye follows the
-- carrier but not its rotation (`transform/follow`). The camera mod extending this one
-- (first_person, third_person) writes the offset. Only the local player's carrier gets
-- an eye. It turns off while the player is in another world, goes with the carrier when
-- it despawns, and is despawned when `camera/3d` is removed.
--
-- While something else shows the carrier's view, the carrier has no eye. The screen shows the
-- camera added last, so the view comes back only with a freshly spawned eye: an old one turned
-- back on would stay behind the other view.
--
-- camera/3d = {
--     offset = { x = <metres>, y = <metres>, z = <metres> },  -- from the carrier, world space
-- }
--
-- camera/3d/eye = {}
--
-- camera/3d/view_of = { entity = <the carrier> }: on an entity showing the carrier's view instead,
-- put there by the mod that shows it. Client only, never synced.
--
-- camera/3d/viewed_by = { <entity>, ... }: on the carrier, kept by the engine

local Quat = require("bevy::math::Quat")

local function follow(cam, c3d)
    local yaw = Quat.from_rotation_y(cam.yaw or 0)
    local pitch = Quat.from_rotation_x(cam.pitch or 0)
    return {
        rotation = Quat.mul_quat(yaw, pitch),
        offset = c3d.offset,
    }
end

local function eye(cam, c3d)
    return {
        Camera3d = {},
        Camera = { order = 0, is_active = true },
        Transform = {},
        IsDefaultUiCamera = true,
        ["transform/follow"] = follow(cam, c3d),
        ["camera/3d/eye"] = {},
    }
end

-- `camera` arrives as `{}` and its own mod may load a frame later, so a new eye can be
-- spawned before `camera` has its defaults. It starts level; filling them is a change to
-- `camera`, and `camera/3d/aim` turns the eye then.
app:add_systems(First, {
    Query[{
        ["or"] = {
            added = { "camera/3d", "camera", "core/net/owner" },
            changed = { "core/net/owner" },
        },
        with = { "camera/3d", "camera", "core/net/owner" },
        without = { "camera/3d/viewed_by" },
        optional = { "Children" },
    }],
    Query[{
        with = { "camera/3d/eye", Mut["Camera"] },
    }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(carriers, all_eyes, own, commands)
    for _, e in ipairs(carriers:iter()) do
        if own:contains(e:get("core/net/owner")) then
            -- Back from another world, a fresh eye, never the one turned off when it left: the
            -- screen shows the camera added last. One still on (a switch of camera mod) stays.
            local on = false
            for _, old in ipairs(all_eyes:iter_many_mut(e:get("Children") or {})) do
                if old:get("Camera").is_active == false then
                    commands:entity(old:id()):despawn()
                else
                    on = true
                end
            end
            if not on then
                commands:entity(e:id()):add_child(commands:spawn(eye(e:get("camera"), e:get("camera/3d"))):id())
            end
        end
    end
end):in_set("camera/3d/spawn")

app:add_systems(First, {
    Query[{
        added = { "camera/3d/viewed_by" },
        with = { "camera/3d" },
        optional = { "Children" },
    }],
    Query[{ with = { "camera/3d/eye" } }],
    Commands,
}, function(viewed, all_eyes, commands)
    for _, e in ipairs(viewed:iter()) do
        for _, old in ipairs(all_eyes:iter_many(e:get("Children") or {})) do
            commands:entity(old:id()):despawn()
        end
    end
end):in_set("camera/3d/yield")

-- A view moved from one entity to another in one flush can take the list away and bring it back,
-- so a carrier viewed again by now gets no eye.
app:add_systems(First, {
    Query[{
        removed = { "camera/3d/viewed_by" },
        with = { "camera/3d", "camera", "core/net/owner" },
        without = { "camera/3d/viewed_by" },
        optional = { "Children" },
    }],
    Query[{ with = { "camera/3d/eye" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(released, all_eyes, own, commands)
    for _, e in ipairs(released:iter()) do
        if own:contains(e:get("core/net/owner")) and #all_eyes:iter_many(e:get("Children") or {}) == 0 then
            commands:entity(e:id()):add_child(commands:spawn(eye(e:get("camera"), e:get("camera/3d"))):id())
        end
    end
end):in_set("camera/3d/resume")

-- The player left for another world: its eye stops rendering this one. A carrier still this
-- client's keeps it.
app:add_systems(First, {
    Query[{
        ["or"] = { removed = { "core/net/owner" }, changed = { "core/net/owner" } },
        with = { "camera/3d" },
        optional = { "Children", "core/net/owner" },
    }],
    Query[{
        with = { "camera/3d/eye", Mut["Camera"] },
    }],
    Query[{ with = { "camera/3d" }, optional = { "core/net/owner" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
}, function(carriers, all_eyes, live, own)
    for _, e in ipairs(carriers:iter()) do
        local now = live:get(e:id())
        local owner = now and now:get("core/net/owner")
        if owner == nil or not own:contains(owner) then
            for _, eye in ipairs(all_eyes:iter_many_mut(e:get("Children") or {})) do
                eye:patch({ Camera = { is_active = false } })
            end
        end
    end
end):in_set("camera/3d/teardown")

-- The camera mods extending this one order their writes of `camera` and `camera/3d` before
-- this system, so the eye turns and moves in the frame they change.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            changed = { "camera", "camera/3d" },
        },
        with = { "camera", "camera/3d" },
        optional = { "Children" },
    }],
    Query[{
        with = { "camera/3d/eye", Mut["transform/follow"] },
    }],
}, function(carriers, all_eyes)
    for _, e in ipairs(carriers:iter()) do
        local cam = e:get("camera")
        local c3d = e:get("camera/3d")
        for _, eye in ipairs(all_eyes:iter_many_mut(e:get("Children") or {})) do
            eye:patch({ ["transform/follow"] = follow(cam, c3d) })
        end
    end
end):in_set("camera/3d/aim")

-- ZZPROBE: temporary. Every camera in this world and which carry the default UI marker, logged
-- whenever that changes.
local zz_last
app:add_systems(Last, {
    Query[{ with = { "Camera" }, optional = { "IsDefaultUiCamera", "camera/3d/eye", "ChildOf" } }],
    Query[{ with = { "core/world/status", "WorldShared" }, without = { "WorldMirror" } }],
}, function(cameras, rows)
    local parts, marked = {}, 0
    for _, c in ipairs(cameras:iter()) do
        local ok, cam = pcall(function() return c:get("Camera") end)
        local ui = c:has("IsDefaultUiCamera")
        if ui then marked = marked + 1 end
        parts[#parts + 1] = string.format("%s{ui=%s active=%s order=%s eye=%s parent=%s}", tostring(c:id()), tostring(ui),
            tostring(ok and cam and cam.is_active), tostring(ok and cam and cam.order), tostring(c:has("camera/3d/eye")),
            tostring(c:get("ChildOf")))
    end
    table.sort(parts)
    local line = table.concat(parts, " ")
    if line ~= zz_last then
        zz_last = line
        local me = rows:iter()[1]
        print(string.format("[ZZPROBE] cameras in %s: %d marked of %d: %s",
            tostring(me and me:get("core/world/status").scope_key), marked, #parts, line))
    end
end)

-- ZZPROBE: temporary. The sidebar's containers, the camera Bevy gave each, its laid-out size and
-- display, and the players holding the sidebar, logged whenever that changes.
local zz_ui_last
local function zz_field(c, name, key)
    local ok, v = pcall(function() return c:get(name) end)
    if not ok or v == nil then return "nil" end
    if type(v) ~= "table" then return tostring(v) end
    if key then return tostring(v[key]) end
    local parts = {}
    for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(type(x) == "table" and (x.x and (x.x .. "x" .. tostring(x.y))) or x) end
    table.sort(parts)
    return table.concat(parts, ",")
end
app:add_systems(Last, {
    Query[{ with = { "sidebar/container" }, optional = { "Node", "ComputedNode", "ComputedUiTargetCamera", "InheritedVisibility", "ChildOf" } }],
    Query[{ with = { "Node" }, without = { "ChildOf" } }],
    Query[{ with = { "sidebar", "core/net/owner" }, optional = { "sidebar/open" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Query[{ with = { "Camera" } }],
    Query[{ with = { "core/world/status", "WorldShared" }, without = { "WorldMirror" } }],
}, function(containers, roots, players, own, cameras, rows)
    local parts = {}
    for _, c in ipairs(containers:iter()) do
        local target = zz_field(c, "ComputedUiTargetCamera")
        parts[#parts + 1] = string.format("%s{display=%s target=%s size=%s visible=%s parent=%s}", tostring(c:id()),
            zz_field(c, "Node", "display"), target, zz_field(c, "ComputedNode", "size"),
            zz_field(c, "InheritedVisibility"), tostring(c:get("ChildOf")))
    end
    local held = {}
    for _, p in ipairs(players:iter()) do
        held[#held + 1] = string.format("%s{mine=%s open=%s}", tostring(p:id()),
            tostring(own:contains(p:get("core/net/owner"))), tostring(p:has("sidebar/open")))
    end
    table.sort(parts)
    table.sort(held)
    local line = string.format("%d container(s): %s | %d UI root(s), %d camera(s) | players: %s", #parts,
        table.concat(parts, " "), #roots:iter(), #cameras:iter(), table.concat(held, " "))
    if line ~= zz_ui_last then
        zz_ui_last = line
        local me = rows:iter()[1]
        print(string.format("[ZZPROBE-UI] sidebar in %s: %s",
            tostring(me and me:get("core/world/status").scope_key), line))
    end
end)

return {
    base = "camera",
    defaults = {
        ["camera/3d"] = {
            offset = { x = 0, y = 0, z = 0 },
        },
    },
    relationships = {
        ["camera/3d/view_of"] = { target = "camera/3d/viewed_by" },
    },
}
