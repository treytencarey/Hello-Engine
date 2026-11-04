-- The client half: each character's sprite and the frame it shows, built per entity.
--
-- A character's sprite is a child (`animation/sprite/image`) holding the sheet's handle, which
-- Bevy refills in place when the file changes or arrives, so a file change rebuilds nothing
-- here. The clip comes from the character's motion on this client. The frame is worked out from
-- when the clip started, so a frame's passing writes only the rect it changes.
--
-- animation/sprite/image = { path, scale, z }: the child holding the sprite, and what it was
--     built from.
-- animation/sprite/playing = { state, facing, started = <seconds, on this world's clock> }:
--     what it should play.
-- animation/sprite/motion = { at = { x, y } }: where the character was last frame.

local AssetServer = require("bevy::asset::AssetServer")
local Time = require("bevy::time::Time")

-- Its sprite, once it names a sheet: spawned on add, replaced when what it is built from changes.
app:add_systems(First, {
    Query[{
        changed = { "animation/sprite" },
        optional = { "Children" },
    }],
    Query[{ with = { "animation/sprite/image" } }],
    Res[AssetServer],
    Commands,
}, function(changed, sprites, asset_server, commands)
    for _, e in ipairs(changed:iter()) do
        local a = e:get("animation/sprite")
        if a.image then
            local children = e:get("Children") or {}
            local sprite = sprites:iter_many(children)[1]
            local built = sprite and sprite:get("animation/sprite/image")
            if not built or built.path ~= a.image or built.scale ~= a.scale or built.z ~= a.z then
                if sprite then commands:entity(sprite:id()):despawn() end
                commands:spawn({
                    ["animation/sprite/image"] = { path = a.image, scale = a.scale, z = a.z },
                    Sprite = { image = asset_server:load(a.image) },
                    Transform = {
                        translation = { x = 0, y = 0, z = a.z },
                        scale = { x = a.scale, y = a.scale, z = 1 },
                    },
                    ChildOf = e:id(),
                })
            end
        end
    end
end):in_set("animation/sprite/image")

-- What it is doing: from its body's velocity while that says it moves (physics moves a body in
-- fixed steps, so most frames show no movement), else from how it moved since last frame. A frame
-- holding two steps reads a kinematic copy as still, as its Transform moved only before the first.
-- Motion is followed every frame. A character that stops keeps facing the way it last went.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "animation/sprite", "Transform" },
        optional = { "animation/sprite/motion", "animation/sprite/playing", "Velocity2d" },
    }],
    Commands,
}, function(time, characters, commands)
    local dt = time:delta_secs()
    for _, e in ipairs(characters:iter()) do
        local playing = e:get("animation/sprite/playing") or {}
        local at = e:get("Transform").translation
        local last = (e:get("animation/sprite/motion") or {}).at or at
        local vx, vy = (at.x - last.x) / dt, (at.y - last.y) / dt
        if last.x ~= at.x or last.y ~= at.y or not e:has("animation/sprite/motion") then
            commands:entity(e:id()):patch({ ["animation/sprite/motion"] = { at = { x = at.x, y = at.y } } })
        end
        local body = e:get("Velocity2d")
        if body and (body.linvel.x ~= 0 or body.linvel.y ~= 0) then
            vx, vy = body.linvel.x, body.linvel.y
        end
        local facing = playing.facing or "down"
        local moving = math.sqrt(vx * vx + vy * vy) > 0.1
        if moving then
            if math.abs(vx) > math.abs(vy) then
                facing = vx > 0 and "right" or "left"
            else
                facing = vy < 0 and "down" or "up"
            end
        end
        local state = (moving and "walk_" or "idle_") .. facing
        if playing.state ~= state then
            commands:entity(e:id()):patch({
                ["animation/sprite/playing"] = { state = state, facing = facing, started = time:elapsed_secs() },
            })
        end
    end
end):in_set("animation/sprite/state"):run_if({ Res[Time] }, function(time)
    return time:delta_secs() > 0
end)

-- The frame it shows, which time alone moves on. A new clip starts from its first frame, and a
-- state with no clip of its own plays `idle`.
app:add_systems(Update, {
    Res[Time],
    Query[{
        with = { "animation/sprite", "animation/sprite/playing" },
        optional = { "Children" },
    }],
    Query[{ with = { "animation/sprite/image", Mut["Sprite"] } }],
}, function(time, characters, sprites)
    local now = time:elapsed_secs()
    for _, e in ipairs(characters:iter()) do
        local a = e:get("animation/sprite")
        local playing = e:get("animation/sprite/playing")
        local clip = a.clips[playing.state] or a.clips.idle
        local sprite = sprites:iter_many_mut(e:get("Children") or {})[1]
        if sprite and clip then
            local shown = math.floor((now - playing.started) * clip.fps * a.speed) % #clip.frames
            local frame = clip.frames[shown + 1]
            local x = (frame % a.columns) * a.tile_size.x
            local y = math.floor(frame / a.columns) * a.tile_size.y
            local rect = sprite:get("Sprite").rect
            if not rect or rect.min.x ~= x or rect.min.y ~= y
                or rect.max.x ~= x + a.tile_size.x or rect.max.y ~= y + a.tile_size.y then
                sprite:patch({
                    Sprite = {
                        rect = {
                            min = { x = x, y = y },
                            max = { x = x + a.tile_size.x, y = y + a.tile_size.y },
                        },
                    },
                })
            end
        end
    end
end):in_set("animation/sprite/frame"):after("animation/sprite/state")
