-- test_world_head.lua: where a player's checkout stands against the commit the world states,
-- told by git/world/head's client half. Root answers each comparison with real git, in a
-- repository this suite makes: the tree of a client world root starts. The world's stated commit
-- is a stand-in the suite moves.
--
-- R0  no request while the world's tree is not a checkout the player edits
-- R1  ...and one, once it is: the world two commits ahead of the checkout is "2 commits behind"
-- R2  the world on the checkout's own commit: nothing to say
-- R3  the world on a commit the checkout doesn't have: "not fetched"
-- R4  the checkout ahead of the world: nothing to say, and no pull asked with no upstream
-- R5  the player pushed past the world: the world is asked to pull, naming its commit, and the
--     player is told how many commits
-- R6  commits the player has not pushed ask no pull
-- R7  one request per stated commit: each is closed once answered

require("modules/core/init.lua")
require("modules/core/world/creator.lua")
require("modules/core/mod_registry/init.lua")

local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitWorldHeadSuite")
local T = suite.assert_test

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local ROOT = "test_fixtures/zz-world-head"
local CK = "assets/" .. ROOT
local BARE = "assets/test_fixtures/zz-world-head-bare.git"
local OUT = "assets/test_fixtures/zz-world-head.out"
local UNKNOWN = "0123456789abcdef0123456789abcdef01234567"

local seen = helpers.shared_state("GitWorldHeadSeen", { notices = 0, asks = 0, pulls = 0, open = 0 })

local BOOT = [==[
local seen = require("modules/core/test_helpers.lua").shared_state("GitWorldHeadSeen", {})

app:add_systems(Startup, { Commands }, function(commands)
    seen.booted = true
    commands:spawn({ ["core/library"] = { ref = "zz:launch", root = "", order = 2 }, ["core/net/sync"] = false })
    commands:spawn({ ["git/world/head"] = {}, ["zz/head/standin"] = {} })
end)

app:add_systems(Update, {
    Query[{ with = { Mut["git/world/head"], "zz/head/standin" } }],
    Query[{ with = { "core/library", "zz/head/checkout" } }],
    Commands,
}, function(heads, checkouts, commands)
    for _, head in ipairs(heads:iter_mut()) do
        if seen.want ~= nil and head:get("git/world/head").sha ~= seen.want then
            head:get_mut("git/world/head").sha = seen.want
        end
    end
    if seen.edits and checkouts:is_empty() then
        commands:spawn({ ["core/library"] = { ref = "zz:world-head", root = "@ROOT", order = 0, edits = true },
            ["zz/head/checkout"] = {}, ["core/net/sync"] = false })
    end
end)

app:add_systems(Update, {
    Query[{ added = { "git/merge/notice" } }],
    Query[{ added = { "git/world/head/pull" } }],
    Query[{ added = { "vault/git/head" } }],
    Query[{ with = { "vault/git/head/reply" } }],
    Query[{ with = { "vault/git/head", "Request" } }],
}, function(notices, pulls, asks, replies, open)
    for _, e in ipairs(notices:iter()) do
        seen.notices = seen.notices + 1
        seen["notice_" .. seen.notices] = e:get("git/merge/notice").text
    end
    for _, e in ipairs(pulls:iter()) do
        seen.pulls = seen.pulls + 1
        seen.pull_sha = e:get("git/world/head/pull").sha
    end
    for _ in ipairs(asks:iter()) do seen.asks = seen.asks + 1 end
    for _, e in ipairs(replies:iter()) do
        local r = e:get("vault/git/head/reply")
        seen["reply_" .. tostring(r.sha)] = tostring(r.relation) .. " count=" .. tostring(r.count)
            .. " pushed=" .. tostring(r.pushed) .. " message=" .. tostring(r.message)
    end
    seen.open = #open:iter()
end):before("git/world/head/compare")
]==]

local st = { phase = "clean", t = 0 }
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

local function finish()
    pcall(os.remove_dir, CK)
    pcall(os.remove_dir, BARE)
    pcall(os.remove, OUT)
    suite.finish("GIT_WORLD_HEAD")
    st.phase = "done"
end

local function notice(n) return tostring(seen["notice_" .. n]) end

-- Runs the queued git commands one at a time, a process per frame at most, so no frame waits.
-- Answers true while any is left.
local function busy()
    if pid ~= nil then
        if process_alive(pid) then return true end
        local code = process_exit_code(pid)
        kill_process(pid)
        pid = nil
        local step = table.remove(queue, 1)
        if code ~= 0 then
            T("R_git_" .. tostring(step.args[#step.args]), false, read_file_bytes(OUT) or "")
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

local function after(fn) queue[#queue].after = fn end

app:add_systems(Update, { World, Commands }, function(world, commands)
    if st.phase == "done" then return end
    st.t = st.t + (world:delta_time() or 0)
    if busy() then return end

    if st.phase == "clean" then
        pcall(os.remove_dir, CK)
        pcall(os.remove_dir, BARE)
        queue[#queue + 1] = { args = { "init", "-q", "-b", "main", CK } }
        for n = 1, 3 do
            write(CK .. "/assets/f.txt", "v" .. n .. "\n")
            git("add", "-A")
            git("commit", "-q", "--no-verify", "-m", "c" .. n)
        end
        git("rev-parse", "HEAD~2", "HEAD~1", "HEAD")
        after(function(text) st.c1, st.c2, st.c3 = text:match("^(%x+)%s+(%x+)%s+(%x+)") end)
        git("checkout", "-q", "--detach", "HEAD~2")
        st.phase = "boot"
        return
    end

    if st.phase == "boot" then
        write_file_bytes(CK .. "/assets/modules/world/boot/client/init.lua", (BOOT:gsub("@ROOT", ROOT)))
        seen.want = st.c3
        commands:spawn({ ["core/world/instance"] = {
            mode = "client", scope_key = "zz:world-head", asset_root = ROOT, headless = true,
        }, ["core/net/sync"] = false })
        st.phase, st.t = "no_checkout", 0
        return
    end

    if st.phase == "no_checkout" then
        if not seen.booted and st.t < 30 then return end
        if st.booted_at == nil then st.booted_at = st.t end
        if st.t < st.booted_at + 3 then return end
        T("R0_the_world_booted", seen.booted == true, "the world never ran its boot")
        T("R0_no_request_while_the_tree_is_not_a_checkout_the_player_edits", seen.asks == 0 and seen.notices == 0,
            string.format("%d request(s), %d notice(s)", seen.asks, seen.notices))
        seen.edits = true
        st.phase, st.t = "behind", 0
        return
    end

    if st.phase == "behind" then
        if seen.notices < 1 and st.t < 30 then return end
        T("R1_the_world_two_commits_ahead_is_two_behind", notice(1):find("2 commits behind", 1, true) ~= nil,
            notice(1) .. " | reply " .. tostring(seen["reply_" .. st.c3]))
        seen.want = st.c1
        st.phase, st.t = "same", 0
        return
    end

    if st.phase == "same" then
        if seen["reply_" .. st.c1] == nil and st.t < 30 then return end
        if st.t < 1 then return end
        T("R2_the_world_on_your_commit_says_nothing",
            tostring(seen["reply_" .. st.c1]):find("^same") ~= nil and seen.notices == 1 and seen.pulls == 0,
            string.format("reply %s, %d notice(s), %d pull(s)", tostring(seen["reply_" .. st.c1]), seen.notices, seen.pulls))
        seen.want = UNKNOWN
        st.phase, st.t = "unknown", 0
        return
    end

    if st.phase == "unknown" then
        if seen.notices < 2 and st.t < 30 then return end
        T("R3_a_commit_you_have_not_fetched_says_so", notice(2):find("not fetched", 1, true) ~= nil,
            notice(2) .. " | reply " .. tostring(seen["reply_" .. UNKNOWN]))
        git("checkout", "-q", "--detach", "main")
        st.phase, st.t = "ahead", 0
        return
    end

    if st.phase == "ahead" then
        if seen.want ~= st.c1 then
            seen.want = st.c1
            -- The checkout moved under the same stated commit: state another, then this one.
            seen["reply_" .. st.c1] = nil
            return
        end
        if seen["reply_" .. st.c1] == nil and st.t < 30 then return end
        if st.t < 1 then return end
        T("R4_you_ahead_of_the_world_says_nothing_and_asks_no_pull",
            tostring(seen["reply_" .. st.c1]):find("^ahead") ~= nil and seen.notices == 2 and seen.pulls == 0,
            string.format("reply %s, %d notice(s), %d pull(s)", tostring(seen["reply_" .. st.c1]), seen.notices, seen.pulls))
        queue[#queue + 1] = { args = { "init", "-q", "--bare", BARE } }
        git("checkout", "-q", "main")
        git("remote", "add", "origin", "../zz-world-head-bare.git")
        git("push", "-q", "-u", "origin", "main")
        st.phase, st.t = "pushed", 0
        return
    end

    if st.phase == "pushed" then
        if seen.want ~= UNKNOWN and seen.pushed_asked == nil then
            seen.want, seen.pushed_asked = UNKNOWN, true
            return
        end
        if seen.notices < 3 then
            -- The unknown commit's notice first, then the world back on c1.
            if st.t > 30 then
                T("R5_answered", false, "no notice")
                return finish()
            end
            return
        end
        if seen.want ~= st.c1 then seen.want = st.c1 end
        if seen.notices < 4 and st.t < 30 then return end
        T("R5_a_player_who_pushed_past_the_world_asks_it_to_pull",
            seen.pulls == 1 and seen.pull_sha == st.c1 and notice(4):find("2 commits behind what you pushed", 1, true) ~= nil,
            string.format("%d pull(s) naming %s, notice %s | reply %s", seen.pulls, tostring(seen.pull_sha), notice(4),
                tostring(seen["reply_" .. st.c1])))
        write(CK .. "/assets/f.txt", "v4\n")
        git("commit", "-q", "--no-verify", "-am", "c4")
        st.phase, st.t = "unpushed", 0
        return
    end

    if st.phase == "unpushed" then
        if seen.want ~= st.c3 then
            seen.want = st.c3
            return
        end
        if seen["reply_" .. st.c3] == nil and st.t < 30 then return end
        if st.t < 1 then return end
        T("R6_commits_you_have_not_pushed_ask_no_pull",
            tostring(seen["reply_" .. st.c3]):find("^ahead") ~= nil and seen.pulls == 1 and seen.notices == 4,
            string.format("reply %s, %d pull(s), %d notice(s)", tostring(seen["reply_" .. st.c3]), seen.pulls, seen.notices))
        T("R7_each_request_is_closed_once_answered", seen.open == 0,
            string.format("%d request(s) open after %d asked", seen.open, seen.asks))
        finish()
    end
end)
