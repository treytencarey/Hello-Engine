-- A character's skeletal animation: its model, and the clip it plays for what it is doing.
-- The server states the model (synced); each client draws it. What it plays (walking, running,
-- jumping, falling, standing, and the way it moves against where it faces) is worked out once, on
-- the side that moves the character, the one holding its Transform's authority: the owning client
-- for a player, the server for a character no client owns. It crosses as `animation/playing`, as
-- the Transform does, and every other copy plays it. A mod that plays something on purpose (a
-- cast, an emote) writes `animation/action`, which wins while it is there and syncs as that mod
-- declares. Missing fields get defaults when it is added.
--
-- animation = {
--     model = <path prefix of the model's files; absent, nothing is drawn or played>,
--     scene = <suffix of the file and label of its scene>,
--     clips = { idle = <suffix>, walk = <suffix>, jump = <suffix>, fall = <suffix>, run = <suffix>, ... },
--     walk_speed = <m/s at which the walk clip plays at its own speed>,
--     run_speed = <m/s at which the run clip plays at its own speed>,
--     offset = { x = <metres>, y = <metres>, z = <metres> },
-- }
--
-- animation/action = { state = <a clip's name>, speed = <playback speed> }: written by
-- another mod; while present it is played instead of the motion's state.
--
-- A state's clip may be a set of directions instead of one suffix:
-- { { angle = 0, clip = <suffix> }, { angle = 45, clip = <suffix> }, ... }, its angles in degrees
-- clockwise from forward, seen from above. The two nearest the angle between where the character
-- faces and where it moves play, each as near as the angle lies to it.
--
-- animation/motion = { at = { x, y, z } }: where the character was last frame, on the side that
-- moves it.
-- animation/playing = { state = <name>, speed = <playback speed>, angle = <degrees clockwise from
-- where it faces to where it moves; absent while it stands> }: what it plays, written by the side
-- that moves it, only when it changes.

local Time = require("bevy::time::Time")
local Quat = require("bevy::math::Quat")

-- Faster than this across, in metres per second, a character with a `run` clip runs.
local RUN_FROM = 4

--- Whether this side moves the character, from its Transform's sync: one never replicated is this
--- side's own; a client's authority means its owning client, one of this side's own nets; else the
--- server. `own` is this side's nets with `core/net/owns`.
local function moves_here(e, own, server)
    local sync = e:get("core/net/sync")
    if type(sync) ~= "table" then return true end
    local transform = sync.Transform
    if type(transform) == "table" and transform.authority == "client" then
        local owner = e:get("core/net/owner")
        return owner ~= nil and own:contains(owner)
    end
    return server
end

-- What it is doing. The motion is its body's velocity while that says it moves (physics moves a
-- body in fixed steps, so most frames show no movement), else how it moved since last frame: a
-- frame holding two steps reads a kinematic body as still, as its Transform moved only before the
-- first. Motion is followed every frame, so it polls.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "animation", "Transform" },
        optional = { "animation/motion", "animation/playing", "animation/action", "Velocity3d", "core/net/sync", "core/net/owner" },
    }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Query[{ with = { "core/world/net" } }],
    Commands,
}, function(time, characters, own, nets, commands)
    local dt = time:delta_secs()
    if dt <= 0 then return end
    local world_net = nets:iter()[1]
    local server = world_net ~= nil and world_net:get("core/world/net").mode == "server"
    for _, e in ipairs(characters:iter()) do
        local a = e:get("animation")
        if a.model == nil or not moves_here(e, own, server) then goto next_character end
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
        if last == nil or last.x ~= at.x or last.y ~= at.y or last.z ~= at.z then
            commands:entity(e:id()):patch({ ["animation/motion"] = { at = { x = at.x, y = at.y, z = at.z } } })
        end
        local playing = e:get("animation/playing") or {}
        if playing.state ~= state or playing.speed ~= speed or playing.angle ~= angle then
            -- set whole: an angle gone (standing) must not stay behind
            commands:entity(e:id()):insert({ ["animation/playing"] = { state = state, speed = speed, angle = angle } })
        end
        ::next_character::
    end
end):in_set("animation/state")

return {
    defaults = {
        animation = {
            scene = "-Idle.glb#Scene0",
            clips = {
                idle = "-Idle.glb#Animation0",
                walk = "-Walk.glb#Animation0",
                jump = "-Jump.glb#Animation0",
                fall = "-Jump.glb#Animation0",
            },
            walk_speed = 6,
            run_speed = 6,
            offset = { x = 0, y = -0.9, z = 0 },
        },
    },
}
