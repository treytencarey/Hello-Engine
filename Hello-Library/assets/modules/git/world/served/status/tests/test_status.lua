-- test_status.lua: git/world/served/status in a client world root starts on a repository this suite
-- makes, with root answering each scan with real git. The world's boot puts git/world/served/status
-- on an entity of its own, and root shares a signed-in identity.
--
-- S1  an edited tracked file is a `write` edit and an untracked one a `create`, asset relative
-- S2  a second save of the edited file, still dirty: its `seq` moves, and the other's stays
-- S3  a revert: the edited file written back and the new one removed each move their `seq` once
--     more, the removed one `deleted`
-- S4  ...and the next scan drops both
-- S5  a path that leaves because HEAD moved (a commit) is dropped with no `seq` move
-- S6  each request is closed once answered, one open at a time

require("modules/core/init.lua")
require("modules/core/world/creator.lua")
require("modules/core/mod_registry/init.lua")

local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitStatusSuite")
local T = suite.assert_test

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/player/identity"] = { site_user_id = "zz-user" },
        WorldShared = {},
        ["core/net/sync"] = false,
    })
end)

local ROOT = "test_fixtures/zz-status"
local CK = "assets/" .. ROOT
local OUT = "assets/test_fixtures/zz-status.out"

local seen = helpers.shared_state("GitStatusSeen", { asks = 0, open = 0, max_open = 0, edits = "" })

local BOOT = [==[
local seen = require("modules/core/test_helpers.lua").shared_state("GitStatusSeen", {})

app:add_systems(Startup, { Commands }, function(commands)
    seen.booted = true
    -- the launch folder, where this library's mods are
    commands:spawn({ ["core/library"] = { ref = "zz:launch", root = "", order = 2 }, ["core/net/sync"] = false })
    commands:spawn({ ["git/world/served/status"] = {}, ["zz/status/carrier"] = {}, ["core/net/sync"] = false })
end)

local last = nil

app:add_systems(Update, {
    Query[{
        with = { "vault/git/status", "Request" },
        without = { "vault/git/status/reply" },
    }],
    Query[{ with = { "core/library/edit" } }],
}, function(open, edits)
    local first = open:iter()[1]
    -- one open at a time, so a request not seen open before is a new ask
    if first ~= nil and first:id() ~= last then
        seen.asks, last = seen.asks + 1, first:id()
    end
    seen.open = #open:iter()
    if seen.open > seen.max_open then seen.max_open = seen.open end
    local list = {}
    for _, e in ipairs(edits:iter()) do
        local d = e:get("core/library/edit")
        list[#list + 1] = string.format("%s=%s:%s", d.path, tostring(d.seq), d.deleted and "deleted" or "here")
    end
    table.sort(list)
    seen.edits = table.concat(list, ",")
end)
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
    pcall(os.remove, OUT)
    suite.finish("GIT_STATUS")
    st.phase = "done"
end

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
            T("S_git_" .. tostring(step.args[#step.args]), false, read_file_bytes(OUT) or "")
        end
    end
    while queue[1] and queue[1].write do
        local w = table.remove(queue, 1).write
        if w[2] == nil then os.remove(w[1]) else write_file_bytes(w[1], w[2]) end
    end
    if queue[1] == nil then return false end
    pid = spawn_process("git", queue[1].args, { output = OUT })
    return true
end

--- The world's edits as `path=seq:here|deleted`, sorted; `asks` how many requests it asked.
local function edits() return tostring(seen.edits) end

-- The edits once the world has asked `n` more requests than `from`: a scan asked after a change
-- on disk answers it, and the one after that has been read.
local function settled(from, n) return seen.asks >= from + n end

app:add_systems(Update, { World, Commands }, function(world, commands)
    if st.phase == "done" then return end
    st.t = st.t + (world:delta_time() or 0)
    if busy() then return end
    if edits():find("committed.txt=2", 1, true) then st.held = true end
    local function step(next_phase)
        st.phase, st.t, st.from = next_phase, 0, seen.asks
    end

    if st.phase == "clean" then
        pcall(os.remove_dir, CK)
        queue[#queue + 1] = { args = { "init", "-q", "-b", "main", CK } }
        write(CK .. "/assets/modules/world/boot/client/init.lua", BOOT)
        write(CK .. "/assets/committed.txt", "one\n")
        write(CK .. "/assets/edited.txt", "before\n")
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m", "first")
        write(CK .. "/assets/edited.txt", "after\n")
        write(CK .. "/assets/fresh.txt", "new\n")
        st.phase = "boot"
        return
    end

    if st.phase == "boot" then
        commands:spawn({ ["core/world/instance"] = {
            mode = "client", scope_key = "zz:status", asset_root = ROOT, headless = true,
        }, ["core/net/sync"] = false })
        step("s1")
        return
    end

    if st.phase == "s1" then
        if edits() ~= "edited.txt=1:here,fresh.txt=1:here" and st.t < 30 then return end
        T("S1_an_edit_is_a_write_and_a_new_file_a_create", edits() == "edited.txt=1:here,fresh.txt=1:here",
            "booted=" .. tostring(seen.booted) .. ", edits " .. edits())
        write(CK .. "/assets/edited.txt", "after, saved again\n")
        step("s2")
        return
    end

    if st.phase == "s2" then
        if edits() ~= "edited.txt=2:here,fresh.txt=1:here" and (not settled(st.from, 3) and st.t < 30) then return end
        T("S2_a_second_save_of_a_dirty_file_moves_its_seq", edits() == "edited.txt=2:here,fresh.txt=1:here",
            "edits " .. edits())
        write(CK .. "/assets/edited.txt", "before\n")
        write(CK .. "/assets/fresh.txt", nil)
        step("s3")
        return
    end

    if st.phase == "s3" then
        if edits() ~= "edited.txt=3:here,fresh.txt=2:deleted" and (not settled(st.from, 3) and st.t < 30) then return end
        T("S3_a_revert_moves_each_seq_once_more", edits() == "edited.txt=3:here,fresh.txt=2:deleted",
            "edits " .. edits())
        step("s4")
        return
    end

    if st.phase == "s4" then
        if edits() ~= "" and (not settled(st.from, 2) and st.t < 30) then return end
        T("S4_and_the_next_scan_drops_them", edits() == "", "edits " .. edits())
        write(CK .. "/assets/committed.txt", "two\n")
        step("s5 edit")
        return
    end

    if st.phase == "s5 edit" then
        if edits() ~= "committed.txt=1:here" and st.t < 30 then return end
        git("commit", "-q", "--no-verify", "-am", "second")
        step("s5")
        return
    end

    if st.phase == "s5" then
        if not settled(st.from, 3) and st.t < 30 then return end
        T("S5_a_path_leaving_because_head_moved_is_dropped_with_no_seq_move", edits() == "" and not st.held,
            "edits " .. edits() .. ", held=" .. tostring(st.held))
        T("S6_each_request_is_closed_once_answered", seen.max_open == 1 and seen.asks >= 8 and seen.open <= 1,
            string.format("%d asked, at most %d open, %d open now", seen.asks, seen.max_open, seen.open))
        finish()
    end
end)
