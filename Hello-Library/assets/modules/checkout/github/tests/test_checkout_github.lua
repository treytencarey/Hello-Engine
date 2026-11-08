-- test_checkout_github.lua: checkout/github asks root for a checkout and answers the Gateway on
-- the request. The suite stands in for root, answering each `vault/git/checkout` on the request
-- entity as root does. A checkout the suite asks comes from no world root started, so nothing
-- else answers it.
--
-- G1  each request asks root once, a child of the request, with the repo and ref
-- G2  ...and never the asked path
-- G3  ready answers root's folder, not the asked path, and closes the ask
-- G4  needs-deploy-key answers the key's public half as the detail, and closes the ask
-- G5  any other failure, or a refusal, answers failed with root's reason, and no detail
-- G6  an unanswered ask waits while the others are answered
-- G7  removing a request still waiting closes its ask
-- G8  removing an answered request removes its answer; others keep theirs
-- G9  asked again after the key is granted (a new request), it asks root afresh, and the old
--     needs-deploy-key comes back nowhere
-- G10 a reload of the mod asks nothing more for answered requests, keeps one ask for a waiting
--     one, and still answers it
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local MessageReader = require("bevy::prelude").MessageReader

local suite = helpers.create_suite("CheckoutGithubSuite")
local T = suite.assert_test

local MOD_FILE = "assets/modules/checkout/github/init.lua"
local KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5-zz"

app:add_systems(Startup, { Commands }, function(commands)
    commands:insert_resource("core/hot_reload/settings", { poll_interval = 0, debounce = 0 })
end)

local reloads = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        if tostring(event.path):find("checkout/github/init.lua", 1, true) then reloads = reloads + 1 end
    end
end):in_set("zz/checkout/reload_watch")

local function want(commands, name, repo, ref, path)
    commands:spawn({ ["checkout/github"] = { repo = repo, ref = ref, path = path }, ["zz/co"] = { name = name } })
end

local function carrier(world, name)
    for _, e in ipairs(world:query({ with = { "zz/co" }, optional = { "checkout/github", "checkout/answer" } })) do
        if e:get("zz/co").name == name then return e end
    end
    return nil
end

local function asks(world, name)
    local c, out = carrier(world, name), {}
    if c == nil then return out end
    for _, e in ipairs(world:query({
        with = { "vault/git/checkout", "Request", "ChildOf" },
        optional = { "vault/git", "vault/git/checkout/reply" },
    })) do
        if e:get("ChildOf") == c:id() then out[#out + 1] = e end
    end
    return out
end

local function answer(world, name)
    local c = carrier(world, name)
    return c and c:get("checkout/answer")
end

local function reply(world, commands, name, fields)
    commands:entity(asks(world, name)[1]:id()):insert({ ["vault/git/checkout/reply"] = fields })
end

local original
local phase, clock = "start", 0
local seen = {}

app:add_systems(Update, { World, Commands }, function(world, commands)
    if phase == "done" then return end
    clock = clock + (world:delta_time() or 0)
    local function step(next_phase) phase, clock = next_phase, 0 end
    local function finish()
        phase = "done"
        if original ~= nil then write_file_bytes(MOD_FILE, original) end
        suite.finish("CHECKOUT_GITHUB")
    end

    if phase == "start" and clock > 0.2 then
        want(commands, "done", "zz-owner/done", "main", "zz/asked/elsewhere")
        want(commands, "key", "zz-owner/private", "main")
        want(commands, "fail", "zz-owner/missing", "feature/x")
        want(commands, "refused", "zz-owner/refused", "main")
        want(commands, "wait", "zz-owner/slow", "main")
        want(commands, "cancel", "zz-owner/cancel", "main")
        step("asked")

    elseif phase == "asked" then
        local names = { "done", "key", "fail", "refused", "wait", "cancel" }
        local all = true
        for _, name in ipairs(names) do all = all and #asks(world, name) == 1 end
        if not all and clock < 5 then return end
        local why = {}
        for _, name in ipairs(names) do
            local list = asks(world, name)
            local asked = list[1] and list[1]:get("vault/git")
            local c = carrier(world, name):get("checkout/github")
            if #list ~= 1 or asked == nil or asked.repo ~= c.repo or asked.ref ~= c.ref then
                why[#why + 1] = string.format("%s: %d asks, repo=%s ref=%s", name, #list,
                    tostring(asked and asked.repo), tostring(asked and asked.ref))
            end
        end
        T("G1_each_request_asks_root_once_as_its_child", #why == 0, table.concat(why, "; "))
        local done = asks(world, "done")[1]
        local asked = done and done:get("vault/git")
        T("G2_the_asked_path_never_reaches_root", asked ~= nil and asked.path == nil,
            "vault/git.path=" .. tostring(asked and asked.path))
        reply(world, commands, "done",
            { status = "ready", path = "worktrees/zz-owner/done/main", sha = "0123456789abcdef0123456789abcdef01234567" })
        reply(world, commands, "key", { status = "failed", reason = "needs-deploy-key", key = KEY })
        reply(world, commands, "fail", { status = "failed", reason = "ref-not-found" })
        reply(world, commands, "refused", { status = "refused", reason = "zz refused" })
        step("answered")

    elseif phase == "answered" then
        local ready = answer(world, "done") and answer(world, "key") and answer(world, "fail") and answer(world, "refused")
        if not ready and clock < 5 then return end
        local d, k, f, r = answer(world, "done"), answer(world, "key"), answer(world, "fail"), answer(world, "refused")
        T("G3_ready_answers_roots_folder_and_closes_the_ask",
            d ~= nil and d.status == "ready" and d.path == "worktrees/zz-owner/done/main" and d.reason == nil
                and #asks(world, "done") == 0,
            string.format("status=%s path=%s asks=%d", tostring(d and d.status), tostring(d and d.path),
                #asks(world, "done")))
        T("G4_needs_deploy_key_answers_the_public_key_as_detail",
            k ~= nil and k.status == "failed" and k.reason == "needs-deploy-key" and k.detail == KEY
                and #asks(world, "key") == 0,
            string.format("status=%s reason=%s detail=%s asks=%d", tostring(k and k.status),
                tostring(k and k.reason), tostring(k and k.detail), #asks(world, "key")))
        T("G5_a_failure_or_refusal_answers_failed_with_roots_reason",
            f ~= nil and f.status == "failed" and f.reason == "ref-not-found" and f.detail == nil and f.path == nil
                and #asks(world, "fail") == 0 and r ~= nil and r.status == "failed" and r.reason == "zz refused",
            string.format("status=%s reason=%s detail=%s refused=%s/%s", tostring(f and f.status),
                tostring(f and f.reason), tostring(f and f.detail), tostring(r and r.status), tostring(r and r.reason)))
        T("G6_an_unanswered_ask_waits", #asks(world, "wait") == 1 and answer(world, "wait") == nil,
            string.format("asks=%d answer=%s", #asks(world, "wait"), tostring(answer(world, "wait"))))
        seen.cancel_ask = asks(world, "cancel")[1]:id()
        commands:entity(carrier(world, "cancel"):id()):remove("checkout/github")
        commands:entity(carrier(world, "key"):id()):remove("checkout/github")
        step("removed")

    elseif phase == "removed" then
        local gone = world:get_entity(seen.cancel_ask) == nil and answer(world, "key") == nil
        if not gone and clock < 5 then return end
        T("G7_removing_a_waiting_request_closes_its_ask",
            world:get_entity(seen.cancel_ask) == nil and #asks(world, "cancel") == 0 and answer(world, "cancel") == nil,
            string.format("ask alive=%s", tostring(world:get_entity(seen.cancel_ask) ~= nil)))
        local d, f = answer(world, "done"), answer(world, "fail")
        T("G8_removing_an_answered_request_removes_its_answer_and_only_its",
            answer(world, "key") == nil and d ~= nil and d.status == "ready" and f ~= nil and f.status == "failed",
            string.format("key=%s done=%s fail=%s", tostring(answer(world, "key") and answer(world, "key").reason),
                tostring(d and d.status), tostring(f and f.status)))
        want(commands, "regrant", "zz-owner/private", "main")
        step("regrant")

    elseif phase == "regrant" then
        if #asks(world, "regrant") == 0 and clock < 5 then return end
        local a = answer(world, "regrant")
        seen.regrant_fresh = #asks(world, "regrant") == 1 and a == nil and answer(world, "key") == nil
        seen.regrant_why = string.format("asks=%d answer=%s old=%s", #asks(world, "regrant"),
            tostring(a and a.reason), tostring(answer(world, "key") and answer(world, "key").reason))
        reply(world, commands, "regrant", { status = "ready", path = "worktrees/zz-owner/private/main" })
        step("regranted")

    elseif phase == "regranted" then
        if answer(world, "regrant") == nil and clock < 5 then return end
        local a = answer(world, "regrant")
        T("G9_asked_again_it_asks_root_afresh_and_the_old_refusal_is_gone",
            seen.regrant_fresh and a ~= nil and a.status == "ready" and answer(world, "key") == nil,
            seen.regrant_why .. " then status=" .. tostring(a and a.status))
        seen.reloads = reloads
        original = read_file_bytes(MOD_FILE)
        write_file_bytes(MOD_FILE, original .. "\n-- zz 1\n")
        step("reloading")

    elseif phase == "reloading" then
        if reloads == seen.reloads and clock < 5 then return end
        seen.reloaded = reloads > seen.reloads
        step("reloaded")

    elseif phase == "reloaded" and clock > 1 then
        local why = string.format("reloaded=%s asks done=%d fail=%d regrant=%d wait=%d", tostring(seen.reloaded),
            #asks(world, "done"), #asks(world, "fail"), #asks(world, "regrant"), #asks(world, "wait"))
        seen.after_reload = seen.reloaded and #asks(world, "done") == 0 and #asks(world, "fail") == 0
            and #asks(world, "regrant") == 0 and #asks(world, "wait") == 1
            and answer(world, "done") ~= nil and answer(world, "regrant") ~= nil
        seen.reload_why = why
        if #asks(world, "wait") > 0 then
            reply(world, commands, "wait", { status = "ready", path = "worktrees/zz-owner/slow/main" })
        end
        step("reload answered")

    elseif phase == "reload answered" then
        local a = answer(world, "wait")
        if a == nil and clock < 5 then return end
        T("G10_a_reload_asks_nothing_more_and_still_answers",
            seen.after_reload and a ~= nil and a.status == "ready" and #asks(world, "wait") == 0,
            seen.reload_why .. " then wait=" .. tostring(a and a.status))
        finish()
    end

    if phase ~= "done" and clock > 15 then
        T("G0_reached_" .. phase, false, "stuck in phase '" .. phase .. "' for 15 s")
        finish()
    end
end):in_set("zz/checkout/suite")
