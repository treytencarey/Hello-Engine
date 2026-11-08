-- test_merge_flow.lua: an edit that met someone else's, end to end. Root hosts the authority, the
-- world's tree, and starts a client world on the player's checkout, a git repository whose
-- committed files match what the authority started from. The authority's copy moves on, then the
-- player saves their own change. From there the path is the real one: the write comes back stale,
-- core holds the authority's version, git/merge asks root, root merges into the checkout, and the
-- result goes up. The player's edit is a stand-in for git/status.
--
-- F1  edits to different lines: the merged file reaches the authority with both changes, and the
--     checkout holds it too
-- F2  edits to the same line: conflict markers in the player's file, the authority untouched and
--     never shown a marker
-- F3  a binary the checkout never fetched, edited here while the authority holds the committed
--     version: it goes up as a create, comes back stale, and the merge takes yours, so it reaches
--     the authority

require("modules/core/init.lua")
require("modules/core/world/creator.lua")
require("modules/core/mod_registry/init.lua")

local helpers = require("modules/core/test_helpers.lua")
local Proto = require("modules/core/asset/shared.lua")
local AssetSrv = require("modules/core/asset/server/init.lua")

local suite = helpers.create_suite("GitMergeFlowSuite")
local T = suite.assert_test

local ROOT = "test_fixtures/zz-merge-flow"
local SROOT = ROOT .. "/authority"
local CROOT = ROOT .. "/checkout"
local S = "assets/" .. SROOT .. "/assets/"
local C = "assets/" .. CROOT .. "/assets/"
local OUT = "assets/test_fixtures/zz-merge-flow.out"
local PORT = 15617

local BASE = "a\nb\nc\nd\ne\nf\ng\nh\ni\n"
local CLEAN_THEIRS = "a\nb\nc\nd\ne\nf\ng\nh\nI (theirs)\n"
local CLEAN_MINE = "A (mine)\nb\nc\nd\ne\nf\ng\nh\ni\n"
local CLASH_THEIRS = "a\nb\nc\nd\nE (theirs)\nf\ng\nh\ni\n"
local CLASH_MINE = "a\nb\nc\nd\nE (mine)\nf\ng\nh\ni\n"
local BIN_BASE, BIN_MINE = "\0\1\2 committed map", "\0\1\2 my edited map"

local seen = helpers.shared_state("GitMergeFlowSeen", { notices = 0 })

AssetSrv.set_write_authorizer(function() return "allow" end)

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local BOOT = [==[
local seen = require("modules/core/test_helpers.lua").shared_state("GitMergeFlowSeen", {})

app:add_systems(Startup, { Commands }, function(commands)
    seen.booted = true
    commands:spawn({ ["core/library"] = { ref = "zz:launch", root = "", order = 2 }, ["core/net/sync"] = false })
    commands:spawn({
        ["core/library"] = {
            ref = "zz:merge-flow", root = "@CROOT", order = 0, edits = true,
            endpoint = { ip = "127.0.0.1", port = @PORT },
        },
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["git/merge"] = {} })
end)

app:add_systems(Update, {
    Query[{ added = { "git/merge/notice" } }],
    Query[{ with = { "git/merge/result" } }],
    Query[{ with = { "core/library", "core/library/upstream" } }],
    Commands,
}, function(notices, records, libraries, commands)
    if seen.edit and not seen.edited then
        seen.edited = true
        for _, path in ipairs({ "clean.txt", "clash.txt", "map.bin" }) do
            commands:spawn({ ["core/library/edit"] = { path = path, seq = 1 }, ["core/net/sync"] = false })
        end
    end
    for _, e in ipairs(notices:iter()) do
        local n = e:get("git/merge/notice")
        seen.notices = seen.notices + 1
        seen["notice_" .. seen.notices] = tostring(n.title) .. ": " .. tostring(n.text)
    end
    local list = {}
    for _, e in ipairs(records:iter()) do
        local r = e:get("git/merge/result")
        list[#list + 1] = tostring(r.key) .. "=" .. tostring(r.status)
    end
    table.sort(list)
    seen.records = table.concat(list, ",")
    for _, lib in ipairs(libraries:iter()) do
        local up = lib:get("core/library/upstream")
        if lib:get("core/library").edits then
            seen.ready = up.ready == true
            local held = {}
            for path, hash in pairs(type(up.held) == "table" and up.held or {}) do
                held[#held + 1] = tostring(path) .. "=" .. tostring(hash)
            end
            table.sort(held)
            seen.held = table.concat(held, ",")
        end
    end
end)
]==]

local st = { phase = "clean", t = 0 }
local queue, pid = {}, nil

local function git(...)
    local args = {
        "-C", "assets/" .. CROOT, "-c", "user.name=zz", "-c", "user.email=zz@zz.invalid",
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

-- The held store outlives a run: a version an earlier run left would already be held.
local function clear_held()
    for _, text in ipairs({ CLEAN_THEIRS, CLASH_THEIRS, BIN_BASE }) do
        pcall(os.remove, ".hello/held/" .. tostring(Proto.hash(text)))
    end
end

local function finish()
    pcall(os.remove_dir, "assets/" .. ROOT)
    pcall(os.remove, OUT)
    clear_held()
    suite.finish("GIT_MERGE_FLOW")
    st.phase = "done"
end

local function busy()
    if pid ~= nil then
        if process_alive(pid) then return true end
        local code = process_exit_code(pid)
        kill_process(pid)
        pid = nil
        local step = table.remove(queue, 1)
        if code ~= 0 then
            T("F_git_" .. tostring(step.args[#step.args]), false, read(OUT) or "")
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

local function shown(text) return (tostring(text):gsub("%z", "\\0"):gsub("\n", "\\n")) end

app:add_systems(Update, { World, Commands }, function(world, commands)
    if st.phase == "done" then return end
    st.t = st.t + (world:delta_time() or 0)
    if busy() then return end

    if st.phase == "clean" then
        pcall(os.remove_dir, "assets/" .. ROOT)
        clear_held()
        queue[#queue + 1] = { args = { "init", "-q", "-b", "main", "assets/" .. CROOT } }
        for _, at in ipairs({ S, C }) do
            write(at .. "clean.txt", BASE)
            write(at .. "clash.txt", BASE)
            write(at .. "map.bin", BIN_BASE)
        end
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m", "base")
        st.phase = "boot"
        return
    end

    if st.phase == "boot" then
        local boot = BOOT:gsub("@CROOT", CROOT):gsub("@PORT", tostring(PORT))
        write_file_bytes(C .. "modules/world/boot/client/init.lua", boot)
        commands:spawn({ ["core/asset"] = { mode = "server", port = PORT, asset_root = SROOT }, ["core/net/sync"] = false })
        commands:spawn({ ["core/world/instance"] = {
            mode = "client", scope_key = "zz:merge-flow", asset_root = CROOT, headless = true,
        }, ["core/net/sync"] = false })
        st.phase, st.t = "connect", 0
        return
    end

    if st.phase == "connect" then
        if not (seen.booted and seen.ready) and st.t < 30 then return end
        if st.t < 1.5 then return end
        T("F0_the_world_booted_and_its_checkout_connected", seen.booted == true and seen.ready == true,
            string.format("booted %s, ready %s", tostring(seen.booted), tostring(seen.ready)))
        -- Someone else's edits land at the authority first.
        write_file_bytes(S .. "clean.txt", CLEAN_THEIRS)
        write_file_bytes(S .. "clash.txt", CLASH_THEIRS)
        st.phase, st.t = "theirs", 0
        return
    end

    if st.phase == "theirs" then
        if st.t < 1 then return end
        -- Then the player saves their own.
        write_file_bytes(C .. "clean.txt", CLEAN_MINE)
        write_file_bytes(C .. "clash.txt", CLASH_MINE)
        write_file_bytes(C .. "map.bin", BIN_MINE)
        seen.edit = true
        st.phase, st.t = "merged", 0
        return
    end

    if st.phase == "merged" then
        local merged = read(S .. "clean.txt") or ""
        local both = merged:find("A (mine)", 1, true) and merged:find("I (theirs)", 1, true)
        local markers = (read(C .. "clash.txt") or ""):find("<<<<<<< ", 1, true)
        local bin = read(S .. "map.bin") == BIN_MINE
        if not (both and markers and bin) and st.t < 30 then return end
        if st.t < 1 then return end
        local said = {}
        for n = 1, seen.notices do said[#said + 1] = tostring(seen["notice_" .. n]) end
        T("F1_different_lines_merge_and_both_changes_reach_the_authority",
            both and read(C .. "clean.txt") == merged,
            string.format("authority %s, checkout %s, held %s, records %s", shown(read(S .. "clean.txt")),
                shown(read(C .. "clean.txt")), tostring(seen.held), tostring(seen.records)))
        T("F2_the_same_line_leaves_markers_in_your_file_only",
            markers ~= nil and read(S .. "clash.txt") == CLASH_THEIRS
            and table.concat(said, " | "):find("CONFLICT: Someone else changed clash.txt", 1, true) ~= nil,
            string.format("checkout %s, authority %s, notices %s", shown(read(C .. "clash.txt")),
                shown(read(S .. "clash.txt")), table.concat(said, " | ")))
        T("F3_a_binary_only_you_changed_reaches_the_authority", bin and read(C .. "map.bin") == BIN_MINE,
            string.format("authority %s, checkout %s, held %s, records %s", shown(read(S .. "map.bin")),
                shown(read(C .. "map.bin")), tostring(seen.held), tostring(seen.records)))
        finish()
    end
end)
