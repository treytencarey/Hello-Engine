-- test_cross_vm.lua: a git answer reaches the world that asked. Root answers in its own VM, and
-- the reply crosses into the client world root started on a repository this suite makes. A
-- reply's fields are plain data, and absent when they don't apply.
--
-- X1  a reply with no count or pushed ("same") arrives, with neither field
-- X2  a reply with a count ("behind") arrives, with it
-- X3  a later reply carries no count from the earlier one
-- X4  a reply is used on its own edge, under a world's head; one under no world's head is not

require("modules/core/init.lua")
require("modules/core/world/creator.lua")
require("modules/core/mod_registry/init.lua")

local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitCrossVmSuite")
local T = suite.assert_test

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local ROOT = "test_fixtures/zz-git-cross-vm"
local CK = "assets/" .. ROOT
local OUT = "assets/test_fixtures/zz-git-cross-vm.out"

local seen = helpers.shared_state("GitCrossVmSeen", { notices = 0 })

local BOOT = [==[
local seen = require("modules/core/test_helpers.lua").shared_state("GitCrossVmSeen", {})

local early_spawned, head_spawned = false, false

-- The stand-in has no commit yet, so it asks nothing, and git/world/head loads with it.
app:add_systems(Startup, { Commands }, function(commands)
    seen.booted = true
    commands:spawn({ ["core/library"] = { ref = "zz:launch", root = "", order = 2 }, ["core/net/sync"] = false })
    commands:spawn({ ["git/world/head"] = {}, ["zz/cross/standin"] = {} })
end)

app:add_systems(Update, {
    Query[{ with = { "zz/cross/early" } }],
    Query[{ with = { Mut["git/world/head"], "zz/cross/standin" } }],
    Query[{ with = { "core/library", "zz/cross/checkout" } }],
    Commands,
}, function(early, heads, checkouts, commands)
    if seen.early_spawn and not early_spawned then
        early_spawned = true
        local parent = commands:spawn({ ["zz/cross/early"] = {} }):id()
        commands:spawn({
            ["vault/git/head"] = {},
            ["vault/git"] = { sha = "@EARLY" },
            ["vault/git/head/reply"] = { sha = "@EARLY", relation = "behind", count = 3 },
            ChildOf = parent,
        })
    end
    if seen.early_head and not head_spawned then
        head_spawned = true
        local parent = commands:spawn({ ["zz/cross/early"] = {}, ["git/world/head"] = { sha = "@EARLY" } }):id()
        commands:spawn({
            ["vault/git/head"] = {},
            ["vault/git"] = { sha = "@EARLY" },
            ["vault/git/head/reply"] = { sha = "@EARLY", relation = "behind", count = 4 },
            ChildOf = parent,
        })
    end
    if seen.early_done then
        for _, e in ipairs(early:iter()) do
            commands:entity(e:id()):despawn()
        end
    end
    for _, head in ipairs(heads:iter_mut()) do
        if seen.want ~= nil and head:get("git/world/head").sha ~= seen.want then
            head:get_mut("git/world/head").sha = seen.want
        end
    end
    if seen.edits and checkouts:is_empty() then
        commands:spawn({ ["core/library"] = { ref = "zz:git-cross-vm", root = "@ROOT", order = 0, edits = true },
            ["zz/cross/checkout"] = {}, ["core/net/sync"] = false })
    end
end)

app:add_systems(Update, {
    Query[{ added = { "git/merge/notice" } }],
    Query[{ with = { "vault/git/head/reply", "Request" } }],
}, function(notices, replies)
    for _, e in ipairs(notices:iter()) do
        seen.notices = seen.notices + 1
        seen["notice_" .. seen.notices] = e:get("git/merge/notice").text
    end
    for _, e in ipairs(replies:iter()) do
        local r = e:get("vault/git/head/reply")
        seen["reply_" .. tostring(r.sha)] = string.format("%s count:%s pushed:%s",
            tostring(r.relation), type(r.count) .. "=" .. tostring(r.count), type(r.pushed))
    end
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

local function after(fn) queue[#queue].after = fn end

local function finish()
    pcall(os.remove_dir, CK)
    pcall(os.remove, OUT)
    suite.finish("GIT_CROSS_VM")
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
            T("X_git_" .. tostring(step.args[#step.args]), false, read_file_bytes(OUT) or "")
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

app:add_systems(Update, { World, Commands }, function(world, commands)
    if st.phase == "done" then return end
    st.t = st.t + (world:delta_time() or 0)
    if busy() then return end

    if st.phase == "clean" then
        pcall(os.remove_dir, CK)
        queue[#queue + 1] = { args = { "init", "-q", "-b", "main", CK } }
        for n = 1, 3 do
            write(CK .. "/assets/f.txt", "v" .. n .. "\n")
            git("add", "-A")
            git("commit", "-q", "--no-verify", "-m", "c" .. n)
        end
        git("rev-parse", "HEAD~2", "HEAD")
        after(function(text) st.c1, st.c3 = text:match("^(%x+)%s+(%x+)") end)
        git("checkout", "-q", "--detach", "HEAD~2")
        st.phase = "boot"
        return
    end

    if st.phase == "boot" then
        write_file_bytes(CK .. "/assets/modules/world/boot/client/init.lua",
            (BOOT:gsub("@ROOT", ROOT):gsub("@EARLY", st.c3)))
        commands:spawn({ ["core/world/instance"] = {
            mode = "client", scope_key = "zz:git-cross-vm", asset_root = ROOT, headless = true,
        }, ["core/net/sync"] = false })
        st.phase, st.t = "early", 0
        return
    end

    if st.phase == "early" then
        if not seen.booted and st.t < 30 then return end
        if st.t < 1.5 then return end
        seen.early_spawn = true
        st.phase, st.t = "early_seen", 0
        return
    end

    if st.phase == "early_seen" then
        if st.t < 1.5 then return end
        T("X4_a_reply_under_no_world_head_is_not_used", seen.notices == 0,
            string.format("%d notice(s): %s", seen.notices, tostring(seen.notice_1)))
        seen.early_head = true
        st.phase, st.t = "late", 0
        return
    end

    if st.phase == "late" then
        if seen.notices < 1 and st.t < 5 then return end
        T("X4_a_reply_under_a_world_head_is_used_on_its_edge",
            seen.notices == 1 and tostring(seen.notice_1):find("4 commits behind", 1, true) ~= nil,
            string.format("%d notice(s): %s", seen.notices, tostring(seen.notice_1)))
        seen.early_done = true
        st.phase, st.t = "cleared", 0
        return
    end

    if st.phase == "cleared" then
        if st.t < 0.5 then return end
        seen.want = st.c1
        seen.edits = true
        st.phase, st.t = "same", 0
        return
    end

    if st.phase == "same" then
        local r = seen["reply_" .. st.c1]
        if r == nil and st.t < 30 then return end
        T("X1_a_reply_with_no_count_or_pushed_arrives_with_neither", r == "same count:nil=nil pushed:nil", tostring(r))
        seen["reply_" .. st.c1] = nil
        seen.want = st.c3
        st.phase, st.t = "behind", 0
        return
    end

    if st.phase == "behind" then
        local r = seen["reply_" .. st.c3]
        if r == nil and st.t < 30 then return end
        T("X2_a_reply_with_a_count_arrives_with_it", r == "behind count:number=2 pushed:nil", tostring(r))
        seen.want = st.c1
        st.phase, st.t = "again", 0
        return
    end

    if st.phase == "again" then
        local r = seen["reply_" .. st.c1]
        if r == nil and st.t < 30 then return end
        T("X3_a_later_reply_carries_no_count_from_the_earlier", r == "same count:nil=nil pushed:nil", tostring(r))
        finish()
    end
end)
