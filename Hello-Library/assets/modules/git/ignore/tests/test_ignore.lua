-- test_ignore.lua: git/ignore answers core's filter asks with root's real git, in a client world
-- root starts on a repository this suite makes. The world's boot carries git/ignore and asks as
-- core would, `core/library/filter/ask { paths }` children of the carrier.
--
-- I1  `assets/config/x.json` is out though no `assets/config/` exists, and a new `.blend1` is out
-- I2  a nested `.gitignore` holds for its folder only, and its `!` puts a file back
-- I3  a path git doesn't ignore is not out
-- I4  an ask root refuses (an unsafe path) answers every path of it out
-- I5  an ask under a carrier without git/ignore gets no answer from it

require("modules/core/init.lua")
require("modules/core/world/creator.lua")
require("modules/core/mod_registry/init.lua")
local helpers = require("modules/core/test_helpers.lua")

local suite = helpers.create_suite("GitIgnoreSuite")
local T = suite.assert_test

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["core/world/net"] = { mode = "server" }, ["core/net/sync"] = false })
end)

local ROOT = "test_fixtures/zz-ignore"
local CK = "assets/" .. ROOT
local OUT = "assets/test_fixtures/zz-ignore.out"
local seen = helpers.shared_state("GitIgnoreSeen", { good = "", bad = "", none = "", booted = false })

local BOOT = [==[
local seen = require("modules/core/test_helpers.lua").shared_state("GitIgnoreSeen", {})
local GOOD = { "assets/config/x.json", "assets/modules/maps/lab/lab.blend1", "assets/modules/a/local.txt",
    "assets/modules/b/local.txt", "assets/modules/a/keep.blend1", "assets/modules/ok.lua" }
app:add_systems(Startup, { Commands }, function(commands)
    seen.booted = true
    commands:spawn({ ["core/library"] = { ref = "zz:launch", root = "", order = 2 }, ["core/net/sync"] = false })
    local c = commands:spawn({ ["git/ignore"] = {}, ["core/net/sync"] = false }):id()
    commands:spawn({ ["core/library/filter/ask"] = { paths = GOOD }, ["zz/ignore/good"] = {}, ChildOf = c, ["core/net/sync"] = false })
    commands:spawn({ ["core/library/filter/ask"] = { paths = { "assets/../x.txt", "assets/fine.txt" } }, ["zz/ignore/bad"] = {},
        ChildOf = c, ["core/net/sync"] = false })
    local bare = commands:spawn({ ["core/library/filter"] = {}, ["core/net/sync"] = false }):id()
    commands:spawn({ ["core/library/filter/ask"] = { paths = { "assets/config/y.json" } }, ["zz/ignore/none"] = {},
        ChildOf = bare, ["core/net/sync"] = false })
end)
app:add_systems(Update, {
    Query[{ added = { "core/library/filter/ask/reply" }, optional = { "zz/ignore/good", "zz/ignore/bad", "zz/ignore/none" } }],
}, function(rows)
    for _, r in ipairs(rows:iter()) do
        local out = r:get("core/library/filter/ask/reply").out or {}
        table.sort(out)
        local text = table.concat(out, ",")
        if r:has("zz/ignore/good") then seen.good = text end
        if r:has("zz/ignore/bad") then seen.bad = text end
        if r:has("zz/ignore/none") then seen.none = text end
    end
end)
]==]

local st = { phase = "clean", t = 0 }
local queue, pid = {}, nil
local function git(...)
    local args = { "-C", CK, "-c", "user.name=zz", "-c", "user.email=zz@zz.invalid", "-c", "commit.gpgsign=false" }
    for _, a in ipairs({ ... }) do args[#args + 1] = a end
    queue[#queue + 1] = { args = args }
end
local function write(path, text) queue[#queue + 1] = { write = { path, text } } end
local function finish()
    pcall(os.remove_dir, CK)
    pcall(os.remove, OUT)
    suite.finish("GIT_IGNORE")
    st.phase = "done"
end
local function busy()
    if pid ~= nil then
        if process_alive(pid) then return true end
        local code = process_exit_code(pid)
        kill_process(pid)
        pid = nil
        local step = table.remove(queue, 1)
        if code ~= 0 then T("I_git_" .. tostring(step.args[#step.args]), false, read_file_bytes(OUT) or "") end
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
    local function step(p) st.phase, st.t = p, 0 end

    if st.phase == "clean" then
        pcall(os.remove_dir, CK)
        queue[#queue + 1] = { args = { "init", "-q", "-b", "main", CK } }
        write(CK .. "/assets/modules/world/boot/client/init.lua", BOOT)
        write(CK .. "/.gitignore", "assets/config/\n*.blend1\n")
        write(CK .. "/assets/modules/a/.gitignore", "local.txt\n!keep.blend1\n")
        write(CK .. "/assets/modules/ok.lua", "return 1\n")
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m", "first")
        step("boot")
    elseif st.phase == "boot" then
        commands:spawn({ ["core/world/instance"] = {
            mode = "client", scope_key = "zz:ignore:main", asset_root = ROOT, headless = true,
        }, ["core/net/sync"] = false })
        step("answers")
    elseif st.phase == "answers" then
        if (seen.good == "" or seen.bad == "") and st.t < 30 then return end
        if st.t < 2 then return end
        local good = "," .. tostring(seen.good) .. ","
        local function has(p) return good:find("," .. p .. ",", 1, true) ~= nil end
        T("I1_config_is_out_with_no_config_folder_and_a_blend1_is_out",
            has("assets/config/x.json") and has("assets/modules/maps/lab/lab.blend1"), "out " .. tostring(seen.good))
        T("I2_a_nested_gitignore_holds_for_its_folder_and_its_bang_puts_back",
            has("assets/modules/a/local.txt") and not has("assets/modules/b/local.txt") and not has("assets/modules/a/keep.blend1"),
            "out " .. tostring(seen.good))
        T("I3_a_path_git_does_not_ignore_is_not_out", not has("assets/modules/ok.lua"), "out " .. tostring(seen.good))
        T("I4_a_refused_ask_answers_every_path_out", seen.bad == "assets/../x.txt,assets/fine.txt", "out " .. tostring(seen.bad))
        T("I5_no_answer_without_git_ignore", seen.none == "", "out " .. tostring(seen.none))
        finish()
    end
end)
