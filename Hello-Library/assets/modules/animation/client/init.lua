-- The client half: each character's model and the clip it plays, built per entity.
--
-- A character's model is a child (`animation/model`) holding its scene, which spawns its own
-- AnimationPlayer. The clips play through `animation/clip` on that child: this half writes every
-- clip the character has, each at its weight, those silent at 0, so the child's graph stays the
-- same while it fades from one to another. The clip to play comes from the character's motion on
-- this client, or from `animation/action` while that is there.
--
-- animation/model = { scene = <the scene's path> }: the child holding the model's scene.
-- animation/motion = { at = { x, y, z } }: where the character was last frame.
-- animation/playing = { state = <name>, speed = <playback speed> }: what it should play.

local AssetServer = require("bevy::asset::AssetServer")
local Time = require("bevy::time::Time")
local Quat = require("bevy::math::Quat")

-- How fast a clip's weight moves toward its target, per second: a fade takes 0.2 s.
local FADE = 5

-- Its model, once its fields are filled in: spawned on add, replaced when the scene changes.
app:add_systems(First, {
    Query[{
        changed = { "animation" },
        optional = { "Children" },
    }],
    Query[{ with = { "animation/model" } }],
    Res[AssetServer],
    Commands,
}, function(changed, models, asset_server, commands)
    for _, e in ipairs(changed:iter()) do
        local a = e:get("animation")
        if a.model and a.scene and a.offset then
            local scene = a.model .. a.scene
            local children = e:get("Children") or {}
            local model = models:iter_many(children)[1]
            if model == nil or model:get("animation/model").scene ~= scene then
                if model then commands:entity(model:id()):despawn() end
                commands:spawn({
                    ["animation/model"] = { scene = scene },
                    SceneRoot = asset_server:load(scene),
                    Transform = { translation = a.offset },
                    ["animation/clip"] = { clips = {}, speed = 1, ["repeat"] = true },
                }):insert({ ChildOf = e:id() })
            end
        end
    end
end):in_set("animation/model")

-- Faster than this across, in metres per second, a character with a `run` clip runs.
local RUN_FROM = 4

--- Wrapped into [0, 360).
local function around(deg)
    return (deg % 360 + 360) % 360
end

--- The two directions of a set nearest `angle`, and how far from the first toward the second it
--- lies (0 to 1), going round: a set's angles need no order, count or spacing.
local function nearest(set, angle)
    local sorted = {}
    for _, d in ipairs(set) do sorted[#sorted + 1] = { angle = around(d.angle or 0), clip = d.clip } end
    table.sort(sorted, function(x, y) return x.angle < y.angle end)
    if #sorted == 1 then return sorted[1], sorted[1], 0 end
    local a = around(angle)
    for i, cur in ipairs(sorted) do
        local nxt = sorted[i % #sorted + 1]
        local span = (nxt.angle - cur.angle) % 360
        if span == 0 then span = 360 end
        local rel = (a - cur.angle) % 360
        if rel < span then return cur, nxt, rel / span end
    end
    return sorted[1], sorted[1], 0
end

--- Each clip file the character's states name, at its target weight for what it plays (its state,
--- or idle for a state with none) and 0 for the rest. A state that is a set of directions splits
--- its weight over the two nearest `angle`, as far as the angle lies between them.
local function targets(a, state, angle)
    local out = {}
    for _, entry in pairs(a.clips) do
        if type(entry) == "table" then
            for _, d in ipairs(entry) do out[a.model .. d.clip] = 0 end
        else
            out[a.model .. entry] = 0
        end
    end
    local entry = a.clips[state] or a.clips.idle
    if type(entry) == "table" and #entry > 0 then
        local first, second, t = nearest(entry, angle or 0)
        out[a.model .. first.clip] = out[a.model .. first.clip] + (1 - t)
        out[a.model .. second.clip] = out[a.model .. second.clip] + t
    elseif type(entry) == "string" then
        out[a.model .. entry] = 1
    end
    return out
end

-- What it is doing, and the clips its model plays for it. The motion is its body's velocity while
-- that says it moves (physics moves a body in fixed steps, so most frames show no movement), else how
-- it moved since last frame: a frame holding two steps reads a kinematic copy as still, as its
-- Transform moved only before the first. Motion is followed every frame, so it polls. Each clip's
-- weight on the model moves toward its target, so a new state fades in as the old one fades out; a
-- model at its targets is not written.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "animation", "Transform" },
        optional = { "animation/motion", "animation/playing", "animation/action", "Velocity3d", "Children" },
    }],
    Query[{ with = { "animation/model" }, optional = { "animation/clip" } }],
    Commands,
}, function(time, characters, models, commands)
    local dt = time:delta_secs()
    if dt <= 0 then return end
    for _, e in ipairs(characters:iter()) do
        local a = e:get("animation")
        if a.model == nil then goto next_character end
        local transform = e:get("Transform")
        local at = transform.translation
        local last = (e:get("animation/motion") or {}).at
        local from = last or at
        local vx, vy, vz = (at.x - from.x) / dt, (at.y - from.y) / dt, (at.z - from.z) / dt
        local body = e:get("Velocity3d")
        if body and body.linvel and (body.linvel.x ~= 0 or body.linvel.y ~= 0 or body.linvel.z ~= 0) then
            vx, vy, vz = body.linvel.x, body.linvel.y, body.linvel.z
        end
        local horizontal = math.sqrt(vx * vx + vz * vz)
        local state, speed = "idle", 1
        local action = e:get("animation/action")
        if action and action.state then
            state, speed = action.state, action.speed or 1
        elseif vy < -1 then
            state = "fall"
        elseif vy > 1 then
            state = "jump"
        elseif horizontal > 0.1 then
            state, speed = "walk", horizontal / a.walk_speed
            if a.clips.run ~= nil and horizontal > RUN_FROM then
                state, speed = "run", horizontal / a.run_speed
            end
            speed = math.max(0.3, math.min(2, speed))
        end
        -- Where it moves, in degrees clockwise from where it faces, seen from above: its front is +Z.
        local angle = nil
        if horizontal > 0.1 then
            local front = Quat.mul_vec3(transform.rotation, { x = 0, y = 0, z = 1 })
            angle = math.deg(math.atan2(front.x, front.z) - math.atan2(vx, vz))
        end

        local playing = e:get("animation/playing") or {}
        if last == nil or last.x ~= at.x or last.y ~= at.y or last.z ~= at.z then
            commands:entity(e:id()):patch({ ["animation/motion"] = { at = { x = at.x, y = at.y, z = at.z } } })
        end
        if playing.state ~= state or playing.speed ~= speed then
            commands:entity(e:id()):patch({ ["animation/playing"] = { state = state, speed = speed } })
        end

        local model = models:iter_many(e:get("Children") or {})[1]
        if model and a.clips then
            local current = model:get("animation/clip") or {}
            local now = current.clips or {}
            -- nothing playing yet: the first state starts at its weights, with nothing to fade from
            local fresh = true
            for _, w in pairs(now) do fresh = fresh and w == 0 end
            local step = dt * FADE
            local want, changed = targets(a, state, angle), false
            local clips = {}
            for clip, target in pairs(want) do
                local w = now[clip] or 0
                if fresh then
                    w = target
                elseif w < target then
                    w = math.min(target, w + step)
                elseif w > target then
                    w = math.max(target, w - step)
                end
                clips[clip] = w
                changed = changed or w ~= now[clip]
            end
            for clip in pairs(now) do changed = changed or want[clip] == nil end
            if changed or current.speed ~= speed then
                commands:entity(model:id()):insert({
                    ["animation/clip"] = { clips = clips, speed = speed, ["repeat"] = true },
                })
            end
        end
        ::next_character::
    end
end):in_set("animation/state")
