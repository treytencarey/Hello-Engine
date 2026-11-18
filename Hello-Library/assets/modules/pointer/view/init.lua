-- The desktop's ray source for `pointer`: from this client's own player's eye (`camera/3d/eye`), along
-- the view's centre while the cursor is hidden (game input), and through the cursor while it is
-- shown (`input/mode.show_cursor`). The hidden cursor keeps a place of its own, so it is not aimed
-- through. It has `pointer` as its base, as `vr/pointer` does for the VR controller.
--
-- pointer/view = {}: on this client's own player, added and removed by `player`'s client half, and
-- swapped for `vr/pointer` by `player/vr` while the player is in VR

local Quat = require("bevy::math::Quat")

-- The eye moves every frame the player looks, so it polls. In a world VM the camera draws into an
-- image the size of the window's physical pixels, so the cursor is read in those.
app:add_systems(Update, {
    Query[{ with = { "pointer/view" }, optional = { "Children", "input/mode" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Query[{ with = { "camera/3d/eye", "Camera", "GlobalTransform" } }],
    Query[{ with = { "Window" } }],
    Commands,
}, function(players, own, eyes, windows, commands)
    for _, n in ipairs(own:iter()) do
        for _, p in ipairs(players:iter_many(n:get("core/net/owns"))) do
            local eye = eyes:iter_many(p:get("Children") or {})[1]
            if eye ~= nil then
                local ray = nil
                if (p:get("input/mode") or {}).show_cursor == true then
                    local window = windows:iter()[1]
                    local cursor = window and window.Window:physical_cursor_position() or nil
                    -- It fails while the camera has no target size yet.
                    local ok, seen = pcall(function() return cursor ~= nil and eye.Camera:viewport_to_world(cursor) or nil end)
                    -- A `Dir3` may read back as its one field.
                    if ok and seen then ray = { origin = seen.origin, direction = seen.direction[1] or seen.direction } end
                end
                if ray == nil then
                    local t = eye.GlobalTransform:compute_transform()
                    ray = { origin = t.translation, direction = Quat.mul_vec3(t.rotation, { x = 0, y = 0, z = -1 }) }
                end
                commands:entity(p:id()):insert({ ["pointer/ray"] = ray })
            end
        end
    end
end):in_set("pointer/view"):before("pointer/cast")

-- What it wrote goes with it.
app:add_systems(First, {
    Query[{ removed = { "pointer/view" } }],
    Commands,
}, function(removed, commands)
    for _, e in ipairs(removed:iter()) do
        local player = commands:get_entity(e:id())
        if player ~= nil then player:try_remove("pointer/ray") end
    end
end):in_set("pointer/view/removed")

return {
    base = "pointer",
}
