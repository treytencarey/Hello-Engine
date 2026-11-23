-- --host
-- A timer handed in with an entity runs from the frame it lands. Core's peer inbound gives a player
-- coming home what was handed, its crossing timer among it, in `First`; a portal reads the timer's
-- component in `Update`. Set there, as core sets it, the component is on before `Update` of that
-- frame, or the player standing in the door it left by is handed straight back.
--
--   H1 a timer set in core's peer inbound has its component in that frame's `Update`
--   H2 a mirror runs no timer of its own: one whose source's timer was about to end, handed back
--      with a fresh timer of that name, cools for the fresh timer, not the end of the old one
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
require("modules/cooldown/shared/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local suite = helpers.create_suite("CooldownHandedSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({ ["zz/cooldown_handed"] = {}, ["core/net/sync"] = false })
    -- A player away: this world's mirror of it, its source's timer about to end, as the source's
    -- updates write `cooldown` onto it.
    commands:spawn({
        ["zz/cooldown_kept"] = {},
        ["core/net/peer/mirror"] = { stable_id = "zz_kept", was_source = true },
        cooldown = { ["zz/cooldown_kept/cooling"] = { remaining = 1.5 } },
        ["core/net/sync"] = false,
    })
end)

local frame, handed_at, seen = 0, nil, nil
local clock, kept_at, kept_cool, kept_old = 0, nil, true, nil

-- As core's re-promotion sets what was handed: on the entity, directly, in its inbound set.
app:add_systems(First, { World }, function(world)
    frame = frame + 1
    clock = clock + (world:delta_time() or 0)
    if frame == 10 then
        local e = world:query({ with = { "zz/cooldown_handed" } })[1]
        world:get_entity(e:id()):set({ cooldown = { ["zz/cooldown_handed/cooling"] = { remaining = 3 } } })
        handed_at = frame
    end
    -- Handed back just before its source's timer would have ended: the mirror marker goes, and
    -- what was handed is set whole, a fresh timer of the same name among it.
    local k = world:query({ with = { "zz/cooldown_kept" }, optional = { "cooldown/left" } })[1]
    local old = k and (k:get("cooldown/left") or {})["zz/cooldown_kept/cooling"]
    -- With no copy running here, as when the mirror runs none, it is handed back after the old
    -- timer would have had under 0.3 s left.
    if kept_at == nil and k ~= nil and ((old ~= nil and old < 0.3) or (old == nil and clock > 1.3)) then
        local full = world:get_entity(k:id())
        full:remove("core/net/peer/mirror")
        full:set({ cooldown = { ["zz/cooldown_kept/cooling"] = { remaining = 3 } } })
        kept_at, kept_old = clock, old
    end
end):in_set("core/net/peer/server_inbound"):after("zz/cooldown_handed/bound")

-- Cooling for the fresh 3 s, so through the next 0.5 s, past where the old copy would have ended.
app:add_systems(Update, { World }, function(world)
    if kept_at == nil or kept_at < 0 then return end
    local k = world:query({ with = { "zz/cooldown_kept" }, optional = { "zz/cooldown_kept/cooling" } })[1]
    kept_cool = kept_cool and k:get("zz/cooldown_kept/cooling") ~= nil
    if clock - kept_at > 0.5 then
        suite.assert_test("H2_a_mirror_runs_no_timer_handed_back_it_cools_for_the_fresh_timer", kept_cool,
            "cooling through 0.5 s after: " .. tostring(kept_cool) .. ", the copy here had " .. tostring(kept_old) .. " s left")
        kept_at = -1
        suite.finish("CooldownHandedSuite")
    end
end)

-- Core's inbound runs after its own setup (`core/net/peer/server_bound`), so after every system
-- with no order of its own: so does this one.
app:add_systems(First, {}, function() end):in_set("zz/cooldown_handed/bound")

app:add_systems(Update, { World }, function(world)
    if handed_at == nil or seen ~= nil then return end
    local e = world:query({ with = { "zz/cooldown_handed" }, optional = { "zz/cooldown_handed/cooling" } })[1]
    seen = e:get("zz/cooldown_handed/cooling") ~= nil
    suite.assert_test("H1_a_timer_set_in_core_s_peer_inbound_has_its_component_in_that_frame_s_update", seen,
        "component in Update of the frame it was handed: " .. tostring(seen))
end)
