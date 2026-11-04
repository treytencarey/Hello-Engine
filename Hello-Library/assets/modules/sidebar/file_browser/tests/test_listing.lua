-- The listing's stateless functions with made-up entries, and the mod's files against the rule that
-- no file access is in them.
require("modules/core/init.lua")
local helpers = require("modules/core/test_helpers.lua")
local Listing = require("modules/sidebar/file_browser/server/listing.lua")

local suite = helpers.create_suite("FileBrowserListingSuite")
local T = suite.assert_test

local function names(entries)
    local out = {}
    for _, entry in ipairs(entries) do out[#out + 1] = entry.name end
    return table.concat(out, " ")
end

local function entries(...)
    local out = {}
    for _, name in ipairs({ ... }) do out[#out + 1] = { name = name, is_dir = false, size = 1 } end
    return out
end

app:add_systems(Startup, {}, function()
    for _, name in ipairs({
        "config", "CONFIG", "Config", "config.", "config ", "config. .", "deploy_keys", "DEPLOY_KEYS", "deploy_keys.",
        "gateways", "GateWays", "gateways ", ".env", ".ENV", ".hidden", "..", ".", "...", ". .", " ", "", "deploy~1", "DEPLOY~1",
    }) do
        T("N1_private_" .. name, Listing.is_private(name))
    end
    for _, name in ipairs({ "config2", "myconfig", "gateway", "deploy_key", "a.b", "a..b", "readme.txt", "x~y", "e" }) do
        T("N2_not_private_" .. name, not Listing.is_private(name))
    end
    T("V1_visible_drops_only_the_private_names",
        names(Listing.visible(entries("a.txt", "CONFIG", ".env", "b", "Gateways.", "deploy_keys", "c"))) == "a.txt b c")

    local mixed = {
        { name = "zeta.txt", is_dir = false, size = 1 },
        { name = "Beta", is_dir = true, size = 0 },
        { name = "Apple.txt", is_dir = false, size = 1 },
        { name = "alpha", is_dir = true, size = 0 },
        { name = "beta.txt", is_dir = false, size = 1 },
    }
    T("S1_folders_first_then_by_name_ignoring_case", names(Listing.sorted(mixed)) == "alpha Beta Apple.txt beta.txt zeta.txt", names(mixed))
    T("S2_two_names_differing_only_in_case_keep_one_order",
        names(Listing.sorted(entries("a", "A"))) == "A a" and names(Listing.sorted(entries("A", "a"))) == "A a")

    local many = {}
    for i = 1, 5 do many[i] = { name = "f" .. i, is_dir = i == 1, size = i } end
    local first = Listing.page(many, "sub", 0, 2)
    T("G1_a_page_starts_at_the_top", names(first.files) == "f1 f2" and first.offset == 0 and first.has_more == true and first.total_count == 5)
    T("G2_its_entries_are_relative_to_the_top", first.files[1].path == "sub/f1" and first.files[1].is_directory == true and first.files[2].size == 2)
    local top = Listing.page(many, "", 0, 1)
    T("G3_a_top_entry_is_its_name", top.files[1].path == "f1" and top.path == "")
    local middle = Listing.page(many, "sub", 2, 2)
    T("G4_a_page_starts_at_its_offset", names(middle.files) == "f3 f4" and middle.has_more == true)
    local last = Listing.page(many, "sub", 4, 2)
    T("G5_the_last_says_none_follow", names(last.files) == "f5" and last.has_more == false)
    local exact = Listing.page(many, "sub", 3, 2)
    T("G6_a_page_ending_at_the_end_says_none_follow", names(exact.files) == "f4 f5" and exact.has_more == false)
    local past = Listing.page(many, "sub", 9, 2)
    T("G7_a_page_past_the_end_is_empty", #past.files == 0 and past.has_more == false and past.total_count == 5)
    local none = Listing.page({}, "gone", 0, 2)
    T("G8_nothing_pages_as_nothing", #none.files == 0 and none.has_more == false and none.total_count == 0)

    local read, why = Listing.read("anywhere", "sub")
    T("R1_reading_is_not_available_yet", read == nil and why == "not available", tostring(why))

    -- By the word and not by the call: a local alias of either table holds the same word.
    for _, file in ipairs({ "server/init.lua", "server/listing.lua", "client/init.lua", "shared/init.lua" }) do
        local source = read_file_bytes("assets/modules/sidebar/file_browser/" .. file)
        T("F1_no_file_access_in_" .. file, source ~= nil and #source > 0
            and not source:find("%f[%w_]os%f[^%w_]") and not source:find("%f[%w_]io%f[^%w_]"))
    end
    suite.finish("FILE_BROWSER_LISTING")
end)
