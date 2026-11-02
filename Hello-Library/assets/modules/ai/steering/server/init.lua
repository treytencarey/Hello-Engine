-- Walks an agent along its path from `ai/nav/path`, keeps it apart from its neighbours and says
-- how it went. It writes `Velocity3d` and lets Rapier move the body, as a walking player does, so
-- agents and players collide alike. Missing fields get defaults when it is added.
--
-- ai/steering = {
--     speed = <metres per second>,
--     arrive_radius = <metres from the last waypoint that count as there>,
--     pass_radius = <metres from any other waypoint that count as past it>,
--     height_radius = <metres of height from a waypoint that count as on its floor>,
--     ease_radius = <metres from the last waypoint at which it starts slowing>,
--     ease_floor = <the share of its speed it slows to>,
--     separation_radius = <metres within which a neighbour pushes it away>,
--     separation_strength = <how hard a neighbour pushes, as a share of its speed>,
--     turn_speed = <how fast it turns to face where it goes, per second>,
--     stall_sample = <seconds between checks that it is getting anywhere>,
--     stall_distance = <metres it must cover between checks>,
--     stall_timeout = <seconds without getting anywhere before it is blocked>,
-- }
--
-- ai/steering/state = {
--     status = "idle" | "moving" | "arrived" | "blocked",
--     cursor = <index of the waypoint it walks to>,
--     for_solved = <the `ai/nav/path` `solved_id` this progress belongs to>,
--     stall_x = <where it was at the last check>,
--     stall_z = <where it was at the last check>,
--     stall_t = <Time's elapsed seconds at the last check>,
--     stuck_for = <seconds it has not got anywhere>,
-- }
--
-- It adds a `Velocity3d` when there is none, which stays when `ai/steering` goes.

local Quat = require("bevy::math::Quat")
local Vec3 = require("bevy::math::Vec3")
local Time = require("bevy::time::Time")

app:add_systems(First, {
    Query[{
        added = { "ai/steering" },
        optional = { "Velocity3d", "ai/steering/state" },
    }],
    Commands,
}, function(added, commands)
    for _, e in ipairs(added:iter()) do
        local s = e:get("ai/steering")
        local entity = commands:entity(e:id())
        entity:patch({
            ["ai/steering"] = {
                speed = s.speed or 2,
                arrive_radius = s.arrive_radius or 0.9,
                pass_radius = s.pass_radius or 0.7,
                height_radius = s.height_radius or 1.5,
                ease_radius = s.ease_radius or 2.25,
                ease_floor = s.ease_floor or 0.25,
                separation_radius = s.separation_radius or 1.5,
                separation_strength = s.separation_strength or 1.2,
                turn_speed = s.turn_speed or 6,
                stall_sample = s.stall_sample or 0.5,
                stall_distance = s.stall_distance or 0.25,
                stall_timeout = s.stall_timeout or 1.5,
            },
        })
        if not e:has("Velocity3d") then
            entity:insert({ Velocity3d = { linvel = { x = 0, y = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } } })
        end
        -- A reload runs this again, and the progress carries on.
        if not e:has("ai/steering/state") then
            entity:insert({ ["ai/steering/state"] = { status = "idle", cursor = 1, stuck_for = 0 } })
        end
    end
end):in_set("ai/steering/init")

-- A new path starts from its first waypoint. A reload re-sees every path as changed, and
-- `for_solved` keeps that from starting one again.
app:add_systems(Update, {
    Res[Time],
    Query[{
        ["or"] = {
            added = { "ai/steering/state" },
            changed = { "ai/nav/path" },
        },
        with = { "ai/steering", Mut["ai/steering/state"], "ai/nav/path", "Transform", Mut["Velocity3d"] },
    }],
}, function(time, paths)
    for _, e in ipairs(paths:iter_mut()) do
        local path = e:get("ai/nav/path")
        local state = e:get("ai/steering/state")
        if path.solved_id ~= state.for_solved then
            local at = e:get("Transform").translation
            e:patch({
                ["ai/steering/state"] = {
                    status = #path.path > 0 and "moving" or "idle",
                    cursor = 1,
                    for_solved = path.solved_id,
                    stall_x = at.x,
                    stall_z = at.z,
                    stall_t = time:elapsed_secs(),
                },
            })
            -- No way to go: it stands still rather than gliding on.
            if #path.path == 0 then
                e:patch({ Velocity3d = { linvel = { x = 0, z = 0 } } })
            end
        end
    end
end):in_set("ai/steering/start")

-- The direction from one point to another on the ground, and how far it is.
local function towards(from, to)
    local delta = { x = to.x - from.x, y = 0, z = to.z - from.z }
    return Vec3.normalize_or_zero(delta), Vec3.length(delta)
end

-- This is the movement loop, so it polls, as a walking player does. `ai/steering/state` is
-- written only when something changes, and its stall check is sampled, so a walking agent
-- writes it twice a second at most.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "ai/steering", Mut["ai/steering/state"], "ai/nav/path", Mut["Transform"], Mut["Velocity3d"] },
    }],
}, function(time, agents)
    local now = time:elapsed_secs()
    local dt = time:delta_secs()
    local rows = agents:iter_mut()

    local crowd = {}
    for _, e in ipairs(rows) do
        crowd[#crowd + 1] = { id = e:id(), at = e:get("Transform").translation }
    end

    for _, e in ipairs(rows) do
        local s = e:get("ai/steering")
        local state = e:get("ai/steering/state")
        local path = e:get("ai/nav/path").path
        local transform = e:get("Transform")
        local at = transform.translation
        local cursor = state.cursor

        if state.status == "moving" and path[cursor] ~= nil then
            local along, distance = towards(at, path[cursor])
            local writes = {}

            -- Waypoints on the way only need brushing past; the last must be reached. One straight
            -- overhead or underfoot is on another floor, and is not reached until it stops being so.
            if distance <= (cursor < #path and s.pass_radius or s.arrive_radius)
                and math.abs(at.y - path[cursor].y) <= s.height_radius then
                cursor = cursor + 1
                writes.cursor = cursor
                if path[cursor] ~= nil then
                    along, distance = towards(at, path[cursor])
                end
            end

            if path[cursor] == nil then
                writes.status = "arrived"
                e:patch({
                    Velocity3d = { linvel = { x = 0, z = 0 }, angvel = { x = 0, y = 0, z = 0 } },
                    ["ai/steering/state"] = writes,
                })
            else
                local speed = s.speed
                -- It eases off so it settles instead of swinging around the goal.
                if cursor == #path and distance < s.ease_radius then
                    speed = speed * math.max(s.ease_floor, distance / s.ease_radius)
                end

                local x, z = along.x * speed, along.z * speed
                for _, other in ipairs(crowd) do
                    if other.id ~= e:id() then
                        local away, gap = towards(other.at, at)
                        if gap > 0.001 and gap < s.separation_radius then
                            local push = (1 - gap / s.separation_radius) * s.separation_strength * speed
                            x, z = x + away.x * push, z + away.z * push
                        end
                    end
                end

                e:patch({ Velocity3d = { linvel = { x = x, z = z }, angvel = { x = 0, y = 0, z = 0 } } })

                if math.abs(x) + math.abs(z) > 0.01 then
                    e:patch({
                        Transform = {
                            rotation = Quat.slerp(transform.rotation,
                                Quat.from_rotation_arc({ x = 0, y = 0, z = 1 }, Vec3.normalize_or_zero({ x = x, y = 0, z = z })),
                                math.min(1, s.turn_speed * dt)),
                        },
                    })
                end

                local since = now - state.stall_t
                if since >= s.stall_sample then
                    local _, moved = towards({ x = state.stall_x, z = state.stall_z }, at)
                    writes.stuck_for = moved < s.stall_distance and state.stuck_for + since or 0
                    if writes.stuck_for >= s.stall_timeout then
                        writes.status = "blocked"
                        e:patch({ Velocity3d = { linvel = { x = 0, z = 0 } } })
                    end
                    writes.stall_x = at.x
                    writes.stall_z = at.z
                    writes.stall_t = now
                end

                if next(writes) ~= nil then
                    e:patch({ ["ai/steering/state"] = writes })
                end
            end
        end
    end
end):in_set("ai/steering/walk"):after("ai/steering/start")

-- Its path was taken away: nothing writes its velocity any more, so it stands still.
app:add_systems(Update, {
    Query[{
        removed = { "ai/nav/path" },
        with = { "ai/steering", Mut["ai/steering/state"], Mut["Velocity3d"] },
    }],
}, function(lost)
    for _, e in ipairs(lost:iter_mut()) do
        e:patch({
            Velocity3d = { linvel = { x = 0, z = 0 } },
            ["ai/steering/state"] = { status = "idle" },
        })
    end
end):in_set("ai/steering/stop")

-- `ai/steering` was taken off an entity that stays: it stands still. A despawned entity has no
-- row here. `ai/steering/state` goes by `mod_registry`.
app:add_systems(First, {
    Query[{
        removed = { "ai/steering" },
        with = { Mut["Velocity3d"] },
    }],
}, function(removed)
    for _, e in ipairs(removed:iter_mut()) do
        e:patch({ Velocity3d = { linvel = { x = 0, z = 0 } } })
    end
end):in_set("ai/steering/removed")
