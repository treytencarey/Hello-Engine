-- test_world_head_pull.lua: git/world/head's server half, in a server world root starts on a
-- repository this suite makes. Root reads the world's commit with real git. A player's ask to
-- pull arrives as the transport delivers a client-stated spawn, `core/net/predict { client_id,
-- requested }`. Root's pull is not built yet: this suite, at root, answers it in the shape it
-- expects, `vault/git/pull/reply { status, sha, message }`, `sha` the commit the pull left the
-- tree on.
--
-- Q0  the world states the commit its tree is on
-- Q1  an ask about a commit the world has left asks root for nothing
-- Q2  an ask about the world's commit asks root to pull, naming that commit
-- Q3  the ask itself is not kept
-- Q4  a second ask while that pull is under way asks nothing more
-- Q5  the pull's reply moves the stated commit
-- Q6  the pull's request is closed once answered

require("modules/core/init.lua")
require("modules/core/world/creator.lua")
require("modules/core/mod_registry/init.lua")

local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitWorldHeadPullSuite")
local T = suite.assert_test

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local ROOT = "test_fixtures/zz-world-head-pull"
local CK = "assets/" .. ROOT
local OUT = "assets/test_fixtures/zz-world-head-pull.out"
local LEFT = "0123456789abcdef0123456789abcdef01234567"

local seen = helpers.shared_state("GitWorldHeadPullSeen", { asked = 0, open = 0, asks_left = 0 })

local BOOT = [==[
local seen = require("modules/core/test_helpers.lua").shared_state("GitWorldHeadPullSeen", {})

local spawned = 0

app:add_systems(Startup, { Commands }, function(commands)
    seen.booted = true
    commands:spawn({ ["git/world/head"] = {} })
end)

app:add_systems(Update, {
    Query[{ with = { "git/world/head" } }],
    Query[{ with = { "core/net/predict" } }],
    Query[{ with = { "vault/git/pull", "Request" } }],
    Commands,
}, function(heads, predicts, pulls, commands)
    local head = heads:iter()[1]
    seen.stated = head and head:get("git/world/head").sha
    local left = 0
    for _, p in ipairs(predicts:iter()) do
        local requested = p:get("core/net/predict").requested
        if requested and requested["git/world/head/pull"] then left = left + 1 end
    end
    seen.asks_left = left
    seen.open = #pulls:iter()
    while spawned < seen.asked do
        spawned = spawned + 1
        commands:spawn({ ["core/net/predict"] = {
            client_id = 7, requested = { ["git/world/head/pull"] = { sha = seen["ask_" .. spawned] } },
        }, ["core/net/sync"] = false })
    end
end)
]==]

local st = { phase = "clean", t = 0, pulls = {} }
local queue, pid = {}, nil

local function git(...)
    local args = {
        "-C", CK, "-c", "user.name=zz", "-c", "user.email=zz@zz.invalid",
        "-c", "commit.gpgsign=false", "-c", "core.autocrlf=false",
    }
    for _, a in ipairs({ ... }) do args[#args + 1] = a end
    queue[#queue + 1] = { args = args }
end

local function write(path, text)
    queue[#queue + 1] = { write = { path, text } }
end

local function after(fn) queue[#queue].after = fn end

local function finish()
    pcall(os.remove_dir, CK)
    pcall(os.remove, OUT)
    suite.finish("GIT_WORLD_HEAD_PULL")
    st.phase = "done"
end

-- Runs the queued git commands one at a time, so no frame waits on one. Answers true while any
-- is left.
local function busy()
    if pid ~= nil then
        if process_alive(pid) then return true end
        local code = process_exit_code(pid)
        kill_process(pid)
        pid = nil
        local step = table.remove(queue, 1)
        if code ~= 0 then
            T("Q_git_" .. tostring(step.args[#step.args]), false, read_file_bytes(OUT) or "")
        end
        if step.after then step.after(read_file_bytes(OUT) or "") end
    end
    while queue[1] and queue[1].write do
        local w = table.remove(queue, 1).write
        write_file_bytes(w[1], w[2])
    end
    if queue[1] == nil then return false end
    pid = spawn_process("git", queue[1].args, { output = OUT })
    return true
end

local function ask(sha)
    seen.asked = seen.asked + 1
    seen["ask_" .. seen.asked] = sha
end

-- Root's side of a pull: every request that reaches root, as it arrives.
app:add_systems(Update, {
    Query[{ added = { "vault/git/pull" }, with = { "RequestFrom", "vault/git" } }],
}, function(pulls)
    for _, e in ipairs(pulls:iter()) do
        st.pulls[#st.pulls + 1] = { id = e:id(), sha = e:get("vault/git").sha, from = e:get("RequestFrom").world_id }
    end
end)

app:add_systems(Update, { World, Commands }, function(world, commands)
    if st.phase == "done" then return end
    st.t = st.t + (world:delta_time() or 0)
    if busy() then return end

    if st.phase == "clean" then
        pcall(os.remove_dir, CK)
        queue[#queue + 1] = { args = { "init", "-q", "-b", "main", CK } }
        write(CK .. "/assets/f.txt", "v1\n")
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m", "c1")
        git("rev-parse", "HEAD")
        after(function(text) st.c1 = text:match("^(%x+)") end)
        st.phase = "boot"
        return
    end

    if st.phase == "boot" then
        write_file_bytes(CK .. "/assets/modules/world/boot/server/init.lua", BOOT)
        commands:spawn({ ["core/world/instance"] = {
            mode = "server", scope_key = "zz:world-head-pull", asset_root = ROOT,
        }, ["core/net/sync"] = false })
        st.phase, st.t = "stated", 0
        return
    end

    if st.phase == "stated" then
        if seen.stated ~= st.c1 and st.t < 30 then return end
        T("Q0_the_world_states_its_commit", seen.stated == st.c1,
            string.format("stated %s, the tree is on %s", tostring(seen.stated), tostring(st.c1)))
        if seen.stated ~= st.c1 then return finish() end
        ask(LEFT)
        st.phase, st.t = "left", 0
        return
    end

    if st.phase == "left" then
        if st.t < 2 then return end
        T("Q1_an_ask_about_a_commit_the_world_left_asks_nothing", #st.pulls == 0 and seen.asks_left == 0,
            string.format("%d pull request(s) at root, %d ask(s) left", #st.pulls, seen.asks_left))
        ask(st.c1)
        st.phase, st.t = "asked", 0
        return
    end

    if st.phase == "asked" then
        if #st.pulls < 1 and st.t < 15 then return end
        local p = st.pulls[1] or {}
        T("Q2_an_ask_about_the_worlds_commit_asks_root_to_pull_naming_it", #st.pulls == 1 and p.sha == st.c1 and p.from ~= 0,
            string.format("%d pull request(s), naming %s from VM %s", #st.pulls, tostring(p.sha), tostring(p.from)))
        if #st.pulls < 1 then return finish() end
        ask(st.c1)
        st.phase, st.t = "again", 0
        return
    end

    if st.phase == "again" then
        if st.t < 2 then return end
        T("Q3_the_ask_is_not_kept", seen.asks_left == 0, string.format("%d ask(s) left", seen.asks_left))
        T("Q4_a_second_ask_while_a_pull_is_under_way_asks_nothing", #st.pulls == 1,
            string.format("%d pull request(s) at root", #st.pulls))
        -- The pull: the tree moves to a newer commit, and root says so.
        write(CK .. "/assets/f.txt", "v2\n")
        git("commit", "-q", "--no-verify", "-am", "c2")
        git("rev-parse", "HEAD")
        after(function(text) st.c2 = text:match("^(%x+)") end)
        st.phase, st.t = "reply", 0
        return
    end

    if st.phase == "reply" then
        commands:entity(st.pulls[1].id):insert({ ["vault/git/pull/reply"] = { status = "updated", sha = st.c2 } })
        st.phase, st.t = "moved", 0
        return
    end

    if st.phase == "moved" then
        if (seen.stated ~= st.c2 or seen.open ~= 0) and st.t < 15 then return end
        T("Q5_the_pulls_reply_moves_the_stated_commit", seen.stated == st.c2,
            string.format("stated %s, the pull left the tree on %s", tostring(seen.stated), tostring(st.c2)))
        T("Q6_the_pull_request_is_closed_once_answered", seen.open == 0,
            string.format("%d pull request(s) open", seen.open))
        finish()
    end
end)
