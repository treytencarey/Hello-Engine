-- --host
-- `ai/nav` and `ai/perception` take their parts off everything when their last carrier leaves, and
-- what added them adds them again when the mod arrives: `ai/demo`'s regions and decoy,
-- `ai/nav/volumes/box`'s child, a player's target.
--
-- PR1 with an agent's carriers there, the parts are there
-- PR2 the last carrier gone, they're swept
-- PR3 a carrier back, each is there again, once
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local suite = require("modules/core/test_helpers.lua").create_suite("DemoPartsReturnSuite")
local Time = require("bevy::time::Time")

local st = { phase = "start", at = 0 }

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({ ["ai/demo"] = { count = 0, regions = true, decoy = true }, ["core/net/sync"] = false })
    commands:spawn({ ["ai/nav/volumes"] = { sample = false }, ["ai/nav/volumes/box"] = { hx = 2, hz = 2 }, ["core/net/sync"] = false })
    commands:spawn({ ["zz/player"] = {}, player = { client_id = 7, spawn_index = 1 }, ["core/net/sync"] = false })
end)

app:add_systems(Update, { World, Commands, Res[Time] }, function(world, commands, time)
    local now = time:elapsed_secs()
    local function count(with, without)
        return #world:query({ with = with, without = without })
    end
    local function arrive()
        st.agent = commands:spawn({ ["ai/nav"] = {}, ["ai/perception"] = {}, ["core/net/sync"] = false }):id()
    end
    if now < st.at then return end
    if st.phase == "start" then
        arrive()
        st.phase, st.at = "there", now + 1.5
    elseif st.phase == "there" then
        suite.assert_test("PR1_the_decoy_is_a_target", count({ "ai/demo/decoy", "ai/perception/target" }) == 1, "")
        suite.assert_test("PR1_the_player_is_a_target", count({ "zz/player", "ai/perception/target" }) == 1, "")
        st.regions = count({ "ai/demo/region", "ai/nav/region" })
        suite.assert_test("PR1_the_regions_are_there", st.regions > 0, tostring(st.regions))
        suite.assert_test("PR1_the_box_has_its_volume", count({ "ai/nav/volumes/box/volume", "ai/nav/volume" }) == 1, "")
        commands:entity(st.agent):despawn()
        st.phase, st.at = "gone", now + 0.5
    elseif st.phase == "gone" then
        suite.assert_test("PR2_the_targets_are_swept", count({ "ai/perception/target" }) == 0, tostring(count({ "ai/perception/target" })))
        suite.assert_test("PR2_the_regions_too", count({ "ai/demo/region", "ai/nav/region" }) == 0, "")
        suite.assert_test("PR2_and_the_volume", count({ "ai/nav/volume" }) == 0, tostring(count({ "ai/nav/volume" })))
        suite.assert_test("PR2_their_entities_stay", count({ "ai/demo/decoy" }) == 1 and count({ "ai/demo/region" }) == st.regions and count({ "ai/nav/volumes/box/volume" }) == 1, "")
        arrive()
        st.phase, st.at = "back", now + 1.5
    elseif st.phase == "back" then
        suite.assert_test("PR3_the_decoy_again", count({ "ai/demo/decoy", "ai/perception/target" }) == 1, "")
        suite.assert_test("PR3_the_player_again", count({ "zz/player", "ai/perception/target" }) == 1, "")
        suite.assert_test("PR3_the_regions_again", count({ "ai/demo/region", "ai/nav/region" }) == st.regions, tostring(count({ "ai/demo/region", "ai/nav/region" })))
        suite.assert_test("PR3_the_volume_again_on_the_one_child", count({ "ai/nav/volumes/box/volume", "ai/nav/volume" }) == 1 and count({ "ai/nav/volumes/box/volume" }) == 1, "")
        st.phase = "done"
        suite.finish("DemoPartsReturnSuite")
    end
end):in_set("zz/demo_parts_suite")
