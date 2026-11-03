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
--     headroom = <metres a floor needs under the surface above it>,
--     wall_height = <metres above a floor at which something in its cell is in the way>,
--     cost = <the regions' cost>,
--     settle = <seconds without new geometry before it bakes>,
-- }
--
-- ai/nav/volume = { hx, hy, hz }: half extents, on an entity whose transform places it
--
-- ai/nav/volumes/due = { at = <Time's elapsed seconds when the bake may start> }: while a bake is owed
-- ai/nav/volumes/job = { vols, vi, grid, ix, iz, y, inside, ceiling, rects }: a sampling bake in
-- progress, `y`, `inside` and `ceiling` being how far down this column it has got
-- ai/nav/volumes/region: marks a region this mod spawned

local Grid = require("modules/ai/nav/volumes/server/grid.lua")
local Time = require("bevy::time::Time")
local LuaFrameBudget = require("bevy_lua_ecs::lua_frame_budget::LuaFrameBudget")
local any_match_filter = require("bevy::ecs::schedule::common_conditions::any_match_filter")
local any_component_removed = require("bevy::ecs::schedule::common_conditions::any_component_removed")
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
        commands:entity(e:id()):insert({ ["ai/nav/volumes/due"] = { at = time:elapsed_secs() + v.settle } })
    end
end):in_set("ai/nav/volumes/init")

-- Every carrier owes a bake, once things have stopped arriving: each arrival pushes it back.
local function owe(time, carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        local v = e:get("ai/nav/volumes")
        commands:entity(e:id()):try_remove("ai/nav/volumes/job")
        commands:entity(e:id()):try_insert({
            ["ai/nav/volumes/due"] = { at = time:elapsed_secs() + v.settle },
        })
    end
end

local volume_changed = any_match_filter[{ changed = { "ai/nav/volume" } }]

-- A volume arriving, changing or going.
app:add_systems(First, {
    Res[Time],
    Query[{ with = { "ai/nav/volumes" } }],
    Commands,
}, function(time, carriers, commands)
    owe(time, carriers, commands)
end):in_set("ai/nav/volumes/watch")
    :run_if(volume_changed["or"](volume_changed, any_component_removed["ai/nav/volume"]))

-- A scene ready, new or respawned after its file changed: its geometry may be what the rays hit.
app:add_observer(On[SceneInstanceReady], {
    Res[Time],
    Query[{ with = { "ai/nav/volumes" } }],
    Commands,
}, function(_, time, carriers, commands)
    owe(time, carriers, commands)
end)

-- Whether something stands in a cell, looked for sideways from its centre, above what a step could
-- climb. A little past the cell's edge, as a wall lined up with the grid has its faces on those edges.
local function blocked(rapier, x, y, z, cell)
    for _, dir in ipairs({ { x = 1, y = 0, z = 0 }, { x = -1, y = 0, z = 0 }, { x = 0, y = 0, z = 1 }, { x = 0, y = 0, z = -1 } }) do
        if rapier:cast_ray({ x = x, y = y, z = z }, dir, cell * 0.55, true, { flags = "ONLY_FIXED" }) ~= nil then
            return true
        end
    end
    return false
end

-- Timed, and a bake that samples runs over several frames, so it polls while one is owed, until
-- the system's slice of the frame is spent.
app:add_systems(Update, {
    Res[Time],
    Res[LuaFrameBudget],
    Query[{
        with = { "ai/nav/volumes", "ai/nav/volumes/due" },
        optional = { "ai/nav/volumes/job", "Children" },
    }],
    Query[{ with = { "ai/nav/volume", "GlobalTransform" } }],
    Query[{ with = { "ai/nav/volumes/region" } }],
    ReadRapierContext,
    Commands,
}, function(time, budget, owed, volumes, baked, rapier, commands)
    local now = time:elapsed_secs()
    local spent = false
    for _, e in ipairs(owed:iter()) do
        if not spent and now >= e:get("ai/nav/volumes/due").at then
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

            while job.vi <= #job.vols and not spent do
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
                    local bottom = top - (vol.hy * 4 + 6)
                    local x, z = Grid.cell_center(job.grid, job.ix, job.iz)
                    local y = job.y or top
                    -- Something standing on the floor is not floor, so only fixed bodies count. A
                    -- solid ray that starts inside a collider stops where it starts, at 0, and only a
                    -- hollow one goes on to where it leaves. So the ray under a floor is solid, to find
                    -- whether it is inside, and then a hollow one finds the way out. A trimesh is only a
                    -- surface, with no inside: the ray goes on to its underside and reads that as the next
                    -- height, which is not a floor unless the mesh is thicker than `headroom`. Then only
                    -- its sides tell, in the cells they pass through, which keeps anything from walking
                    -- into what is left inside it.
                    local hit = y > bottom and rapier:cast_ray({ x = x, y = y, z = z }, { x = 0, y = -1, z = 0 }, y - bottom,
                        not job.inside, { flags = "ONLY_FIXED" }) or nil

                    local more = false
                    if hit ~= nil and job.inside then
                        job.ceiling = y - hit.toi
                        job.y, job.inside, more = job.ceiling - 0.01, nil, true
                    elseif hit ~= nil and job.y ~= nil and hit.toi < 0.005 then
                        job.inside, more = true, true
                    elseif hit ~= nil then
                        local height = y - hit.toi
                        if job.ceiling == nil or job.ceiling - height >= v.headroom then
                            local floors = job.grid.floor[job.iz][job.ix]
                            table.insert(floors, height)
                            if blocked(rapier, x, height + v.wall_height, z, v.cell) then
                                job.grid.blocked[job.iz][job.ix][#floors] = true
                            end
                        end
                        job.ceiling = height
                        job.y = height - 0.01
                        -- Anything lower, within the volume, could not have the headroom.
                        more = height > vol.floor_y + v.headroom
                    end

                    if not more then
                        job.y, job.inside, job.ceiling = nil, nil, nil
                        job.ix = job.ix + 1
                        if job.ix > job.grid.w then
                            job.ix, job.iz = 1, job.iz + 1
                        end
                    end
                    if job.iz > job.grid.h then
                        Grid.mark_walkable(job.grid, v.max_step)
                        for _, r in ipairs(Grid.merge_rects(job.grid, v.max_step)) do
                            job.rects[#job.rects + 1] = r
                        end
                        job.grid = nil
                        job.vi = job.vi + 1
                    end
                end
                spent = budget:over_budget()
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
                            min_y = r.min_y,
                            max_y = r.max_y,
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

return {
    defaults = {
        ["ai/nav/volumes"] = {
            sample = true,
            cell = 1,
            max_step = 0.45,
            headroom = 2,
            wall_height = 0.6,
            cost = 1,
            settle = 0.35,
        },
    },
}
