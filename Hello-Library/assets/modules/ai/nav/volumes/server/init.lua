-- Turns the `ai/nav/volume`s on an entity and below it into `ai/nav/region`s, children of that
-- entity. A volume is the area to consider: what is walkable inside it is sampled against the
-- collision world, so an obstacle standing in it becomes a hole the route goes around. Attach a
-- child mod, which brings this along: `ai/nav/volumes/box` or `ai/nav/volumes/scene`. Missing
-- fields get defaults when it is added.
--
-- ai/nav/volumes = {
--     sample = <false to trust the volumes as they are>,
--     cell = <metres between samples>,
--     max_step = <metres of height between neighbouring cells that is still walkable>,
--     cost = <the regions' cost>,
--     settle = <seconds without new geometry before it bakes>,
--     rays_per_frame = <samples per frame>,
-- }
--
-- ai/nav/volume = { hx, hy, hz }: half extents, on an entity whose transform places it
--
-- ai/nav/volumes/due = { at = <Time's elapsed seconds when the bake may start> }: while a bake is owed
-- ai/nav/volumes/job = { vols, vi, grid, ix, iz, rects }: a sampling bake in progress
-- ai/nav/volumes/region: marks a region this mod spawned

local Grid = require("modules/ai/nav/volumes/server/grid.lua")
local Time = require("bevy::time::Time")
local On = require("bevy::ecs::prelude::On")
local SceneInstanceReady = require("bevy::scene::SceneInstanceReady")
local ReadRapierContext = require("bevy_rapier3d::plugin::ReadRapierContext")

app:add_systems(First, {
    Res[Time],
    Query[{ added = { "ai/nav/volumes" } }],
    Commands,
}, function(time, added, commands)
    for _, e in ipairs(added:iter()) do
        local v = e:get("ai/nav/volumes")
        commands:entity(e:id()):patch({
            ["ai/nav/volumes"] = {
                sample = v.sample ~= false,
                cell = v.cell or 1,
                max_step = v.max_step or 0.45,
                cost = v.cost or 1,
                settle = v.settle or 0.35,
                rays_per_frame = v.rays_per_frame or 400,
            },
            ["ai/nav/volumes/due"] = { at = time:elapsed_secs() + (v.settle or 0.35) },
        })
    end
end):in_set("ai/nav/volumes/init")

-- Every carrier owes a bake, once things have stopped arriving: each arrival pushes it back.
local function owe(time, carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        local v = e:get("ai/nav/volumes")
        commands:entity(e:id()):try_remove("ai/nav/volumes/job")
        commands:entity(e:id()):try_insert({
            ["ai/nav/volumes/due"] = { at = time:elapsed_secs() + (v.settle or 0) },
        })
    end
end

-- A volume arriving, changing or going. Runs before the fill above, which replaces this for an
-- entity that has only just arrived.
app:add_systems(First, {
    Res[Time],
    Query[{
        ["or"] = {
            changed = { "ai/nav/volume" },
            removed = { "ai/nav/volume" },
        },
    }],
    Query[{ with = { "ai/nav/volumes" } }],
    Commands,
}, function(time, touched, carriers, commands)
    if not touched:is_empty() then
        owe(time, carriers, commands)
    end
end):in_set("ai/nav/volumes/watch"):before("ai/nav/volumes/init")

-- A scene ready, new or respawned after its file changed: its geometry may be what the rays hit.
app:add_observer(On[SceneInstanceReady], {
    Res[Time],
    Query[{ with = { "ai/nav/volumes" } }],
    Commands,
}, function(_, time, carriers, commands)
    owe(time, carriers, commands)
end)

-- Timed, and a bake that samples runs over several frames, so it polls while one is owed.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "ai/nav/volumes", "ai/nav/volumes/due" },
        optional = { "ai/nav/volumes/job", "Children" },
    }],
    Query[{ with = { "ai/nav/volume", "GlobalTransform" } }],
    Query[{ with = { "ai/nav/volumes/region" } }],
    ReadRapierContext,
    Commands,
}, function(time, owed, volumes, baked, rapier, commands)
    local now = time:elapsed_secs()
    for _, e in ipairs(owed:iter()) do
        if now >= e:get("ai/nav/volumes/due").at then
            local v = e:get("ai/nav/volumes")
            local job = e:get("ai/nav/volumes/job")
            if job == nil then
                local list = volumes:iter_descendants(e:id())
                list[#list + 1] = e:id()
                local vols = {}
                for _, node in ipairs(volumes:iter_many(list)) do
                    local volume = node:get("ai/nav/volume")
                    if volume.hx and volume.hz and volume.hx > 0 and volume.hz > 0 then
                        local at = node.GlobalTransform:compute_transform().translation
                        local hy = volume.hy or 0
                        -- agents walk on the bottom of the volume
                        vols[#vols + 1] = { x = at.x, z = at.z, hx = volume.hx, hy = hy, hz = volume.hz, floor_y = at.y - hy }
                    end
                end
                job = { vols = vols, vi = 1, rects = {} }
            end

            local budget = v.rays_per_frame
            while job.vi <= #job.vols and budget > 0 do
                local vol = job.vols[job.vi]
                if not v.sample then
                    job.rects[#job.rects + 1] = {
                        min_x = vol.x - vol.hx,
                        max_x = vol.x + vol.hx,
                        min_z = vol.z - vol.hz,
                        max_z = vol.z + vol.hz,
                        y = vol.floor_y,
                    }
                    job.vi = job.vi + 1
                else
                    if not job.grid then
                        job.grid = Grid.new(vol.x - vol.hx, vol.z - vol.hz, vol.x + vol.hx, vol.z + vol.hz, v.cell)
                        job.ix, job.iz = 1, 1
                    end
                    -- from above the volume, down through it and a little under
                    local top = vol.floor_y + vol.hy * 2 + 2
                    while job.iz <= job.grid.h and budget > 0 do
                        local x, z = Grid.cell_center(job.grid, job.ix, job.iz)
                        -- Something standing on the floor is not floor, so only fixed bodies count.
                        local hit = rapier:cast_ray({ x = x, y = top, z = z }, { x = 0, y = -1, z = 0 }, vol.hy * 4 + 6, true, {
                            flags = "ONLY_FIXED",
                        })
                        job.grid.floor[job.iz][job.ix] = hit ~= nil and top - hit.toi or false
                        job.ix = job.ix + 1
                        if job.ix > job.grid.w then
                            job.ix, job.iz = 1, job.iz + 1
                        end
                        budget = budget - 1
                    end
                    if job.iz > job.grid.h then
                        Grid.mark_walkable(job.grid, v.max_step)
                        for _, r in ipairs(Grid.merge_rects(job.grid)) do
                            job.rects[#job.rects + 1] = r
                        end
                        job.grid = nil
                        job.vi = job.vi + 1
                    end
                end
            end

            local entity = commands:entity(e:id())
            if job.vi > #job.vols then
                for _, old in ipairs(baked:iter_many(e:get("Children") or {})) do
                    commands:entity(old:id()):despawn()
                end
                for _, r in ipairs(job.rects) do
                    commands:spawn({
                        ["ai/nav/region"] = {
                            min_x = r.min_x,
                            max_x = r.max_x,
                            min_z = r.min_z,
                            max_z = r.max_z,
                            y = r.y,
                            cost = v.cost,
                        },
                        ["ai/nav/volumes/region"] = {},
                        ChildOf = e:id(),
                    })
                end
                entity:remove("ai/nav/volumes/due", "ai/nav/volumes/job")
            else
                entity:insert({ ["ai/nav/volumes/job"] = job })
            end
        end
    end
end):in_set("ai/nav/volumes/bake")
