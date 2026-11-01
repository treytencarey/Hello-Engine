-- --host
-- `abilities/fireball` on the server, headless, with physics: it fires straight and explodes
-- on what it hits.
--
--   F1 missing fields get defaults
--   F2 it registers itself in `abilities`
--   F3 a press fires a launch from 1 m above the player, with no gravity, that explodes on contact
--   F3b its caster is the player (`projectile/caster`), synced with the shot, and the player lists
--       it (`projectile/casts`)
--   F4 it flies straight into a wall and explodes there: an explosion of its blast radius,
--      and the ball is gone
--   F6 a cooldown started by something else (a debuff) fires nothing
--   F7 a press while it cools fires nothing
--   F5 taken off: its entry goes, and another ability's entry stays
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("AbilitiesFireballSuite")

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local function the_player(world)
    return world:query({ with = { "zz/player" }, optional = { "abilities/fireball", "abilities", "abilities/fireball/cooling" } })[1]
end

-- Every launch, counted as it is spawned: one that hits the wall is gone in 0.4 s.
local launches = 0
app:add_systems(Update, { World }, function(world)
    launches = launches + #world:query({ added = { "abilities/projectile" } })
end):in_set("zz/abilities_fireball_suite_launches")

local phase, clock = "spawn", 0
local launches_before = 0
local player_id

-- The suite's clock is the mods': Bevy's `Time`.
app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(next_phase) phase, clock = next_phase, 0 end
    local p = player_id and the_player(world)
    local function patch(t) world:get_entity(player_id):patch(t) end

    if phase == "spawn" then
        -- High above the ground, facing -Z, with a wall 10 m ahead.
        player_id = commands:spawn({
            ["zz/player"] = {},
            ["abilities/fireball"] = {},
            abilities = { zzother = { key = "KeyE" } },
            Transform = { translation = { x = 0, y = 100, z = 0 } },
            camera = { yaw = 0, pitch = 0 },
            ["core/net/owner"] = { client_id = 7 },
            ["core/net/sync"] = { Transform = { authority = "client" } },
        }):id()
        commands:spawn({
            ["zz/wall"] = {},
            Transform = { translation = { x = 0, y = 101, z = -10 } },
            RigidBody3d = "Fixed",
            Collider3d = { cuboid = { hx = 5, hy = 5, hz = 0.5 } },
            ["core/net/sync"] = false,
        })
        step("registered")

    elseif phase == "registered" then
        if clock < 0.5 then return end
        local f = p:get("abilities/fireball") or {}
        suite.assert_test("F1_missing_fields_get_defaults",
            f.key == "KeyQ" and f.cooldown == 1 and f.speed == 25 and f.radius == 0.25 and f.blast == 1.5, "")
        local a = (p:get("abilities") or {}).fireball or {}
        suite.assert_test("F2_it_registers_in_abilities", a.key == "KeyQ", "entry key=" .. tostring(a.key))
        patch({ ["input/game/abilities/fireball"] = { value = 1 } })
        step("fired")

    elseif phase == "fired" then
        local list = world:query({
            with = { "abilities/projectile" },
            optional = { "projectile", "ChildOf", "projectile/explode", "projectile/caster", "core/net/sync" },
        })
        if (#list == 0 or list[1]:get("projectile") == nil) and clock < 1 then return end
        local caster = list[1] and list[1]:get("projectile/caster") or {}
        local casts = world:query({ with = { "zz/player" }, optional = { "projectile/casts" } })[1]:get("projectile/casts") or {}
        -- The list comes once the `projectile` mod, which declares the relationship, has loaded.
        if #casts == 0 and caster.entity ~= nil and clock < 1 then return end
        suite.assert_test("F3b_its_caster_is_the_player",
            caster.entity == p:id() and #casts == 1 and casts[1] == list[1]:id()
                -- Clients get the caster with the shot's first spawn.
                and ((list[1]:get("core/net/sync") or {})["projectile/caster"] or {}).authority == "server",
            "caster=" .. tostring(caster.entity) .. " player=" .. tostring(p:id()) .. " casts=" .. #casts)
        local shot = list[1] and list[1]:get("projectile") or {}
        local explode = list[1] and list[1]:get("projectile/explode") or {}
        suite.assert_test("F3_a_press_fires_a_straight_launch_that_explodes_on_contact",
            #list == 1 and ((list[1]:get("abilities/projectile") or {}).at or {}).y == 101
                and shot.gravity == 0 and explode.radius == 1.5,
            "launches=" .. #list .. " gravity=" .. tostring(shot.gravity))
        step("hit")

    elseif phase == "hit" then
        local blasts = world:query({ with = { "explosion" } })
        -- The server's despawn of the ball lands a frame or so after its explosion shows.
        if (#blasts == 0 or #world:query({ with = { "abilities/projectile" } }) > 0) and clock < 3 then return end
        local x = blasts[1] and blasts[1]:get("explosion") or {}
        local at = x.at or {}
        -- The wall's face is at z = -9.5; the ball flew level at y = 101.
        suite.assert_test("F4_it_explodes_where_it_hits_the_wall",
            #blasts == 1 and x.radius == 1.5 and math.abs((at.z or 0) + 9.5) < 1.5 and math.abs((at.y or 0) - 101) < 0.2
                and #world:query({ with = { "abilities/projectile" } }) == 0,
            string.format("blasts=%d at=(%s,%s,%s) balls=%s", #blasts, tostring(at.x), tostring(at.y), tostring(at.z), (function()
                local out = {}
                for _, b in ipairs(world:query({ with = { "abilities/projectile" }, optional = { "collision_trigger", "Sensor3d", "RigidBody3d" } })) do
                    local w = world:get_entity(b:id()).GlobalTransform:compute_transform().translation
                    out[#out + 1] = string.format("(%.1f,%.1f,%.1f sensor=%s trig=%s)", w.x, w.y, w.z,
                        tostring(b:has("Sensor3d")), tostring(b:has("collision_trigger")))
                end
                return table.concat(out, " ")
            end)()))
        commands:entity(player_id):remove("input/game/abilities/fireball")
        step("cooled")

    elseif phase == "cooled" then
        -- Once the shot's own cooldown is over, a debuff starts it again with no press: a
        -- fresh `abilities/fireball/cooling`.
        if p:has("abilities/fireball/cooling") and clock < 3 then return end
        patch({ cooldown = { ["abilities/fireball/cooling"] = { remaining = 5 } } })
        launches_before = launches
        step("debuff")

    elseif phase == "debuff" then
        if clock < 0.4 then return end
        suite.assert_test("F6_a_cooldown_started_by_something_else_fires_nothing",
            p:has("abilities/fireball/cooling") and launches == launches_before,
            "launches since=" .. (launches - launches_before))
        launches_before = launches
        patch({ ["input/game/abilities/fireball"] = { value = 1 } })
        step("cooling_press")

    elseif phase == "cooling_press" then
        if clock < 0.4 then return end
        suite.assert_test("F7_a_press_while_it_cools_fires_nothing",
            launches == launches_before, "launches since=" .. (launches - launches_before))
        commands:entity(player_id):remove("abilities/fireball")
        step("removed")

    elseif phase == "removed" then
        if clock < 0.3 then return end
        local list = p:get("abilities") or {}
        suite.assert_test("F5_taken_off_its_entry_goes_and_others_stay",
            list.fireball == nil and (list.zzother or {}).key == "KeyE", "")
        suite.finish("ABILITIES_FIREBALL")
        phase = "done"
    end
end):in_set("zz/abilities_fireball_suite")
