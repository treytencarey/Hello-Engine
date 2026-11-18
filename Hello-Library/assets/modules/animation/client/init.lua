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

-- What it is doing: from its body's velocity while that says it moves (physics moves a body in
-- fixed steps, so most frames show no movement), else from how it moved since last frame. A frame
-- holding two steps reads a kinematic copy as still, as its Transform moved only before the first.
-- Motion is followed every frame.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "animation", "Transform" },
        optional = { "animation/motion", "animation/playing", "animation/action", "Velocity3d" },
    }],
    Commands,
}, function(time, characters, commands)
    local dt = time:delta_secs()
    if dt <= 0 then return end
    for _, e in ipairs(characters:iter()) do
        local a = e:get("animation")
        if a.model == nil then goto next_character end
        local at = e:get("Transform").translation
        local last = (e:get("animation/motion") or {}).at
        local from = last or at
        local vx, vy, vz = (at.x - from.x) / dt, (at.y - from.y) / dt, (at.z - from.z) / dt
        local body = e:get("Velocity3d")
        if body and body.linvel and (body.linvel.x ~= 0 or body.linvel.y ~= 0 or body.linvel.z ~= 0) then
            vx, vy, vz = body.linvel.x, body.linvel.y, body.linvel.z
        end
        local state, speed = "idle", 1
        local action = e:get("animation/action")
        if action and action.state then
            state, speed = action.state, action.speed or 1
        elseif vy < -1 then
            state = "fall"
        elseif vy > 1 then
            state = "jump"
        else
            local horizontal = math.sqrt(vx * vx + vz * vz)
            if horizontal > 0.1 then
                state = "walk"
                speed = math.max(0.3, math.min(2, horizontal / a.walk_speed))
            end
        end
        local playing = e:get("animation/playing") or {}
        if last == nil or last.x ~= at.x or last.y ~= at.y or last.z ~= at.z then
            commands:entity(e:id()):patch({ ["animation/motion"] = { at = { x = at.x, y = at.y, z = at.z } } })
        end
        if playing.state ~= state or playing.speed ~= speed then
            commands:entity(e:id()):patch({ ["animation/playing"] = { state = state, speed = speed } })
        end
        ::next_character::
    end
end):in_set("animation/state")

--- Each clip the character has, at 1 for what it plays (its state's, or idle's) and 0 for the rest.
local function targets(a, playing)
    local out = {}
    for _, suffix in pairs(a.clips) do out[a.model .. suffix] = 0 end
    local suffix = a.clips[playing.state] or a.clips.idle
    if suffix then out[a.model .. suffix] = 1 end
    return out
end

-- The clips on its model: each weight moves toward its target, so a new state fades in as the
-- old one fades out. It polls while a weight moves; a model at its targets is not written.
app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "animation", "animation/playing" }, optional = { "Children" } }],
    Query[{ with = { "animation/model" }, optional = { "animation/clip" } }],
    Commands,
}, function(time, characters, models, commands)
    local step = time:delta_secs() * FADE
    for _, e in ipairs(characters:iter()) do
        local a = e:get("animation")
        local playing = e:get("animation/playing")
        local model = models:iter_many(e:get("Children") or {})[1]
        if model and a.model and a.clips then
            local current = model:get("animation/clip") or {}
            local now = current.clips or {}
            -- nothing playing yet: the first state starts at its weight, with nothing to fade from
            local fresh = true
            for _, w in pairs(now) do fresh = fresh and w == 0 end
            local want, changed = targets(a, playing), false
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
            if changed or current.speed ~= playing.speed then
                commands:entity(model:id()):insert({
                    ["animation/clip"] = { clips = clips, speed = playing.speed or 1, ["repeat"] = true },
                })
            end
        end
    end
end):in_set("animation/play"):after("animation/state")
