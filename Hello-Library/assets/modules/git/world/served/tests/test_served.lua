-- --host
-- git/world/served on a client: its carrier carries git/status only while this world's own content
-- library is the player's checkout (`edits`, which core sets from the home fact). No home fact is
-- published here, so git/status is the fact under test, not what it does.
--
-- S1  the checkout was already this world's when the carrier arrived: the first run catches up
-- S2  the checkout moving away takes git/status off
-- S3  ...and coming back puts it back
-- S4  another scope's library being edited is not this world's checkout
-- S5  a reload of the mod keeps git/status on, added once
-- S6  git/world/served taken off an entity that stays takes git/status with it
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitWorldServedSuite")
local T = suite.assert_test

local SCOPE = "github:zzserved/proj:main"
local OTHER = "github:zzserved/proj:other"
local SOURCE = "assets/modules/git/world/served/client/init.lua"

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
    commands:spawn({
        ["core/world/status"] = { scope_key = SCOPE, mode = "client", status = "ready" },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
    -- This world's own content library, already the player's checkout before the mod exists.
    commands:spawn({
        ["core/library"] = { ref = SCOPE, root = "test_fixtures/zz_served_none", order = 5, edits = true },
        ["zz/served/own"] = {},
        ["core/net/sync"] = false,
    })
end)

local added = 0
app:add_systems(First, { Query[{ added = { "git/status" } }] }, function(rows)
    added = added + #rows:iter()
end):in_set("zz/served_count")

local function carrier(world)
    return world:query({ with = { "zz/served/carrier" }, optional = { "git/status" } })[1]
end

local function own(world)
    return world:query({ with = { "core/library", "zz/served/own" } })[1]
end

local phase, clock = "carrier", 0

app:add_systems(Update, { World, Commands }, function(world, commands)
    clock = clock + (world:delta_time() or 0)
    local c = carrier(world)
    local watching = c ~= nil and c:has("git/status")
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function edits(on)
        local lib = own(world)
        local declared = lib:get("core/library")
        declared.edits = on
        commands:entity(lib:id()):insert({ ["core/library"] = declared })
    end

    if phase == "carrier" and clock > 0.2 then
        -- The boot's base landing on the world entity, after the library was declared.
        commands:spawn({ ["git/world/served"] = {}, ["zz/served/carrier"] = {}, ["core/net/sync"] = false })
        step("s1")

    elseif phase == "s1" and (watching or clock > 5) then
        T("S1_already_the_checkout_on_arrival_is_caught_up", watching,
            "no git/status on the carrier after it arrived in a world whose tree is the checkout")
        edits(false)
        step("s2")

    elseif phase == "s2" and (not watching or clock > 5) then
        T("S2_the_checkout_moving_away_takes_it_off", not watching,
            "git/status must go when this world's tree stops being the checkout")
        edits(true)
        step("s3")

    elseif phase == "s3" and (watching or clock > 5) then
        T("S3_the_checkout_coming_back_puts_it_back", watching,
            "git/status must come back with the checkout")
        edits(false)
        commands:spawn({
            ["core/library"] = { ref = OTHER, root = "test_fixtures/zz_served_other", order = 6, edits = true },
            ["core/net/sync"] = false,
        })
        step("s4")

    elseif phase == "s4" and clock > 1 then
        T("S4_another_scopes_edited_library_is_not_this_worlds", not watching,
            "a library edited under another scope made this world watch")
        edits(true)
        step("s5 on")

    elseif phase == "s5 on" and (watching or clock > 5) and clock > 0.3 then
        added = 0
        write_file_bytes(SOURCE, read_file_bytes(SOURCE))
        step("s5 reload")

    elseif phase == "s5 reload" and clock > 2 then
        T("S5_a_reload_keeps_git_status_on_added_once", watching and added == 0,
            string.format("on=%s, added again %d time(s)", tostring(watching), added))
        commands:entity(c:id()):remove("git/world/served")
        step("s6")

    elseif phase == "s6" and (not watching or clock > 5) then
        T("S6_taking_the_carrier_off_takes_git_status", not watching,
            "git/status stayed on an entity that is no longer git/world/served's")
        phase = "done"
        suite.finish("GIT_WORLD_SERVED")
    end

    if phase ~= "done" and clock > 15 then
        T("S0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 15 s")
        phase = "done"
        suite.finish("GIT_WORLD_SERVED")
    end
end):in_set("zz/served_suite")
