-- --host
-- A timer handed in with an entity runs from the frame it lands. Core's peer inbound gives a player
-- coming home what was handed, its crossing timer among it, in `First`; a portal reads the timer's
-- component in `Update`. Set there, as core sets it, the component is on before `Update` of that
-- frame, or the player standing in the door it left by is handed straight back.
--
--   H1 a timer set in core's peer inbound has its component in that frame's `Update`
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
require("modules/cooldown/shared/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local suite = helpers.create_suite("CooldownHandedSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({ ["zz/cooldown_handed"] = {}, ["core/net/sync"] = false })
end)

local frame, handed_at, seen = 0, nil, nil

-- As core's re-promotion sets what was handed: on the entity, directly, in its inbound set.
app:add_systems(First, { World }, function(world)
    frame = frame + 1
    if frame ~= 10 then return end
    local e = world:query({ with = { "zz/cooldown_handed" } })[1]
    world:get_entity(e:id()):set({ cooldown = { ["zz/cooldown_handed/cooling"] = { remaining = 3 } } })
    handed_at = frame
end):in_set("core/net/peer/server_inbound"):after("zz/cooldown_handed/bound")

-- Core's inbound runs after its own setup (`core/net/peer/server_bound`), so after every system
-- with no order of its own: so does this one.
app:add_systems(First, {}, function() end):in_set("zz/cooldown_handed/bound")

app:add_systems(Update, { World }, function(world)
    if handed_at == nil or seen ~= nil then return end
    local e = world:query({ with = { "zz/cooldown_handed" }, optional = { "zz/cooldown_handed/cooling" } })[1]
    seen = e:get("zz/cooldown_handed/cooling") ~= nil
    suite.assert_test("H1_a_timer_set_in_core_s_peer_inbound_has_its_component_in_that_frame_s_update", seen,
        "component in Update of the frame it was handed: " .. tostring(seen))
    suite.finish("CooldownHandedSuite")
end)
