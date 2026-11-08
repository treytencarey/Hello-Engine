-- test_world_head_flow.lua: git/world/head from the world stating its commit to its pull, in the
-- shape it runs in: a server world on one checkout, and a player's client world, joined to it,
-- on a clone the player pushed from. Root starts both and compares with real git. Root's pull is
-- not built yet, so this suite, at root, does the pull and answers it in the shape it expects,
-- `vault/git/pull/reply { status, sha }`.
--
-- J1  the world states the commit its tree is on
-- J2  ...and its player gets it
-- J3  the player, whose upstream holds a commit the world lacks, is told so, and the world is
--     asked to pull, naming its commit
-- J4  the ask reaches root as a pull of the server world
-- J5  the pull moves the stated commit, on the server and for the player
-- J6  the player is asked again about the new commit: nothing more to say

require("modules/core/init.lua")
require("modules/core/world/creator.lua")
require("modules/core/mod_registry/init.lua")

local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitWorldHeadFlowSuite")
local T = suite.assert_test

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local SCOPE = "zz:world-head-flow"
local WROOT = "test_fixtures/zz-world-head-flow/world"
local CROOT = "test_fixtures/zz-world-head-flow/player"
local W = "assets/" .. WROOT
local C = "assets/" .. CROOT
local BARE = "assets/test_fixtures/zz-world-head-flow/remote.git"
local OUT = "assets/test_fixtures/zz-world-head-flow.out"

local seen = helpers.shared_state("GitWorldHeadFlowSeen", { notices = 0, pulls = 0 })

local SERVER_BOOT = [==[
local seen = require("modules/core/test_helpers.lua").shared_state("GitWorldHeadFlowSeen", {})

app:add_systems(Startup, { Commands }, function(commands)
    seen.server_booted = true
    commands:spawn({ ["git/world/head"] = {} })
end)

app:add_systems(Update, { Query[{ with = { "git/world/head" } }] }, function(heads)
    local head = heads:iter()[1]
    seen.server_stated = head and head:get("git/world/head").sha
end)
]==]

local CLIENT_BOOT = [==[
local seen = require("modules/core/test_helpers.lua").shared_state("GitWorldHeadFlowSeen", {})

app:add_systems(Startup, { Commands }, function(commands)
    seen.client_booted = true
    commands:spawn({ ["core/library"] = { ref = "zz:launch", root = "", order = 2 }, ["core/net/sync"] = false })
    commands:spawn({ ["core/library"] = { ref = "@SCOPE", root = "@CROOT", order = 0, edits = true },
        ["core/net/sync"] = false })
end)

app:add_systems(Update, {
    Query[{ added = { "git/merge/notice" } }],
    Query[{ added = { "git/world/head/pull" } }],
    Query[{ with = { "vault/git/head/reply" } }],
    Query[{ with = { "git/world/head" } }],
}, function(notices, pulls, replies, heads)
    for _, e in ipairs(notices:iter()) do
        seen.notices = seen.notices + 1
        seen["notice_" .. seen.notices] = e:get("git/merge/notice").text
    end
    for _, e in ipairs(pulls:iter()) do
        seen.pulls = seen.pulls + 1
        seen.pull_sha = e:get("git/world/head/pull").sha
    end
    for _, e in ipairs(replies:iter()) do
        local r = e:get("vault/git/head/reply")
        seen["reply_" .. tostring(r.sha)] = tostring(r.relation) .. " pushed=" .. tostring(r.pushed)
    end
    local head = heads:iter()[1]
    seen.client_stated = head and head:get("git/world/head").sha
end):before("git/world/head/compare")
]==]

local st = { phase = "clean", t = 0, pulls = {} }
local queue, pid = {}, nil

local function git(dir, ...)
    local args = {
        "-C", dir, "-c", "user.name=zz", "-c", "user.email=zz@zz.invalid",
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
    pcall(os.remove_dir, "assets/test_fixtures/zz-world-head-flow")
    pcall(os.remove, OUT)
    suite.finish("GIT_WORLD_HEAD_FLOW")
    st.phase = "done"
end

local function notice(n) return tostring(seen["notice_" .. n]) end

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
            T("J_git_" .. tostring(step.args[#step.args]), false, read_file_bytes(OUT) or "")
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
        pcall(os.remove_dir, "assets/test_fixtures/zz-world-head-flow")
        queue[#queue + 1] = { args = { "init", "-q", "--bare", "-b", "main", BARE } }
        queue[#queue + 1] = { args = { "init", "-q", "-b", "main", W } }
        for n = 1, 3 do
            write(W .. "/assets/f.txt", "v" .. n .. "\n")
            git(W, "add", "-A")
            git(W, "commit", "-q", "--no-verify", "-m", "c" .. n)
        end
        git(W, "rev-parse", "HEAD")
        after(function(text) st.c3 = text:match("^(%x+)") end)
        git(W, "remote", "add", "origin", "../remote.git")
        git(W, "push", "-q", "-u", "origin", "main")
        queue[#queue + 1] = { args = { "clone", "-q", BARE, C } }
        git(C, "remote", "set-url", "origin", "../remote.git")
        -- The player's commit, pushed while the world ran.
        write(C .. "/assets/f.txt", "v4\n")
        git(C, "commit", "-q", "--no-verify", "-am", "c4")
        git(C, "rev-parse", "HEAD")
        after(function(text) st.c4 = text:match("^(%x+)") end)
        git(C, "push", "-q", "origin", "main")
        st.phase = "boot"
        return
    end

    if st.phase == "boot" then
        write_file_bytes(W .. "/assets/modules/world/boot/server/init.lua", SERVER_BOOT)
        commands:spawn({ ["core/world/instance"] = {
            mode = "server", scope_key = SCOPE, asset_root = WROOT,
        }, ["core/net/sync"] = false })
        st.phase, st.t = "stated", 0
        return
    end

    if st.phase == "stated" then
        if seen.server_stated ~= st.c3 and st.t < 30 then return end
        T("J1_the_world_states_its_commit", seen.server_stated == st.c3,
            string.format("stated %s, the tree is on %s (booted %s)", tostring(seen.server_stated), tostring(st.c3),
                tostring(seen.server_booted)))
        if seen.server_stated ~= st.c3 then return finish() end
        local port
        for _, e in ipairs(world:query({ with = { "core/world/status" } })) do
            local row = e:get("core/world/status")
            if row.scope_key == SCOPE and row.mode == "server" then port = row.port end
        end
        write_file_bytes(C .. "/assets/modules/world/boot/client/init.lua", (CLIENT_BOOT:gsub("@CROOT", CROOT):gsub("@SCOPE", SCOPE)))
        commands:spawn({ ["core/world/instance"] = {
            mode = "client", scope_key = SCOPE, asset_root = CROOT, port = port, headless = true,
        }, ["core/net/sync"] = false })
        st.phase, st.t = "joined", 0
        return
    end

    if st.phase == "joined" then
        if seen.client_stated ~= st.c3 and st.t < 30 then return end
        T("J2_its_player_gets_it", seen.client_stated == st.c3,
            string.format("the player has %s (booted %s)", tostring(seen.client_stated), tostring(seen.client_booted)))
        if seen.client_stated ~= st.c3 then return finish() end
        st.phase, st.t = "told", 0
        return
    end

    if st.phase == "told" then
        if (seen.pulls < 1 or seen.notices < 1) and st.t < 15 then return end
        T("J3_a_player_who_pushed_past_the_world_is_told_and_asks_it_to_pull",
            seen.pulls == 1 and seen.pull_sha == st.c3 and notice(1):find("1 commit behind what you pushed", 1, true) ~= nil,
            string.format("%d pull ask(s) naming %s, notice %s | reply %s", seen.pulls, tostring(seen.pull_sha), notice(1),
                tostring(seen["reply_" .. st.c3])))
        st.phase, st.t = "reached", 0
        return
    end

    if st.phase == "reached" then
        if #st.pulls < 1 and st.t < 15 then return end
        local p = st.pulls[1] or {}
        local server_vm
        for _, e in ipairs(world:query({ with = { "core/world/status" } })) do
            local row = e:get("core/world/status")
            if row.scope_key == SCOPE and row.mode == "server" then server_vm = row.world_id end
        end
        T("J4_the_ask_reaches_root_as_a_pull_of_the_server_world",
            #st.pulls == 1 and p.sha == st.c3 and p.from == server_vm,
            string.format("%d pull request(s) at root, naming %s, from VM %s (the server world is VM %s)",
                #st.pulls, tostring(p.sha), tostring(p.from), tostring(server_vm)))
        if #st.pulls < 1 then return finish() end
        git(W, "pull", "-q", "--ff-only")
        st.phase, st.t = "pulled", 0
        return
    end

    if st.phase == "pulled" then
        commands:entity(st.pulls[1].id):insert({ ["vault/git/pull/reply"] = { status = "updated", sha = st.c4 } })
        st.phase, st.t = "moved", 0
        return
    end

    if st.phase == "moved" then
        if (seen.client_stated ~= st.c4 or seen["reply_" .. st.c4] == nil) and st.t < 15 then return end
        if st.t < 1 then return end
        T("J5_the_pull_moves_the_stated_commit", seen.server_stated == st.c4 and seen.client_stated == st.c4,
            string.format("the server states %s, the player has %s, the pull left the tree on %s",
                tostring(seen.server_stated), tostring(seen.client_stated), tostring(st.c4)))
        T("J6_the_player_is_asked_again_and_told_nothing_more",
            tostring(seen["reply_" .. st.c4]):find("^same pushed=nil") ~= nil and seen.notices == 1 and seen.pulls == 1,
            string.format("reply %s, %d notice(s), %d pull ask(s)", tostring(seen["reply_" .. st.c4]), seen.notices, seen.pulls))
        finish()
    end
end)
