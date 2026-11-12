-- --host
-- The file browser over a real connection. An isolated server VM, launched with an `asset_root` of
-- its own, spawns real players; this VM is a client of it, with a real `player/client`, sidebar and
-- clicks, and a second client VM asks for itself. What a client may ask is driven by a forged UPDATE
-- through `core/net/send`, as a modified client could send it. Reading a folder is not available yet,
-- which the suite proves first. It then stands in made-up entries for the read, on the server VM, to
-- drive all that does not touch a disk. Layout and a real pointer are in test_file_browser_windowed.lua.
require("modules/core/init.lua")
require("modules/core/mod_registry/init.lua")
require("modules/core/net/client/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local MessageWriter = require("bevy::prelude").MessageWriter
local MessageReader = require("bevy::prelude").MessageReader
local DiagnosticsStore = require("bevy::diagnostic::DiagnosticsStore")

local suite = helpers.create_suite("FileBrowserNetSuite")
local T = suite.assert_test

local PORT = 15191
local TREE = "test_fixtures/file_browser_net/tree"
local CLIENT_FILE = "assets/modules/sidebar/file_browser/client/init.lua"
local SERVER_FILE = "assets/modules/sidebar/file_browser/server/init.lua"
local PANEL_FILE = "assets/modules/sidebar/panel/init.lua"
local SIDEBAR_FILE = "assets/modules/sidebar/init.lua"

write_file_bytes("assets/" .. TREE .. "/assets/zz_tree.txt", "x")

local DEFAULTS = {
    port_up = false, carriers = 0, sync_listed = 0, serves = 0, reads = 0, read_root = "", read_paths = "",
    made_up = false, gone = false, alpha_changed = false, drop_carrier = false, c2_answer_rows = 0, c2_said = "", c2_replica_parts = 0,
}
local ts = helpers.shared_state("FileBrowserNetState", DEFAULTS)

helpers.make_fixture("modules/test_fixtures/gen_file_browser_server.lua", [=[
require("modules/core/net/server/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local Listing = require("modules/sidebar/file_browser/server/listing.lua")
local boot = Instances.boot_data()
local ts = helpers.shared_state("FileBrowserNetState", boot.DEFAULTS)

local function entries(list)
    local out = {}
    for name, is_dir in pairs(list) do out[#out + 1] = { name = name, is_dir = is_dir, size = is_dir and 0 or 1 } end
    return out
end
local MADE_UP = {
    [""] = entries({
        zz_tree = false, Zeta = false, apple = false, [".env"] = false, Alpha = true, beta = true, gone = true, many = true,
        sub = true, upper = true, config = true, deploy_keys = true, gateways = true, [".hidden"] = true,
    }),
    sub = entries({ inner = true, config = true, deploy_keys = true, gateways = true, [".hidden"] = true, [".env"] = false }),
    ["sub/inner"] = entries({ deep = false }),
    upper = entries({ CONFIG = true, ["config."] = true, GateWays = true }),
    gone = entries({ inside = false }),
    beta = entries({ file = false }),
    Alpha = entries({ file = false }),
}
local many = {}
for i = 1, 230 do many[string.format("f%03d", i)] = false end
MADE_UP.many = entries(many)

-- The read every ask reaches: what it was handed, then the stub, or made-up entries.
local stub = Listing.read
Listing.read = function(root, path)
    ts.reads = ts.reads + 1
    ts.read_root = root
    ts.read_paths = ts.read_paths .. "[" .. path .. "]"
    if not ts.made_up then return stub(root, path) end
    if ts.gone and path == "gone" then return {} end
    if ts.alpha_changed and path == "Alpha" then return entries({ changed = false }) end
    return MADE_UP[path] or {}
end

app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({
        ["core/world/net"] = { mode = "server", name = "zzfb", port = boot.PORT, max_clients = 4 },
        ["core/net"] = { mode = "server", name = "zzfb", port = boot.PORT, max_clients = 4 },
        ["core/net/sync"] = false,
    })
    commands:spawn({ ["player/spawner"] = {}, ["core/net/sync"] = false })
    commands:spawn({
        Name = "zz_a",
        Transform = { translation = { x = 0, y = 0, z = -3 } },
        ["player/spawner/point"] = {},
        ["core/net/sync"] = false,
    })
    commands:spawn({
        Name = "zz_b",
        Transform = { translation = { x = -3, y = 0, z = 0 } },
        ["player/spawner/point"] = {},
        ["core/net/sync"] = false,
    })
end)
app:add_systems(Update, {
    Query[{
        with = { "player" },
        optional = { "sidebar/file_browser", "core/net/sync" },
    }],
}, function(players)
    local carriers, listed = 0, 0
    for _, p in ipairs(players:iter()) do
        if p:has("sidebar/file_browser") then carriers = carriers + 1 end
        local sync = p:get("core/net/sync")
        if type(sync) == "table" and sync["sidebar/file_browser/answer"] ~= nil then listed = listed + 1 end
    end
    ts.carriers, ts.sync_listed = carriers, listed
    ts.port_up = true
end):in_set("zz/fb_server_report")
app:add_systems(Update, { Query[{ changed = { "sidebar/file_browser/answer" } }] }, function(answers)
    for _, _ in ipairs(answers:iter()) do ts.serves = ts.serves + 1 end
end):in_set("zz/fb_server_serves")
app:add_systems(Update, {
    Query[{ with = { "player", "sidebar/file_browser" } }],
    Commands,
}, function(players, commands)
    if ts.drop_carrier then
        for _, p in ipairs(players:iter()) do commands:entity(p:id()):remove("sidebar/file_browser") end
    end
end):in_set("zz/fb_server_drop")
]=])
helpers.spawn_vm("modules/test_fixtures/gen_file_browser_server.lua", { DEFAULTS = DEFAULTS, PORT = PORT },
    { headless = true, asset_root = TREE, asset_root_absolute = true })

-- A second client: it asks for one good path and one bad, and says all it ever held.
helpers.make_fixture("modules/test_fixtures/gen_file_browser_client2.lua", [=[
require("modules/core/net/client/init.lua")
require("modules/core/mod_registry/init.lua")
local Instances = require("modules/core/instances.lua")
local helpers = require("modules/core/test_helpers.lua")
local boot = Instances.boot_data()
local ts = helpers.shared_state("FileBrowserNetState", boot.DEFAULTS)
local connected, asked = false, false
app:add_systems(Update, {
    Query[{ with = { "sidebar/file_browser", "core/net/local", "core/net/sync" } }],
    Commands,
}, function(mine, commands)
    if not connected then
        connected = true
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zzfb_c2", ip = "127.0.0.1", port = boot.PORT },
            ["core/net"] = { mode = "client", name = "zzfb_c2", ip = "127.0.0.1", port = boot.PORT },
            ["core/net/sync"] = false,
        })
    end
    local me = mine:iter()[1]
    if me ~= nil and not asked then
        local sync = me:get("core/net/sync")
        if type(sync) == "table" and sync["sidebar/file_browser/request"] ~= nil then
            asked = true
            commands:entity(me:id()):patch({ ["sidebar/file_browser/request"] = {
                ["0:other"] = { op = "list", path = "other", offset = 0, limit = 10 },
                ["0:config"] = { op = "list", path = "config", offset = 0, limit = 10 },
            } })
        end
    end
end):in_set("zz/fb_client2")
app:add_systems(Update, {
    Query[{ changed = { "sidebar/file_browser/answer" } }],
    Query[{ with = { "player", "core/net/local" } }],
}, function(changed, locals)
    local mine = locals:iter()[1]
    for _, e in ipairs(changed:iter()) do
        if mine ~= nil and e:id() == mine:id() then
            local parts = {}
            for key, answer in pairs(e:get("sidebar/file_browser/answer")) do
                parts[#parts + 1] = key .. "=" .. tostring(answer.error)
            end
            table.sort(parts)
            if #parts > 0 then ts.c2_said = table.concat(parts, ";") end
        else
            ts.c2_answer_rows = ts.c2_answer_rows + 1
        end
    end
end):in_set("zz/fb_client2_answers")
app:add_systems(Update, {
    Query[{
        with = { "player" },
        without = { "core/net/local" },
        any_of = { "sidebar/file_browser", "sidebar/file_browser/request", "sidebar/file_browser/answer" },
    }],
}, function(parts)
    ts.c2_replica_parts = math.max(ts.c2_replica_parts, parts:count())
end):in_set("zz/fb_client2_replica")
]=])

-- A real reload rewrites a file under an immediate watcher. The watcher skips a file whose bytes it
-- has seen, so each rewrite differs, by a comment at the end, and the end of the suite puts them back.
app:add_systems(Startup, { Commands }, function(commands)
    commands:spawn({ ["ui/theme/dark"] = {} })
end)

local originals = {}
local rewrites = 0

local function reload(path, change_from, change_to)
    originals[path] = originals[path] or read_file_bytes(path)
    local source = originals[path]
    if change_from ~= nil then
        local from, to = source:find(change_from, 1, true)
        source = source:sub(1, from - 1) .. change_to .. source:sub(to + 1)
    end
    rewrites = rewrites + 1
    write_file_bytes(path, source .. "\n-- zz " .. rewrites .. "\n")
end

local function finish()
    for path, source in pairs(originals) do
        write_file_bytes(path, source)
    end
    os.remove_dir("assets/test_fixtures/file_browser_net")
    suite.finish("FILE_BROWSER_NET")
end

-- Every answer this client ever held, by key: the client half takes a key as soon as it reads it.
local seen = {}
app:add_systems(Update, {
    Query[{
        changed = { "sidebar/file_browser/answer" },
        with = { "core/net/local" },
    }],
}, function(changed)
    for _, e in ipairs(changed:iter()) do
        for key, answer in pairs(e:get("sidebar/file_browser/answer")) do
            seen[key] = answer
        end
    end
end):in_set("zz/fb_seen")

-- Refresh in the very frame an answer is read: the key is taken out and missing again at once, with
-- the server's answer still standing. Asked again then, the request would not change on the wire:
-- the old answer would read as new, or, with nothing else asked, no answer would ever come.
local refresh_at_read = false
app:add_systems(Update, {
    Query[{
        changed = { "sidebar/file_browser/answer" },
        with = { "core/net/local" },
    }],
    Query[{ with = { "sidebar/file_browser/refresh" } }],
    Commands,
}, function(changed, refreshes, commands)
    for _, e in ipairs(changed:iter()) do
        local refresh = refreshes:iter()[1]
        if refresh_at_read and refresh ~= nil and e:get("sidebar/file_browser/answer")["0:Alpha"] ~= nil then
            refresh_at_read = false
            ts.alpha_changed = true
            commands:trigger(Pointer[Click], {
                entity = refresh:id(),
                pointer_location = { target = { None = { width = 0, height = 0 } } },
                event = { button = "Primary", hit = { camera = refresh:id() } },
            })
        end
    end
end):in_set("zz/fb_refresh_at_read"):after("sidebar/file_browser/receive"):before("sidebar/file_browser/ask")

local reloads = 0
app:add_systems(Update, { MessageReader["core/hot_reload/file_changed"] }, function(changed)
    for _, event in ipairs(changed:read()) do
        local path = tostring(event.path)
        if path:find("sidebar/file_browser/client/init.lua", 1, true) or path:find("sidebar/file_browser/server/init.lua", 1, true)
            or path:find("sidebar/panel/init.lua", 1, true) or path:find("sidebar/init.lua", 1, true) then
            reloads = reloads + 1
        end
    end
end):in_set("zz/fb_reload_watch")

-- How often the first slot's name is written: a row that does not move is not rewritten.
local first_writes = 0
app:add_systems(Update, {
    Query[{
        changed = { "Text" },
        with = { "sidebar/file_browser/name", "ChildOf" },
    }],
    Query[{ with = { "sidebar/file_browser/row" } }],
}, function(changed, slots)
    for _, e in ipairs(changed:iter()) do
        local slot = slots:get(e:get("ChildOf"))
        if slot ~= nil and slot:get("sidebar/file_browser/row").index == 1 then
            first_writes = first_writes + 1
        end
    end
end):in_set("zz/fb_first_writes")

local function me(world)
    return world:query({
        with = { "player", "core/net/local", "core/net/id" },
        optional = {
            "sidebar", "sidebar/file_browser", "sidebar/file_browser/state", "sidebar/file_browser/request",
            "sidebar/file_browser/answer", "core/net/sync",
        },
    })[1]
end

local function count(world, name)
    return #world:query({ with = { name } })
end

local function button(world)
    return world:query({ with = { "sidebar/file_browser/button" }, optional = { "sidebar/button/open", "ui/style" } })[1]
end

local function view(world)
    return world:query({ with = { "sidebar/file_browser/view" }, optional = { "sidebar/panel", "ChildOf" } })[1]
end

-- The rows as drawn, in order, read through each slot's own children.
local function rows(world)
    local out = {}
    for _, slot in ipairs(world:query({ with = { "sidebar/file_browser/row" } })) do
        local inside = world:descendants(slot:id())
        local name = world:query({ iter_many = inside, with = { "sidebar/file_browser/name", "Text" } })[1]
        local mark = world:query({ iter_many = inside, with = { "sidebar/file_browser/mark", "Text" } })[1]
        local size = world:query({ iter_many = inside, with = { "sidebar/file_browser/size", "Text" } })[1]
        local data = slot:get("sidebar/file_browser/row")
        out[data.index] = {
            id = slot:id(), kind = data.kind, path = data.path, depth = data.depth,
            name = name and name:get("Text"), mark = mark and mark:get("Text"), size = size and size:get("Text"),
        }
    end
    return out
end

local function row_at(world, path, kind)
    for _, row in ipairs(rows(world)) do
        if row.path == path and (kind == nil or row.kind == kind) then return row end
    end
end

local function names_of(world)
    local names = {}
    for _, row in ipairs(rows(world)) do names[#names + 1] = tostring(row.name) end
    return table.concat(names, " ")
end

local function open_once(world)
    local state = me(world):get("sidebar/file_browser/state") or {}
    local b = button(world)
    local text = string.format("buttons %d views %d rows %d lists %d scrolls %d refresh %d open %s sub %s inner row %s",
        count(world, "sidebar/file_browser/button"), count(world, "sidebar/file_browser/view"), #rows(world),
        count(world, "sidebar/file_browser/rows"), count(world, "sidebar/panel/scroll"), count(world, "sidebar/file_browser/refresh"),
        tostring(state.open), tostring((state.expanded or {}).sub), tostring(row_at(world, "sub/inner") ~= nil))
    return count(world, "sidebar/file_browser/button") == 1 and b ~= nil and b:has("sidebar/button/open")
        and count(world, "sidebar/file_browser/view") == 1 and count(world, "sidebar/file_browser/rows") == 1
        and count(world, "sidebar/panel/scroll") == 1 and count(world, "sidebar/file_browser/refresh") == 1
        and state.open == true and (state.expanded or {}).sub == true and row_at(world, "sub/inner") ~= nil, text
end

local function title_of(world)
    local e = world:query({ with = { "sidebar/panel/title", "Text" } })[1]
    return e and e:get("Text")
end

local function names_in(answer)
    local names = {}
    for _, file in ipairs((answer or {}).files or {}) do names[#names + 1] = file.name end
    return table.concat(names, " ")
end

-- Every spelling a client could ask for a private or outside path, each refused. A protection
-- taken away shows as the answer a path that passes gets.
local REFUSED = {
    "..", "../", "../..", "sub/..", "sub/../..", "sub/../../above", "... ", ". .", ".. ",
    "C:/Windows", "C:\\Windows", "c:", "/", "/etc", "//server/share",
    "config::$DATA", "config::$INDEX_ALLOCATION", "sub/config::$INDEX_ALLOCATION", "sub/plain::$DATA",
    "sub\\config", "sub\\inner", "\\sub",
    "CONFIG", "Config", "config.", "config ", "config. .", "upper/config", "upper/CONFIG",
    "config", "deploy_keys", "gateways", "sub/config", "sub/deploy_keys", "sub/gateways",
    "sub/config/", "./config", "sub/./config", "sub//config", "config/made_up.txt", "sub/",
    ".hidden", ".env", "sub/.hidden", "sub/.env", ".hidden/made_up.txt",
    "deploy~1", "DEPLOY~1", "sub/deploy~1", "sub/\t", "sub/\n",
}

-- Requests that are not plain, or not a known op, each refused.
local NOT_PLAIN = {
    { name = "not_a_table", ask = 5 },
    { name = "text", ask = "list" },
    { name = "no_op", ask = { path = "sub" } },
    { name = "op_a_number", ask = { op = 5, path = "sub" } },
    { name = "touch", ask = { op = "touch", path = "made" } },
    { name = "mkdir", ask = { op = "mkdir", path = "made" } },
    { name = "rename", ask = { op = "rename", path = "sub", new_path = "renamed" } },
    { name = "delete", ask = { op = "delete", path = "sub" } },
    { name = "path_a_table", ask = { op = "list", path = { "sub" } } },
    { name = "no_path", ask = { op = "list" } },
    { name = "offset_text", ask = { op = "list", path = "sub", offset = "1" } },
    { name = "offset_below_0", ask = { op = "list", path = "sub", offset = -1 } },
    { name = "limit_text", ask = { op = "list", path = "sub", limit = "1" } },
    { name = "limit_0", ask = { op = "list", path = "sub", limit = 0 } },
    { name = "path_too_long", ask = { op = "list", path = string.rep("a", 2000) } },
}

local phase, clock, frames = "wait_server", 0, 0
local mark, cursor = {}, 1

local function click(commands, entity)
    commands:trigger(Pointer[Click], {
        entity = entity,
        pointer_location = { target = { None = { width = 0, height = 0 } } },
        event = { button = "Primary", hit = { camera = mark.camera } },
    })
end

local function all_seen(keys)
    for _, key in ipairs(keys) do
        if seen[key] == nil then return false end
    end
    return true
end

app:add_systems(Update, {
    World,
    Res[DiagnosticsStore],
    MessageWriter["core/net/send"],
    Commands,
}, function(world, store, sends, commands)
    clock = clock + (world:delta_time() or 0)
    frames = frames + 1
    local function step(next_phase) phase, clock, frames = next_phase, 0, 0 end
    local function forge(request)
        sends:write({
            msg_type = "update",
            net_id = me(world):get("core/net/id").id,
            components = { ["sidebar/file_browser/request"] = request },
        })
    end

    if phase == "wait_server" and ts.port_up then
        commands:spawn({
            ["core/world/net"] = { mode = "client", name = "zzfb_c", ip = "127.0.0.1", port = PORT },
            ["core/net"] = { mode = "client", name = "zzfb_c", ip = "127.0.0.1", port = PORT },
            ["core/net/sync"] = false,
        })
        mark.camera = commands:spawn({ ["zz/camera"] = {} }):id()
        step("joining")

    elseif phase == "joining" and me(world) ~= nil and button(world) ~= nil and clock > 0.5 then
        local mine = me(world)
        T("A1_the_server_gives_the_panel_to_its_player", ts.carriers == 1, tostring(ts.carriers))
        T("A1_and_lists_the_request_and_answer", ts.sync_listed == 1, tostring(ts.sync_listed))
        T("A2_it_reaches_the_owner", mine:has("sidebar/file_browser"))
        local sync = mine:get("core/net/sync")
        local request_sync = sync["sidebar/file_browser/request"] or {}
        local answer_sync = sync["sidebar/file_browser/answer"] or {}
        T("A3_the_request_is_the_owners_and_the_answer_the_servers",
            request_sync.authority == "client" and request_sync.target == "owner"
            and answer_sync.authority == "server" and answer_sync.target == "owner")
        T("A4_with_the_defaults_both_sides_read", mine:get("sidebar/file_browser").page_size == 50
            and mine:get("sidebar/file_browser").max_limit == 200)
        T("B1_one_button_in_the_bar", count(world, "sidebar/file_browser/button") == 1)
        T("B2_its_state_starts_closed", (mine:get("sidebar/file_browser/state") or {}).open == false)
        commands:entity(mine:id()):patch({ ["sidebar/open"] = {} })
        step("closed_idle")

    -- A whole history closed: nothing has asked, and the panel's systems have cost nothing.
    elseif phase == "closed_idle" and frames >= 130 and clock > 2 then
        T("C1_closed_nothing_is_asked", ts.serves == 0 and ts.reads == 0 and next(seen) == nil, ts.serves .. " " .. ts.reads)
        T("C1_there_is_no_view", count(world, "sidebar/file_browser/view") == 0 and count(world, "sidebar/file_browser/row") == 0)
        local most = 0
        for _, set in ipairs({ "lua/sidebar/file_browser/ask", "lua/sidebar/file_browser/render", "lua/sidebar/file_browser/receive" }) do
            local row = store:get(set)
            for _, value in ipairs(row and row:values() or {}) do most = math.max(most, value) end
        end
        T("C2_closed_its_systems_do_nothing", most == 0, tostring(most))
        forge({ good = { op = "list", path = "sub/inner", offset = 3, limit = 50 } })
        step("good")

    elseif phase == "good" and seen.good ~= nil then
        T("N1_a_good_path_answers_not_available", seen.good.error == "not available" and seen.good.files == nil, tostring(seen.good.error))
        T("N1_on_its_own_key", seen.good.path == "sub/inner" and seen.good.offset == 3)
        T("R1_the_read_is_handed_this_worlds_root", ts.read_root == "assets/" .. TREE .. "/assets", ts.read_root)
        T("R2_and_the_path_relative_to_it", ts.read_paths == "[sub/inner]", ts.read_paths)
        local root_crossed = false
        for _, value in pairs(seen.good) do
            root_crossed = root_crossed or (type(value) == "string" and value:find("test_fixtures", 1, true) ~= nil)
        end
        T("R3_the_root_never_crosses", not root_crossed)
        mark.batch = {}
        mark.reads = ts.reads
        step("refused")

    -- A few at a time, each batch all answered before the next.
    elseif phase == "refused" and all_seen(mark.batch) then
        for _, key in ipairs(mark.batch) do
            local answer = seen[key]
            T("P1_refused_" .. REFUSED[tonumber(key:sub(2))], answer.error == "refused" and answer.files == nil, tostring(answer.error))
        end
        mark.batch = {}
        local request = {}
        while cursor <= #REFUSED and #mark.batch < 12 do
            local key = "p" .. cursor
            mark.batch[#mark.batch + 1] = key
            request[key] = { op = "list", path = REFUSED[cursor], offset = 0, limit = 50 }
            cursor = cursor + 1
        end
        if #mark.batch > 0 then
            forge(request)
        else
            T("P2_a_refused_path_never_reaches_the_read", ts.reads == mark.reads, ts.reads .. " " .. mark.reads)
            cursor = 1
            step("not_plain")
        end

    elseif phase == "not_plain" and all_seen(mark.batch) then
        for _, key in ipairs(mark.batch) do
            T("P3_refused_" .. key, seen[key].error == "refused" and seen[key].files == nil, tostring(seen[key].error))
        end
        mark.batch = {}
        local request = {}
        while cursor <= #NOT_PLAIN and #mark.batch < 12 do
            local case = NOT_PLAIN[cursor]
            mark.batch[#mark.batch + 1] = case.name
            request[case.name] = case.ask
            cursor = cursor + 1
        end
        if #mark.batch > 0 then
            forge(request)
        else
            T("P4_a_request_not_plain_never_reaches_the_read", ts.reads == mark.reads, ts.reads .. " " .. mark.reads)
            forge(5)
            step("whole_not_a_table")
        end

    -- A request that is no table at all answers nothing, and the server lives.
    elseif phase == "whole_not_a_table" and clock > 0.5 then
        forge({ alive = { op = "list", path = "sub", offset = 0, limit = 50 } })
        step("alive")

    elseif phase == "alive" and seen.alive ~= nil then
        T("P5_a_request_that_is_no_table_does_not_stop_the_server", seen.alive.error == "not available", tostring(seen.alive.error))
        local at_bound = {}
        for i = 1, 16 do at_bound["b" .. i] = { op = "list", path = "sub", offset = 0, limit = 1 } end
        forge(at_bound)
        step("at_bound")

    elseif phase == "at_bound" and seen.b1 ~= nil and clock > 0.2 then
        local answered = 0
        for i = 1, 16 do
            if seen["b" .. i] ~= nil then answered = answered + 1 end
        end
        T("K1_a_request_at_the_key_bound_is_answered", answered == 16, tostring(answered))
        mark.reads = ts.reads
        local past_bound = {}
        for i = 1, 17 do past_bound["w" .. i] = { op = "list", path = "sub", offset = 0, limit = 1 } end
        forge(past_bound)
        step("past_bound")

    elseif phase == "past_bound" and clock > 0.7 then
        local answered = 0
        for i = 1, 17 do
            if seen["w" .. i] ~= nil then answered = answered + 1 end
        end
        T("K2_a_request_past_the_key_bound_is_refused_whole", answered == 0, tostring(answered))
        T("K2_with_no_read_at_all", ts.reads == mark.reads, ts.reads .. " " .. mark.reads)
        ts.made_up = true
        forge({ top = { op = "list", path = "", offset = 0, limit = 50 } })
        step("top")

    elseif phase == "top" and seen.top ~= nil then
        T("O1_private_and_hidden_names_are_dropped_and_folders_come_first",
            names_in(seen.top) == "Alpha beta gone many sub upper apple Zeta zz_tree", names_in(seen.top))
        T("O2_the_count_leaves_them_out", seen.top.total_count == 9, tostring(seen.top.total_count))
        T("O3_a_top_path_is_its_name", seen.top.files[1].path == "Alpha" and seen.top.files[1].is_directory == true)
        forge({ deep = { op = "list", path = "sub", offset = 0, limit = 50 } })
        step("deep")

    elseif phase == "deep" and seen.deep ~= nil then
        T("O4_at_any_depth_too", names_in(seen.deep) == "inner" and seen.deep.total_count == 1, names_in(seen.deep))
        forge({ upper = { op = "list", path = "upper", offset = 0, limit = 50 } })
        step("upper")

    elseif phase == "upper" and seen.upper ~= nil then
        T("O5_in_any_case_too", seen.upper.total_count == 0, names_in(seen.upper))
        forge({ wide = { op = "list", path = "many", offset = 0, limit = 100000 } })
        step("limit")

    elseif phase == "limit" and seen.wide ~= nil then
        T("L1_a_limit_past_the_bound_answers_the_bound", #seen.wide.files == 200, tostring(#seen.wide.files))
        T("L1_and_says_more_follow", seen.wide.has_more == true and seen.wide.total_count == 230)
        forge({ huge = { op = "list", path = "many", offset = 0, limit = 1e308 } })
        step("limit_huge")

    elseif phase == "limit_huge" and seen.huge ~= nil then
        T("L2_any_limit_past_it_too", #seen.huge.files == 200, tostring(#seen.huge.files))
        forge({ page = { op = "list", path = "many", offset = 200, limit = 50 } })
        step("page")

    elseif phase == "page" and seen.page ~= nil then
        T("L3_a_page_starts_at_its_offset", #seen.page.files == 30 and seen.page.files[1].name == "f201"
            and seen.page.offset == 200, tostring(#seen.page.files))
        T("L3_and_the_last_says_none_follow", seen.page.has_more == false)
        ts.made_up = false
        -- The real client's own request again: it writes it whole from here.
        forge({})
        commands:entity(me(world):id()):patch({ ["sidebar/file_browser/request"] = {
            ["0:Alpha"] = { op = "list", path = "Alpha", offset = 0, limit = 50 },
            ["0:beta"] = { op = "list", path = "beta", offset = 0, limit = 50 },
        } })
        mark.quick = 0
        step("quick")

    -- Two asks written in a frame, then more in each of the next two: each is answered.
    elseif phase == "quick" then
        mark.quick = mark.quick + 1
        if mark.quick == 1 then
            commands:entity(me(world):id()):patch({ ["sidebar/file_browser/request"] = {
                ["0:gone"] = { op = "list", path = "gone", offset = 0, limit = 50 },
            } })
        elseif mark.quick == 2 then
            commands:entity(me(world):id()):patch({ ["sidebar/file_browser/request"] = {
                ["1:many"] = { op = "list", path = "many", offset = 1, limit = 1 },
                ["2:many"] = { op = "list", path = "many", offset = 2, limit = 1 },
            } })
        elseif all_seen({ "0:Alpha", "0:beta", "0:gone", "1:many", "2:many" }) then
            T("Q1_asks_in_one_frame_both_land", seen["0:Alpha"].path == "Alpha" and seen["0:beta"].path == "beta")
            T("Q2_an_ask_a_frame_later_lands_too", seen["0:gone"].path == "gone")
            T("Q3_two_pages_of_one_folder_each_land", seen["1:many"].offset == 1 and seen["2:many"].offset == 2)
            helpers.spawn_vm("modules/test_fixtures/gen_file_browser_client2.lua", { DEFAULTS = DEFAULTS, PORT = PORT }, { headless = true })
            step("second_client")
        end

    elseif phase == "second_client" and ts.c2_said ~= "" and clock > 0.5 then
        T("S1_a_second_client_gets_its_own_answers", ts.c2_said == "0:config=refused;0:other=not available", ts.c2_said)
        T("S2_the_server_gave_it_its_own_panel", ts.carriers == 2, tostring(ts.carriers))
        local remote = world:query({
            with = { "player" },
            without = { "core/net/local" },
            optional = { "sidebar/file_browser", "sidebar/file_browser/request", "sidebar/file_browser/answer" },
        })[1]
        T("S3_it_arrives_here_as_a_player_with_none_of_the_panel", remote ~= nil and not remote:has("sidebar/file_browser")
            and not remote:has("sidebar/file_browser/request") and not remote:has("sidebar/file_browser/answer"))
        T("S4_the_other_client_saw_none_of_this_ones", ts.c2_answer_rows == 0 and ts.c2_replica_parts == 0,
            ts.c2_answer_rows .. " " .. ts.c2_replica_parts)
        T("S5_and_this_one_none_of_its", seen["0:other"] == nil and seen["0:config"] == nil)
        click(commands, button(world):id())
        step("opening")

    elseif phase == "opening" and #rows(world) > 0 then
        local v = view(world)
        local container = world:query({ with = { "sidebar/container" } })[1]
        T("U1_a_click_opens_a_plain_panel_in_the_container", count(world, "sidebar/file_browser/view") == 1
            and v:get("ChildOf") == container:id() and v:has("sidebar/panel"))
        T("U1_and_saves_it_open", me(world):get("sidebar/file_browser/state").open == true)
        T("U2_the_tree_says_listing_is_not_available_yet", #rows(world) == 1 and rows(world)[1].kind == "note"
            and rows(world)[1].name == "Listing isn't available yet", names_of(world))
        step("title")

    elseif phase == "title" and clock > 0.2 then
        T("U3_the_title_ends_the_loading_text", title_of(world) == "Files" and count(world, "sidebar/panel/loading") == 0,
            tostring(title_of(world)))
        click(commands, rows(world)[1].id)
        step("note_clicked")

    elseif phase == "note_clicked" and clock > 0.2 then
        T("U4_a_click_on_it_does_nothing", #rows(world) == 1 and next(me(world):get("sidebar/file_browser/state").expanded or {}) == nil)
        ts.made_up = true
        click(commands, world:query({ with = { "sidebar/file_browser/refresh" } })[1]:id())
        step("filling")

    -- From here the read answers made-up entries, for all a listing does on the client.
    elseif phase == "filling" and row_at(world, "zz_tree") ~= nil and clock > 0.2 then
        T("V1_folders_first", names_of(world) == "Alpha beta gone many sub upper apple Zeta zz_tree", names_of(world))
        T("V2_a_folder_is_marked_closed_a_file_with_its_size", rows(world)[1].mark == ">" and row_at(world, "apple").size == "1 B",
            tostring(rows(world)[1].mark) .. " " .. tostring(row_at(world, "apple").size))
        T("V3_the_note_is_gone", row_at(world, "") == nil)
        mark.first_writes = first_writes
        mark.first_id = rows(world)[1].id
        click(commands, row_at(world, "sub").id)
        step("expanding")

    elseif phase == "expanding" and row_at(world, "sub/inner") ~= nil and clock > 0.2 then
        local inner = row_at(world, "sub/inner")
        T("E1_a_click_opens_a_folder_under_it", inner.depth == 1 and row_at(world, "sub").mark == "v", tostring(inner.depth))
        T("E1_and_saves_it", (me(world):get("sidebar/file_browser/state").expanded or {}).sub == true)
        T("E2_a_row_above_it_is_not_rewritten", first_writes == mark.first_writes and rows(world)[1].id == mark.first_id,
            first_writes .. " " .. mark.first_writes)
        click(commands, row_at(world, "sub/inner").id)
        step("nested")

    elseif phase == "nested" and row_at(world, "sub/inner/deep") ~= nil then
        T("E3_a_folder_in_a_folder_opens_too", row_at(world, "sub/inner/deep").depth == 2)
        click(commands, row_at(world, "sub").id)
        step("collapsing")

    elseif phase == "collapsing" and row_at(world, "sub/inner") == nil and clock > 0.2 then
        T("E4_a_second_click_closes_it", row_at(world, "sub").mark == ">"
            and (me(world):get("sidebar/file_browser/state").expanded or {}).sub == nil)
        T("E4_taking_its_rows", #rows(world) == 9, tostring(#rows(world)))
        mark.reads = ts.reads
        click(commands, row_at(world, "sub").id)
        step("expanded_again")

    elseif phase == "expanded_again" and row_at(world, "sub/inner/deep") ~= nil then
        T("E5_opened_again_it_is_asked_for_again_and_what_was_open_in_it_stays", ts.reads > mark.reads)
        click(commands, row_at(world, "many").id)
        step("many_open")

    elseif phase == "many_open" and row_at(world, "many", "more") ~= nil and clock > 0.2 then
        local shown = 0
        for _, row in ipairs(rows(world)) do
            if row.path:sub(1, 5) == "many/" then shown = shown + 1 end
        end
        T("M1_a_big_folder_shows_a_page", shown == 50, tostring(shown))
        T("M1_then_a_row_for_more", row_at(world, "many", "more").name == "Load more...")
        click(commands, row_at(world, "many", "more").id)
        step("many_more")

    elseif phase == "many_more" and row_at(world, "many/f100") ~= nil and clock > 0.2 then
        T("M2_a_click_on_it_loads_the_next_page_after_the_last", row_at(world, "many/f051") ~= nil
            and row_at(world, "many/f101") == nil and row_at(world, "many", "more") ~= nil)
        local order_right = true
        local last = ""
        for _, row in ipairs(rows(world)) do
            if row.path:sub(1, 5) == "many/" and row.kind == "file" then
                order_right = order_right and row.path > last
                last = row.path
            end
        end
        T("M2_in_order", order_right)
        click(commands, row_at(world, "many").id)
        step("many_closed")

    elseif phase == "many_closed" and row_at(world, "many/f001") == nil and clock > 0.2 then
        click(commands, row_at(world, "gone").id)
        step("gone_open")

    elseif phase == "gone_open" and row_at(world, "gone/inside") ~= nil then
        ts.gone = true
        click(commands, world:query({ with = { "sidebar/file_browser/refresh" } })[1]:id())
        step("gone_refreshed")

    elseif phase == "gone_refreshed" and clock > 0.5 and row_at(world, "zz_tree") ~= nil then
        T("F1_a_folder_deleted_while_open_just_empties", row_at(world, "gone") ~= nil and row_at(world, "gone/inside") == nil, names_of(world))
        T("F1_its_state_stays", (me(world):get("sidebar/file_browser/state").expanded or {}).gone == true)
        T("F1_and_what_else_was_open_comes_back", row_at(world, "sub/inner/deep") ~= nil)
        refresh_at_read = true
        click(commands, row_at(world, "Alpha").id)
        step("refreshed_at_read")

    elseif phase == "refreshed_at_read" and not refresh_at_read and row_at(world, "Alpha/changed") ~= nil then
        T("Q4_a_folder_asked_again_as_its_answer_is_read_gets_a_new_one", row_at(world, "Alpha/file") == nil, names_of(world))
        mark.reloads, mark.button, mark.reads = reloads, button(world):id(), ts.reads
        reload(CLIENT_FILE)
        step("reloading")

    elseif phase == "reloading" and reloads > mark.reloads then
        step("reloaded")

    elseif phase == "reloaded" and clock > 2 and #rows(world) > 0 then
        T("H1_a_real_reload_leaves_one_new_button", count(world, "sidebar/file_browser/button") == 1
            and button(world):id() ~= mark.button)
        local kept, why = open_once(world)
        T("H2_its_own_reload_leaves_it_open_with_its_folders_expanded_and_one_of_everything", kept, why)
        T("H2_asking_the_server_again_for_them", ts.reads > mark.reads, ts.reads .. " " .. mark.reads)
        T("H2_its_icon_is_drawn_open", button(world):get("ui/style").background == "icon_active")
        click(commands, row_at(world, "sub/inner").id)
        step("after_reload_click")

    elseif phase == "after_reload_click" and row_at(world, "sub/inner/deep") == nil and clock > 0.2 then
        T("H3_after_it_a_click_on_a_row_works", (me(world):get("sidebar/file_browser/state").expanded or {})["sub/inner"] == nil)
        mark.reloads = reloads
        reload(PANEL_FILE)
        step("panel_reloading")

    elseif phase == "panel_reloading" and reloads > mark.reloads then
        step("panel_reloaded")

    elseif phase == "panel_reloaded" and clock > 2.5 then
        local kept, why = open_once(world)
        T("H5_a_reload_of_the_panel_brings_the_content_back_once", kept, why)
        mark.reloads = reloads
        mark.button = button(world):id()
        mark.container = world:query({ with = { "sidebar/container" } })[1]:id()
        reload(SIDEBAR_FILE)
        step("sidebar_reloading")

    elseif phase == "sidebar_reloading" and reloads > mark.reloads then
        step("sidebar_reloaded")

    elseif phase == "sidebar_reloaded" and clock > 2.5 then
        T("H6_a_reload_of_the_sidebar_gives_its_new_bar_one_new_button", count(world, "sidebar/file_browser/button") == 1
            and button(world):id() ~= mark.button)
        local kept, why = open_once(world)
        T("H6_and_leaves_the_panel_open_with_its_folders_expanded", kept, why)
        local container = world:query({ with = { "sidebar/container" } })[1]
        T("H6_in_the_new_container", count(world, "sidebar/container") == 1 and container:id() ~= mark.container
            and view(world):get("ChildOf") == container:id())
        mark.reloads = reloads
        reload(CLIENT_FILE, '["sidebar/panel"] = { title = "Files" }', '["sidebar/panel"] = { title = "Files zz" }')
        step("ui_changing")

    elseif phase == "ui_changing" and reloads > mark.reloads then
        step("ui_changed")

    elseif phase == "ui_changed" and clock > 2 then
        T("H7_a_change_to_the_mods_ui_shows_in_the_open_panel", title_of(world) == "Files zz", tostring(title_of(world)))
        local kept, why = open_once(world)
        T("H7_still_open_with_its_folders_expanded", kept, why)
        mark.reloads = reloads
        reload(CLIENT_FILE)
        step("ui_restoring")

    elseif phase == "ui_restoring" and reloads > mark.reloads then
        step("ui_restored")

    elseif phase == "ui_restored" and clock > 2 then
        T("H7_and_the_file_put_back_shows_too", title_of(world) == "Files", tostring(title_of(world)))
        reload(SERVER_FILE)
        step("server_reloading")

    elseif phase == "server_reloading" and clock > 2 then
        click(commands, row_at(world, "beta").id)
        step("after_server_reload")

    elseif phase == "after_server_reload" and row_at(world, "beta/file") ~= nil then
        T("H8_a_reload_of_the_server_half_loses_nothing", ts.carriers == 2 and ts.sync_listed == 2, ts.carriers .. " " .. ts.sync_listed)
        click(commands, button(world):id())
        step("user_closed")

    elseif phase == "user_closed" and count(world, "sidebar/file_browser/view") == 0 and clock > 0.2 then
        T("K4_closing_takes_the_view_and_all_in_it", count(world, "sidebar/file_browser/row") == 0 and count(world, "sidebar/panel/scroll") == 0)
        T("K4_and_saves_it_closed", me(world):get("sidebar/file_browser/state").open == false)
        mark.reloads = reloads
        mark.button = button(world):id()
        reload(CLIENT_FILE)
        step("user_closed_reloading")

    elseif phase == "user_closed_reloading" and reloads > mark.reloads then
        step("user_closed_reloaded")

    elseif phase == "user_closed_reloaded" and clock > 1.5 and button(world) ~= nil then
        T("K5_closed_it_stays_closed_through_a_reload", button(world):id() ~= mark.button
            and not button(world):has("sidebar/button/open") and count(world, "sidebar/file_browser/view") == 0
            and me(world):get("sidebar/file_browser/state").open == false)
        T("K5_keeping_its_folders_for_next_time", (me(world):get("sidebar/file_browser/state").expanded or {}).sub == true)
        click(commands, button(world):id())
        step("reopen")

    elseif phase == "reopen" and row_at(world, "sub/inner") ~= nil then
        T("K6_opened_again_its_folders_are_expanded", me(world):get("sidebar/file_browser/state").open == true)
        ts.made_up = false
        click(commands, world:query({ with = { "sidebar/file_browser/refresh" } })[1]:id())
        step("back_to_the_stub")

    elseif phase == "back_to_the_stub" and row_at(world, "zz_tree") == nil and #rows(world) == 1 and clock > 0.2 then
        T("K7_with_reading_not_available_the_state_stays", rows(world)[1].kind == "note"
            and (me(world):get("sidebar/file_browser/state").expanded or {}).sub == true, names_of(world))
        commands:entity(me(world):id()):remove("sidebar")
        step("sidebar_gone")

    elseif phase == "sidebar_gone" and clock > 0.5 then
        T("B3_the_sidebar_gone_takes_button_and_view", count(world, "sidebar/file_browser/button") == 0
            and count(world, "sidebar/file_browser/view") == 0 and count(world, "sidebar/file_browser/row") == 0)
        commands:entity(me(world):id()):patch({ sidebar = {} })
        step("sidebar_back")

    elseif phase == "sidebar_back" and clock > 1 and button(world) ~= nil then
        T("B4_a_new_bar_gets_one_new_button_closed", count(world, "sidebar/file_browser/button") == 1
            and count(world, "sidebar/file_browser/view") == 0
            and (me(world):get("sidebar/file_browser/state") or {}).open == false)
        click(commands, button(world):id())
        step("removal_open")

    elseif phase == "removal_open" and #rows(world) > 0 then
        ts.drop_carrier = true
        step("removed")

    elseif phase == "removed" and clock > 1.5 then
        local names = {
            "sidebar/file_browser", "sidebar/file_browser/state", "sidebar/file_browser/request", "sidebar/file_browser/answer",
            "sidebar/file_browser/button", "sidebar/file_browser/view", "sidebar/file_browser/row", "sidebar/file_browser/rows",
            "sidebar/file_browser/refresh", "sidebar/file_browser/mark", "sidebar/file_browser/name", "sidebar/file_browser/size",
            "sidebar/panel",
        }
        local left = {}
        for _, name in ipairs(names) do
            if count(world, name) > 0 then left[#left + 1] = name end
        end
        T("Z1_the_server_taking_it_off_leaves_nothing_here", #left == 0, table.concat(left, " "))
        T("Z2_nor_a_sync_entry_there", ts.carriers == 0 and ts.sync_listed == 0, ts.carriers .. " " .. ts.sync_listed)
        local script_left = false
        for _, row in ipairs(world:query({ with = { "core/script" } })) do
            local entry = row:get("core/script").entry
            if type(entry) == "string" and entry:find("sidebar/file_browser", 1, true) then script_left = true end
        end
        T("Z3_its_script_stopped", not script_left)
        phase = "done"
        finish()
    end

    if phase ~= "done" and clock > 25 then
        T("Z_reached_" .. phase, false, "stuck in phase '" .. phase .. "': " .. names_of(world))
        phase = "done"
        finish()
    end
end):in_set("zz/fb_suite"):after("sidebar/file_browser/render")
