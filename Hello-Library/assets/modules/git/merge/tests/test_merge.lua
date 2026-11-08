-- test_merge.lua: git/merge asks root to merge each held version into the player's checkout, and
-- root merges with real git in a repository this suite makes, the tree of a client world root
-- starts. Core's held state is a stand-in the suite moves, and so is the player's edit.
--
-- M1  edits that do not overlap: root writes both into the file, the record says clean, and the
--     path's edit names the held version (`on`)
-- M2  edits that overlap: git's markers in the file, a CONFLICT notice, and no `on`
-- M3  a binary both sides changed: a COULD NOT MERGE notice, the file untouched, and no `on`
-- M4  a binary only the player changed: theirs is not written, and the edit names the held version
-- M5  a binary only the world changed: root writes the held version
-- M6  one request per held version, each asking root to apply it, and each closed once answered
-- M7  a new held version is merged again, and a path no longer held loses its record
-- M8  an edit stated after the answer names the held version too
-- M9  a world root did not start is never answered: after the timeout its record says failed, a
--     notice says so, and the request is closed

require("modules/core/init.lua")
require("modules/core/world/creator.lua")
require("modules/core/mod_registry/init.lua")

local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitMergeSuite")
local T = suite.assert_test

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local ROOT = "test_fixtures/zz-merge"
local CK = "assets/" .. ROOT
local OUT = "assets/test_fixtures/zz-merge.out"
local H = { 3999999911, 3999999912, 3999999913, 3999999914, 3999999915, 3999999916, 3999999917 }

local BASE = "a\nb\nc\nd\ne\nf\ng\nh\ni\n"
local MINE = "A\nb\nc\nd\ne\nf\ng\nh\ni\n"
local THEIRS = "a\nb\nc\nd\ne\nf\ng\nh\nI\n"
local MERGED = "A\nb\nc\nd\ne\nf\ng\nh\nI\n"
local THEIRS2 = "a\nb\nc\nd\nE\nf\ng\nh\nI\n"
local MERGED2 = "A\nb\nc\nd\nE\nf\ng\nh\nI\n"

local seen = helpers.shared_state("GitMergeSeen", { notices = 0, asks = 0, open = 0, stage = 0 })

local BOOT = [==[
local seen = require("modules/core/test_helpers.lua").shared_state("GitMergeSeen", {})

app:add_systems(Startup, { Commands }, function(commands)
    seen.booted = true
    commands:spawn({ ["core/library"] = { ref = "zz:launch", root = "", order = 2 }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/library"] = { ref = "zz:merge", root = "@ROOT", order = 0, edits = true },
        ["core/library/upstream"] = { held = {} },
        ["zz/merge/checkout"] = { stage = 0 },
        ["core/net/sync"] = false,
    })
    for _, path in ipairs({ "clean.txt", "clash.txt", "blob.bin", "mine.bin" }) do
        commands:spawn({ ["core/library/edit"] = { path = path, seq = 1 }, ["core/net/sync"] = false })
    end
    commands:spawn({ ["git/merge"] = {} })
end)

app:add_systems(Update, {
    Query[{ with = { Mut["core/library/upstream"], Mut["zz/merge/checkout"] } }],
    Commands,
}, function(checkouts, commands)
    for _, lib in ipairs(checkouts:iter_mut()) do
        if lib:get("zz/merge/checkout").stage ~= seen.stage then
            lib:get_mut("zz/merge/checkout").stage = seen.stage
            if seen.stage == 1 then
                lib:get_mut("core/library/upstream").held = {
                    ["clean.txt"] = @H1, ["clash.txt"] = @H2, ["blob.bin"] = @H3, ["mine.bin"] = @H4,
                    ["theirs.bin"] = @H5,
                }
            elseif seen.stage == 2 then
                lib:get_mut("core/library/upstream").held = {
                    ["clean.txt"] = @H6, ["clash.txt"] = @H2, ["blob.bin"] = @H3, ["theirs.bin"] = @H5,
                }
            end
        end
    end
    if seen.late_edit and not seen.late_spawned then
        seen.late_spawned = true
        commands:spawn({ ["core/library/edit"] = { path = "theirs.bin", seq = 1 }, ["core/net/sync"] = false })
    end
end)

app:add_systems(Update, {
    Query[{ added = { "git/merge/notice" } }],
    Query[{ added = { "git/merge/job" }, with = { "vault/git/merge", "vault/git" } }],
    Query[{ with = { "git/merge/job" } }],
    Query[{ with = { "git/merge/result" } }],
    Query[{ with = { "core/library/edit" } }],
}, function(notices, asked, open, records, edits)
    for _, e in ipairs(notices:iter()) do
        local n = e:get("git/merge/notice")
        seen.notices = seen.notices + 1
        seen["notice_" .. seen.notices] = tostring(n.title) .. ": " .. tostring(n.text)
    end
    for _, e in ipairs(asked:iter()) do
        local v = e:get("vault/git")
        seen.asks = seen.asks + 1
        seen["ask_" .. seen.asks] = tostring(v.path) .. " " .. tostring(v.hash) .. " apply=" .. tostring(v.apply)
    end
    seen.open = #open:iter()
    local list = {}
    for _, e in ipairs(records:iter()) do
        local r = e:get("git/merge/result")
        list[#list + 1] = tostring(r.key) .. "=" .. tostring(r.status) .. ":" .. tostring(r.hash)
    end
    table.sort(list)
    seen.records = table.concat(list, ",")
    for _, e in ipairs(edits:iter()) do
        local d = e:get("core/library/edit")
        seen["on_" .. d.path] = tostring(d.on)
    end
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

local function read(path)
    local ok, text = pcall(read_file_bytes, path)
    return ok and text or nil
end

local function held(n) return ".hello/held/" .. H[n] end

local function finish()
    pcall(os.remove_dir, CK)
    pcall(os.remove, OUT)
    for n = 1, #H do pcall(os.remove, held(n)) end
    suite.finish("GIT_MERGE")
    st.phase = "done"
end

local function has_record(entry) return ("," .. tostring(seen.records) .. ","):find("," .. entry .. ",", 1, true) ~= nil end

local function busy()
    if pid ~= nil then
        if process_alive(pid) then return true end
        local code = process_exit_code(pid)
        kill_process(pid)
        pid = nil
        local step = table.remove(queue, 1)
        if code ~= 0 then
            T("M_git_" .. tostring(step.args[#step.args]), false, read(OUT) or "")
        end
    end
    while queue[1] and queue[1].write do
        local w = table.remove(queue, 1).write
        write_file_bytes(w[1], w[2])
    end
    if queue[1] == nil then return false end
    pid = spawn_process("git", queue[1].args, { output = OUT })
    return true
end

local function root_view(world)
    local view = { records = {}, open = 0, notices = {} }
    for _, e in ipairs(world:query({ with = { "git/merge/result" }, without = { "WorldMirror" } })) do
        local r = e:get("git/merge/result")
        view.records[#view.records + 1] = tostring(r.key) .. "=" .. tostring(r.status) .. ":" .. tostring(r.hash)
    end
    view.open = #world:query({ with = { "git/merge/job" }, without = { "RequestFrom" } })
    for _, e in ipairs(world:query({ with = { "git/merge/notice" } })) do
        view.notices[#view.notices + 1] = tostring(e:get("git/merge/notice").text)
    end
    return view
end

app:add_systems(Update, { World, Commands }, function(world, commands)
    if st.phase == "done" then return end
    st.t = st.t + (world:delta_time() or 0)
    if busy() then return end

    if st.phase == "clean" then
        pcall(os.remove_dir, CK)
        queue[#queue + 1] = { args = { "init", "-q", "-b", "main", CK } }
        write(CK .. "/assets/clean.txt", BASE)
        write(CK .. "/assets/clash.txt", BASE)
        write(CK .. "/assets/blob.bin", "\0\1\2\3")
        write(CK .. "/assets/mine.bin", "\0\1\2\3")
        write(CK .. "/assets/theirs.bin", "\0\1\2\3")
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m", "base")
        write(CK .. "/assets/clean.txt", MINE)
        write(CK .. "/assets/clash.txt", "a\nb\nc\nd\nMINE\nf\ng\nh\ni\n")
        write(CK .. "/assets/blob.bin", "\0\1\2\9")
        write(CK .. "/assets/mine.bin", "\0\1\2\9")
        write(held(1), THEIRS)
        write(held(2), "a\nb\nc\nd\nTHEIRS\nf\ng\nh\ni\n")
        write(held(3), "\0\1\2\7")
        write(held(4), "\0\1\2\3")
        write(held(5), "\0\1\2\7")
        write(held(6), THEIRS2)
        write(held(7), "late\n")
        st.phase = "boot"
        return
    end

    if st.phase == "boot" then
        local boot = BOOT:gsub("@ROOT", ROOT):gsub("@H(%d)", function(n) return tostring(H[tonumber(n)]) end)
        write_file_bytes(CK .. "/assets/modules/world/boot/client/init.lua", boot)
        commands:spawn({ ["core/world/instance"] = {
            mode = "client", scope_key = "zz:merge", asset_root = ROOT, headless = true,
        }, ["core/net/sync"] = false })
        -- At root, which root did not start: its requests are never answered. Root keeps its own
        -- tree on its ladder beside the stand-in.
        commands:spawn({ ["core/library"] = { ref = "zz:launch", root = "", order = 2 }, ["core/net/sync"] = false })
        commands:spawn({
            ["core/library"] = { ref = "zz:merge-root", root = ROOT, order = 0, edits = true },
            ["core/library/upstream"] = { held = { ["late.txt"] = H[7] } },
            ["core/net/sync"] = false,
        })
        commands:spawn({ ["git/merge"] = {}, ["zz/merge/root"] = {}, ["core/net/sync"] = false })
        st.phase, st.t = "booting", 0
        return
    end

    if st.phase == "booting" then
        if not seen.booted and st.t < 30 then return end
        if st.t < 2 then return end
        T("M0_the_world_booted", seen.booted == true, "the world never ran its boot")
        local view = root_view(world)
        T("M9_a_request_root_does_not_answer_stays_open_before_the_timeout",
            view.open == 1 and #view.records == 0,
            string.format("%d open, records %s", view.open, table.concat(view.records, ",")))
        seen.stage = 1
        st.phase, st.t = "answers", 0
        return
    end

    if st.phase == "answers" then
        local done = seen.asks >= 5 and seen.open == 0 and seen.notices >= 2
            and seen["on_clean.txt"] == tostring(H[1]) and seen["on_mine.bin"] == tostring(H[4])
        if not done and st.t < 40 then return end
        if st.t < 1 then return end
        T("M1_edits_that_do_not_overlap_are_written_merged_and_the_edit_is_on_the_held_version",
            read(CK .. "/assets/clean.txt") == MERGED and has_record("clean.txt=clean:" .. H[1])
            and seen["on_clean.txt"] == tostring(H[1]),
            string.format("file %q, records %s, on %s", tostring(read(CK .. "/assets/clean.txt")),
                tostring(seen.records), tostring(seen["on_clean.txt"])))
        local clash = read(CK .. "/assets/clash.txt") or ""
        local said = tostring(seen.notice_1) .. " | " .. tostring(seen.notice_2)
        T("M2_edits_that_overlap_leave_markers_a_notice_and_no_on",
            clash:find("<<<<<<< ", 1, true) ~= nil and clash:find("MINE", 1, true) ~= nil
            and clash:find("THEIRS", 1, true) ~= nil and has_record("clash.txt=conflict:" .. H[2])
            and said:find("CONFLICT: Someone else changed clash.txt", 1, true) ~= nil
            and seen["on_clash.txt"] == "nil",
            string.format("file %q, records %s, notices %s, on %s", clash, tostring(seen.records), said,
                tostring(seen["on_clash.txt"])))
        T("M3_a_binary_both_changed_fails_with_a_notice_untouched_and_no_on",
            read(CK .. "/assets/blob.bin") == "\0\1\2\9" and has_record("blob.bin=failed:" .. H[3])
            and said:find("COULD NOT MERGE: blob.bin", 1, true) ~= nil and seen["on_blob.bin"] == "nil",
            string.format("records %s, notices %s, on %s", tostring(seen.records), said, tostring(seen["on_blob.bin"])))
        T("M4_a_binary_only_you_changed_stands_and_the_edit_is_on_the_held_version",
            read(CK .. "/assets/mine.bin") == "\0\1\2\9" and has_record("mine.bin=clean:" .. H[4])
            and seen["on_mine.bin"] == tostring(H[4]),
            string.format("records %s, on %s", tostring(seen.records), tostring(seen["on_mine.bin"])))
        T("M5_a_binary_only_the_world_changed_is_written_with_the_held_version",
            read(CK .. "/assets/theirs.bin") == "\0\1\2\7" and has_record("theirs.bin=clean:" .. H[5]),
            string.format("records %s", tostring(seen.records)))
        local asks = {}
        for n = 1, seen.asks do asks[#asks + 1] = tostring(seen["ask_" .. n]) end
        local all = table.concat(asks, " | ")
        T("M6_one_request_per_held_version_each_applied_and_closed",
            seen.asks == 5 and seen.open == 0 and select(2, all:gsub("apply=true", "")) == 5
            and all:find("assets/clean.txt " .. H[1], 1, true) ~= nil,
            string.format("%d asked (%s), %d open", seen.asks, all, seen.open))
        seen.stage = 2
        st.phase, st.t = "again", 0
        return
    end

    if st.phase == "again" then
        local done = seen.asks >= 6 and seen.open == 0 and has_record("clean.txt=clean:" .. H[6])
            and seen["on_clean.txt"] == tostring(H[6]) and read(CK .. "/assets/clean.txt") == MERGED2
        if not done and st.t < 30 then return end
        if st.t < 1 then return end
        T("M7_a_new_held_version_is_merged_again_and_a_path_no_longer_held_loses_its_record",
            seen.asks == 6 and tostring(seen.ask_6):find("assets/clean.txt " .. H[6], 1, true) ~= nil
            and read(CK .. "/assets/clean.txt") == MERGED2 and seen["on_clean.txt"] == tostring(H[6])
            and has_record("clean.txt=clean:" .. H[6]) and not has_record("mine.bin=clean:" .. H[4]),
            string.format("%d asked (last %s), file %q, records %s, on %s", seen.asks, tostring(seen.ask_6),
                tostring(read(CK .. "/assets/clean.txt")), tostring(seen.records), tostring(seen["on_clean.txt"])))
        seen.late_edit = true
        st.phase, st.t = "late", 0
        return
    end

    if st.phase == "late" then
        if seen["on_theirs.bin"] ~= tostring(H[5]) and st.t < 10 then return end
        T("M8_an_edit_stated_after_the_answer_is_on_the_held_version",
            seen["on_theirs.bin"] == tostring(H[5]), "on " .. tostring(seen["on_theirs.bin"]))
        st.phase, st.t = "timeout", 0
        return
    end

    if st.phase == "timeout" then
        local view = root_view(world)
        if #view.records == 0 and st.t < 45 then return end
        T("M9_an_unanswered_request_fails_after_the_timeout_and_is_closed",
             table.concat(view.records, ",") == "late.txt=failed:" .. H[7] and view.open == 0
            and table.concat(view.notices, " | "):find("late.txt: git did not answer", 1, true) ~= nil,
            string.format("records %s, %d open, notices %s", table.concat(view.records, ","), view.open,
                table.concat(view.notices, " | ")))
        finish()
    end
end)
