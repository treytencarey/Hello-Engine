-- Whether a client is in VR. A client states it for its own player, as only it can see its
-- headset: `vr/active` exists while poses arrive, and the server and other clients receive it.
--
-- vr = {
--     timeout = <seconds without a pose before it counts as off>,
-- }
--
-- vr/active = {}
--
-- vr/tracking = {
--     at = <when the last pose arrived, seconds since the world started>,
-- }

return {
    defaults = {
        vr = {
            timeout = 2,
        },
    },
}
