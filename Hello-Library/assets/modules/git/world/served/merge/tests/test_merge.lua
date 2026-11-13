-- test_merge.lua: git/world/served/merge as core's resolver for a file both sides changed. The suite
-- stands in for core (its `core/library/merge` requests) and for root (each `vault/git/merge`
-- answer); `test_merge_flow` runs the whole path against root's real git.
--
-- M1  core's request asks root once to merge it, applying only a clean merge, with a record
-- M2  root's clean merge answers core "merged"
-- M3  a conflict answers "no", and so does a failure
-- M4  core's request gone: its record and root's open request go
-- M5  root's silence answers "no" after 30 s

require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Time = require("bevy::time::Time")

local suite = helpers.create_suite("GitMergeSuite")
local T = suite.assert_test

local carrier
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "client" }, ["core/net/sync"] = false })
    carrier = commands:spawn({ ["git/world/served/merge"] = {}, ["core/net/sync"] = false }):id()
end)

-- Root's stand-in: each request under the carrier answered as `answers[path]` says, once; root's
-- own refusal (the suite is root) is taken off first. A path with no answer waits.
local answers, asked = {}, {}
app:add_systems(First, {
    Query[{ with = { "vault/git/merge", "vault/git", "Request" }, optional = { "vault/git/merge/reply" } }],
    Commands,
}, function(requests, commands)
    for _, r in ipairs(requests:iter()) do
        local v = r:get("vault/git")
        if not asked[r:id()] then
            asked[r:id()] = true
            asked[v.path] = (asked[v.path] or 0) + 1
            asked["apply:" .. v.path] = v.apply
            asked["hash:" .. v.path] = v.hash
        end
        local reply = r:has("vault/git/merge/reply") and r:get("vault/git/merge/reply") or nil
        if reply and reply.status == "refused" then
            commands:entity(r:id()):remove("vault/git/merge/reply")
        elseif not reply and answers[v.path] then
            commands:entity(r:id()):insert({ ["vault/git/merge/reply"] = { status = answers[v.path], message = "zz" } })
            answers[v.path] = nil
        end
    end
end):in_set("zz/merge_root")

local function ask(commands, path, theirs)
    return commands:spawn({ ["core/library/merge"] = { path = path, mine = 1, theirs = theirs }, ["core/net/sync"] = false }):id()
end
local function reply(world, path)
    for _, e in ipairs(world:query({ with = { "core/library/merge" }, optional = { "core/library/merge/reply" } })) do
        if e:get("core/library/merge").path == path then
            return e:has("core/library/merge/reply") and e:get("core/library/merge/reply").status or false
        end
    end
end
local function records(world, path)
    local n = 0
    for _, e in ipairs(world:query({ with = { "git/world/served/merge/result" } })) do
        if e:get("git/world/served/merge/result").key == path then n = n + 1 end
    end
    return n
end
local function open(world, path)
    local n = 0
    for _, e in ipairs(world:query({ with = { "vault/git/merge", "vault/git" } })) do
        if e:get("vault/git").path == "assets/" .. path then n = n + 1 end
    end
    return n
end

local phase, clock, ids = "start", 0, {}
app:add_systems(Update, { World, Res[Time], Commands }, function(world, time, commands)
    clock = clock + time:delta_secs()
    local function step(p) phase, clock = p, 0 end
    local function finish()
        phase = "done"
        suite.finish("GIT_MERGE")
    end
    if phase == "done" then return end

    if phase == "start" and clock > 0.3 then
        ids.clean = ask(commands, "modules/clean.txt", 11)
        ids.clash = ask(commands, "modules/clash.txt", 12)
        ids.blob = ask(commands, "modules/blob.bin", 13)
        ids.gone = ask(commands, "modules/gone.txt", 14)
        ids.quiet = ask(commands, "modules/quiet.txt", 15)
        step("asked")
    elseif phase == "asked" and (asked["assets/modules/clean.txt"] or clock > 5) and clock > 1 then
        T("M1_a_request_asks_root_once_applying_only_a_clean_merge",
            asked["assets/modules/clean.txt"] == 1 and asked["apply:assets/modules/clean.txt"] == "clean"
                and asked["hash:assets/modules/clean.txt"] == 11 and records(world, "modules/clean.txt") == 1,
            string.format("asks=%s apply=%s records=%d", tostring(asked["assets/modules/clean.txt"]),
                tostring(asked["apply:assets/modules/clean.txt"]), records(world, "modules/clean.txt")))
        answers["assets/modules/clean.txt"] = "clean"
        answers["assets/modules/clash.txt"] = "conflict"
        answers["assets/modules/blob.bin"] = "failed"
        step("answered")
    elseif phase == "answered" and ((reply(world, "modules/clean.txt") and reply(world, "modules/clash.txt")
        and reply(world, "modules/blob.bin")) or clock > 5) then
        T("M2_a_clean_merge_answers_merged", reply(world, "modules/clean.txt") == "merged", tostring(reply(world, "modules/clean.txt")))
        T("M3_a_conflict_or_a_failure_answers_no", reply(world, "modules/clash.txt") == "no" and reply(world, "modules/blob.bin") == "no",
            tostring(reply(world, "modules/clash.txt")) .. "/" .. tostring(reply(world, "modules/blob.bin")))
        commands:entity(ids.gone):despawn()
        step("gone")
    elseif phase == "gone" and ((records(world, "modules/gone.txt") == 0 and open(world, "modules/gone.txt") == 0) or clock > 5) then
        T("M4_cores_request_gone_takes_the_record_and_roots_request", records(world, "modules/gone.txt") == 0
            and open(world, "modules/gone.txt") == 0, "")
        step("quiet")
    elseif phase == "quiet" and (reply(world, "modules/quiet.txt") or clock > 35) then
        T("M5_silence_answers_no_after_30_s", reply(world, "modules/quiet.txt") == "no", tostring(reply(world, "modules/quiet.txt")))
        finish()
    end
    if phase ~= "done" and phase ~= "quiet" and clock > 10 then
        T("M0_reached_" .. phase, false, "stuck")
        finish()
    end
end):in_set("zz/merge_flow")
