-- The client half of the "GitHub" sidebar panel: the player's repositories and a repository's
-- branches, asked of root, with Switch to move to a branch's world, Portal to ask the world's server
-- for a portal to it, Pull on this world's own branch, and the branch's latest commits. Root holds
-- the token and makes every GitHub call; the panel asks root and shows only what root answers. A
-- repository the Hello Engine app isn't installed on offers Install, and the REPOSITORY picker
-- "+ Add a repository…": both ask root's `vault/open_url` for root's install page. A read the player
-- denied says so, and is asked again only on a new choice or a new panel.
-- `git/panel` arrives from the server, on the owner's own player only; the state and the UI this
-- half adds stay on this client.
--
-- git/panel = {}
--
-- git/panel/state = {
--     open = <whether the panel is open>,
--     repo = <the chosen repository, "<owner>/<name>">,
--     branch = <the chosen branch>,
--     folder = <the folder the player typed, the world's place in the repository; nil for its top>,
--     typing = <true while the folder field is open>,
-- }
--
-- git/panel/button = {}
-- git/panel/view = {}
-- git/panel/row = {}
--
-- git/panel/request and git/panel/response: the ask this half writes and the server's answer, laid
-- out in the server half.

local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local Scroll = require("bevy::picking::prelude::Scroll")
local Time = require("bevy::time::Time")
local KeyboardInput = require("bevy::input::keyboard::KeyboardInput")
local MessageReader = require("bevy::prelude").MessageReader

-- How long an armed despawn waits for its second click, and how long a refusal stays on its row.
local ARM_SECONDS = 5
local REFUSAL_SECONDS = 10

-- Core's canonical form lowercases the owner and the name, and keeps the folder and the branch as
-- they are. A world in a folder of its repository is named by that folder: without it, the target
-- is the repository's top, which may hold no world.
local function scope_of(repo, branch, folder)
    local sub = (tostring(folder or ""):gsub("^/+", ""):gsub("/+$", ""))
    return "github:" .. repo:lower() .. (sub ~= "" and ("/" .. sub) or "") .. ":" .. branch
end

-- The folder row's text; while the field is open, the text being typed and a cursor.
local function folder_text(folder, typing, draft)
    if typing then return "Folder: " .. (draft or folder or "") .. "_" end
    return "Folder: " .. ((folder ~= nil and folder ~= "") and folder or "(root)")
end

local function split(repo)
    if repo == nil then return nil end
    return repo:match("^([^/]+)/(.+)$")
end

-- A canonical key, `github:<owner>/<name>[/<folder>]:<branch>`, read back: the owner and the name
-- lowered as core writes them, the folder and the branch as they are. Nil for any other key.
local function parse_scope(key)
    if type(key) ~= "string" then return nil end
    local path, branch = key:match("^github:([^:]+):(.+)$")
    if path == nil then return nil end
    local owner, name, folder = path:match("^([^/]+)/([^/]+)/?(.*)$")
    if owner == nil then return nil end
    return { owner = owner:lower(), name = name:lower(), folder = folder ~= "" and folder or nil, branch = branch }
end

-- The base repository first, when root names one; the rest in GitHub's order, most recently
-- updated first.
local function listed(repos)
    local out = {}
    for _, r in ipairs(repos) do
        if r.is_base == true and r.owner ~= nil then out[#out + 1] = r end
    end
    for _, r in ipairs(repos) do
        if r.is_base ~= true and r.owner ~= nil then out[#out + 1] = r end
    end
    return out
end

-- The standing sign-in ask hangs under the repositories ask, not the carrier: a standing
-- `vault/github/signin` among the carrier's children is `sidebar/profile`'s.
local function ask_repos(commands, carrier)
    local repos = commands:spawn({
        ["vault/github/repos"] = {},
        Request = {},
        ["core/script/owner"] = false,
        ChildOf = carrier,
    }):id()
    commands:spawn({
        ["vault/github/signin"] = {},
        Request = {},
        ["core/script/owner"] = false,
        ChildOf = repos,
    })
end

local function ask_sessions(commands, carrier)
    commands:spawn({
        ["core/registry/sessions"] = {},
        Request = {},
        ["core/script/owner"] = false,
        ChildOf = carrier,
    })
end

-- A row's scope as it reads: without `github:`, cut to 24 characters.
local function short(scope)
    local label = (tostring(scope):gsub("^github:", ""))
    if #label > 24 then label = label:sub(1, 21) .. "..." end
    return label
end

-- A row's component, or nil when the query names it optional and the row has none.
local function opt(e, name)
    return e:has(name) and e:get(name) or nil
end

-- Each refusal in the row's own words.
local function despawn_refused(reason)
    return "⚠ despawn refused: " .. tostring(reason)
end
local function stop_refused(reason)
    if reason == "playing" then return "⚠ can't stop the world you are in: switch first" end
    if reason == "watched" then return "⚠ can't stop it: a portal looks at it" end
    if reason == "not-held" then return "⚠ can't stop it: this PC doesn't hold it" end
    return "⚠ stop refused: " .. tostring(reason)
end
local function restart_refused(reason)
    if reason == "not-held" then return "⚠ can't restart it: this PC doesn't hold it" end
    return "⚠ restart refused: " .. tostring(reason)
end

local function ask_branches(commands, carrier, owner, name)
    commands:spawn({
        ["vault/github/branches"] = { owner = owner, name = name },
        Request = {},
        ["core/script/owner"] = false,
        ChildOf = carrier,
    })
end

local function ask_commits(commands, carrier, owner, name, branch)
    commands:spawn({
        ["vault/github/commits"] = { owner = owner, name = name, branch = branch },
        Request = {},
        ["core/script/owner"] = false,
        ChildOf = carrier,
    })
end

-- An answer root gave while signed out is stale once signed in, and one it gave signed in is stale
-- once signed out. A read the player denied, or one root says the app can't make, is no signed-out
-- answer: it is asked again only on a new choice or a new panel.
local function stale(said, reply)
    if reply ~= nil and (reply.error == "denied" or reply.reason ~= nil) then return false end
    return reply ~= nil and (said.login ~= nil) == (reply.error ~= nil)
end

-- Root's install page for the Hello Engine app, through root's `vault/open_url`, whose dialog shows
-- the player the address before anything opens. A click closes an earlier ask root hasn't answered
-- and opens one in its place.
local function ask_open(commands, carrier, url, earlier)
    for _, ask in ipairs(earlier) do
        commands:entity(ask:id()):despawn()
    end
    commands:spawn({
        ["vault/open_url"] = { url = url },
        Request = {},
        ["core/script/owner"] = false,
        ChildOf = carrier,
    })
end

local ADD_REPOSITORY = "+ Add a repository…"
local DENIED = "GitHub access not allowed"
local function not_installed(repo)
    return "⚠ the Hello Engine app isn't installed on " .. tostring(repo)
end

local function close(nodes, arrows, picker)
    for _, list in ipairs(nodes:iter_many_mut({ picker.list })) do
        list:get_mut("Node").display = "None"
    end
    for _, arrow in ipairs(arrows:iter_many_mut({ picker.arrow })) do
        arrow:get_mut("Text"):set_if_neq("▼")
    end
end

-- A picker: its label, the button showing the choice, and the options under it, shown only while
-- the picker is open. Whether it is open lives on the list and its arrow, so a click opens or
-- closes it without a rebuild, and a rebuild reads the arrow back to keep it as it was.
local function spawn_picker(commands, scroll, label, chosen, open, options)
    local block = commands:spawn({
        ["git/panel/row"] = {},
        Node = { width = { Percent = 100 }, flex_direction = "Column", flex_shrink = 0 },
        ChildOf = scroll,
    }):id()
    commands:spawn({
        Text = { text = label },
        TextFont = { font_size = 10 },
        Node = { margin = { top = { Px = 8 }, bottom = { Px = 4 } } },
        ["ui/style"] = { text = "text_dim" },
        ChildOf = block,
    })
    local trigger = commands:spawn({
        Button = {},
        Node = {
            width = { Percent = 100 },
            height = { Px = 30 },
            flex_direction = "Row",
            align_items = "Center",
            justify_content = "SpaceBetween",
            padding = { left = { Px = 8 }, right = { Px = 8 } },
            border = { left = { Px = 1 }, right = { Px = 1 }, top = { Px = 1 }, bottom = { Px = 1 } },
        },
        BorderRadius = {
            top_left = { Px = 4 }, top_right = { Px = 4 },
            bottom_left = { Px = 4 }, bottom_right = { Px = 4 },
        },
        ["ui/style"] = { background = "row_bg", hover = "row_hover", border = "border" },
        ChildOf = block,
    }):id()
    commands:spawn({
        Text = { text = chosen or "(none)" },
        TextFont = { font_size = 12 },
        ["ui/style"] = { text = chosen ~= nil and "text" or "text_dim" },
        ChildOf = trigger,
    })
    local arrow = commands:spawn({
        Text = { text = open and "▲" or "▼" },
        TextFont = { font_size = 10 },
        ["ui/style"] = { text = "text_dim" },
        ChildOf = trigger,
    }):id()
    local list = commands:spawn({
        Node = {
            display = open and "Flex" or "None",
            width = { Percent = 100 },
            flex_direction = "Column",
            max_height = { Px = 180 },
            overflow = { x = "Visible", y = "Scroll" },
            border = { left = { Px = 1 }, right = { Px = 1 }, bottom = { Px = 1 } },
        },
        ScrollPosition = { x = 0, y = 0 },
        ["ui/style"] = { background = "bg", border = "border" },
        ChildOf = block,
    })
    -- The wheel scrolls the list, not the panel under it as well. `ScrollPosition` is written whole:
    -- a field set on its working copy is dropped.
    list:observe(On[Pointer[Scroll]], {
        Query[{
            with = { Mut["ScrollPosition"] },
            optional = { "ComputedNode" },
        }],
    }, function(event, lists)
        event:propagate(false)
        for _, l in ipairs(lists:iter_many_mut({ event.entity })) do
            local node = l:get("ComputedNode")
            local room = node and math.max(0, node.content_size.y - node.size.y) or 0
            local at = l:get("ScrollPosition").y
            l:get_mut("ScrollPosition"):set_if_neq({ x = 0, y = math.max(0, math.min(room, at - event.event.y * 20)) })
        end
    end)
    local picks = {}
    for _, option in ipairs(options) do
        local row = commands:spawn({
            Button = not option.selected and {} or nil,
            Node = {
                width = { Percent = 100 },
                height = { Px = 26 },
                flex_shrink = 0,
                align_items = "Center",
                padding = { left = { Px = 8 }, right = { Px = 8 } },
            },
            ["ui/style"] = option.selected and { background = "row_selected" } or { background = "row_bg", hover = "row_hover" },
            ChildOf = list:id(),
        }):id()
        commands:spawn({
            Text = { text = option.text },
            TextFont = { font_size = 11 },
            ["ui/style"] = { text = option.selected and "text" or "text_dim" },
            ChildOf = row,
        })
        if not option.selected then
            picks[#picks + 1] = { button = row, value = option.value, open = option.open }
        end
    end
    return { trigger = trigger, arrow = arrow, list = list:id(), picks = picks }
end

local function spawn_action(commands, row, text, live, dim, width)
    local button = commands:spawn({
        Button = {},
        Node = {
            flex_grow = width == nil and 1 or 0,
            width = width ~= nil and { Px = width } or "Auto",
            height = { Px = 32 },
            justify_content = "Center",
            align_items = "Center",
            border = { left = { Px = 1 }, right = { Px = 1 }, top = { Px = 1 }, bottom = { Px = 1 } },
        },
        BorderRadius = {
            top_left = { Px = 4 }, top_right = { Px = 4 },
            bottom_left = { Px = 4 }, bottom_right = { Px = 4 },
        },
        ["ui/style"] = live and { background = "icon_bg", hover = "icon_hover", border = "border" }
            or { background = "row_alt", border = "border" },
        ChildOf = row,
    })
    commands:spawn({
        Text = { text = text },
        TextFont = { font_size = 12 },
        ["ui/style"] = { text = dim and "text_dim" or "text" },
        ChildOf = button:id(),
    })
    return button
end

-- A new carrier gets its state, if it has none, and its standing ask for the player's
-- repositories, if it has none. The asks outlive a reload of this mod, and a reload re-fires this
-- edge: the state and the asks already there stay.
app:add_systems(First, {
    Query[{
        added = { "git/panel" },
        optional = { "git/panel/state", "Children" },
    }],
    Query[{ with = { "vault/github/repos", "Request" } }],
    Query[{ with = { "core/registry/sessions", "Request" } }],
    Commands,
}, function(carriers, asks, sessions, commands)
    for _, e in ipairs(carriers:iter()) do
        if not e:has("git/panel/state") then
            commands:entity(e:id()):insert({ ["git/panel/state"] = { open = false } })
        end
        if asks:iter_many(e:get("Children") or {})[1] == nil then
            ask_repos(commands, e:id())
        end
        if sessions:iter_many(e:get("Children") or {})[1] == nil then
            ask_sessions(commands, e:id())
        end
    end
end):in_set("git/panel")

-- `git/panel` taken off an entity that stays: its asks close. A despawned carrier takes its children
-- itself. The flip asks and pulls it spawned are the player's, and stay.
app:add_systems(First, {
    Query[{
        removed = { "git/panel" },
        optional = { "Children" },
    }],
    Query[{
        any_of = {
            "vault/github/repos", "vault/github/branches", "vault/github/commits", "vault/open_url",
            "core/registry/sessions", "core/registry/despawn", "core/world/unload", "core/world/restart",
        },
        with = { "Request" },
    }],
    Commands,
}, function(removed, asks, commands)
    for _, e in ipairs(removed:iter()) do
        for _, ask in ipairs(asks:iter_many(e:get("Children") or {})) do
            commands:entity(ask:id()):try_despawn()
        end
    end
end):in_set("git/panel")

-- The server's answer to an ask on `git/panel/request` stands until the ask is taken back. Taking it
-- back here makes the next ask a change, even one asking the same.
app:add_systems(Update, {
    Query[{
        changed = { "git/panel/response" },
        with = { "git/panel", "core/net/owner" },
    }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(answered, own, commands)
    for _, e in ipairs(answered:iter()) do
        if own:contains(e:get("core/net/owner")) and e:get("git/panel/response").op ~= nil then
            commands:entity(e:id()):insert({ ["git/panel/request"] = {} })
        end
    end
end):in_set("git/panel")

-- A row's ask answered: `done` closes it (root lists the sessions again at once after a despawn),
-- and a refusal stays on its row for REFUSAL_SECONDS from here.
app:add_systems(Update, {
    Res[Time],
    Query[{
        ["or"] = {
            added = { "core/registry/despawn/reply", "core/world/unload/reply", "core/world/restart/reply" },
            changed = { "core/registry/despawn/reply", "core/world/unload/reply", "core/world/restart/reply" },
        },
        with = { "Request", "ChildOf" },
        optional = {
            "core/registry/despawn", "core/world/unload", "core/world/restart",
            "core/registry/despawn/reply", "core/world/unload/reply", "core/world/restart/reply",
        },
    }],
    Query[{ with = { "git/panel", Mut["git/panel/state"] } }],
    Commands,
}, function(time, answered, carriers, commands)
    for _, ask in ipairs(answered:iter()) do
        local carrier = carriers:iter_many_mut({ ask:get("ChildOf") })[1]
        local wish = opt(ask, "core/registry/despawn") or opt(ask, "core/world/unload") or opt(ask, "core/world/restart")
        local said = opt(ask, "core/registry/despawn/reply") or opt(ask, "core/world/unload/reply")
            or opt(ask, "core/world/restart/reply")
        if carrier ~= nil and wish ~= nil and said ~= nil then
            if said.status == "done" then
                commands:entity(ask:id()):despawn()
            elseif said.status == "refused" then
                local refused = {}
                for scope, at in pairs(carrier:get("git/panel/state").refused or {}) do refused[scope] = at end
                refused[wish.scope] = time:elapsed_secs()
                carrier:get_mut("git/panel/state").refused = refused
            end
        end
    end
end):in_set("git/panel")

-- An install ask answered, opened or refused: root's dialog has gone, and the ask closes.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            added = { "vault/open_url/reply" },
            changed = { "vault/open_url/reply" },
        },
        with = { "vault/open_url", "Request", "ChildOf" },
    }],
    Query[{ with = { "git/panel" } }],
    Commands,
}, function(answered, carriers, commands)
    for _, ask in ipairs(answered:iter()) do
        if carriers:contains(ask:get("ChildOf")) then
            commands:entity(ask:id()):despawn()
        end
    end
end):in_set("git/panel")

-- The two deadlines on the state: an arm lapses after ARM_SECONDS, and a refusal's ask goes after
-- REFUSAL_SECONDS, taking its row's line with it.
app:add_systems(Update, {
    Res[Time],
    Query[{ with = { "git/panel", Mut["git/panel/state"] }, optional = { "Children" } }],
    Query[{
        any_of = { "core/registry/despawn", "core/world/unload", "core/world/restart" },
        with = { "Request" },
        optional = {
            "core/registry/despawn", "core/world/unload", "core/world/restart",
            "core/registry/despawn/reply", "core/world/unload/reply", "core/world/restart/reply",
        },
    }],
    Commands,
}, function(time, carriers, asks, commands)
    local now = time:elapsed_secs()
    for _, carrier in ipairs(carriers:iter_mut()) do
        local s = carrier:get("git/panel/state")
        if s.armed ~= nil and now - s.armed.at > ARM_SECONDS then
            carrier:get_mut("git/panel/state").armed = nil
        end
        local kept, gone = {}, nil
        for scope, at in pairs(s.refused or {}) do
            if now - at >= REFUSAL_SECONDS then
                gone = gone or {}
                gone[scope] = true
            else
                kept[scope] = at
            end
        end
        if gone ~= nil then
            for _, ask in ipairs(asks:iter_many(carrier:get("Children") or {})) do
                local wish = opt(ask, "core/registry/despawn") or opt(ask, "core/world/unload") or opt(ask, "core/world/restart")
                local said = opt(ask, "core/registry/despawn/reply") or opt(ask, "core/world/unload/reply")
                    or opt(ask, "core/world/restart/reply")
                if gone[wish.scope] and said ~= nil and said.status == "refused" then
                    commands:entity(ask:id()):despawn()
                end
            end
            carrier:get_mut("git/panel/state").refused = kept
        end
    end
end):in_set("git/panel"):run_if({
    Query[{ with = { "git/panel/state" } }],
}, function(states)
    for _, row in ipairs(states:iter()) do
        local s = row:get("git/panel/state")
        if s.armed ~= nil or next(s.refused or {}) ~= nil then return true end
    end
    return false
end)

-- An ask for a choice moved on from is closed, which stops root's call for it.
app:add_systems(Update, {
    Query[{
        with = { "git/panel", Mut["git/panel/state"] },
        optional = { "Children" },
    }],
    Query[{
        with = { "vault/github/repos", "Request" },
        optional = { "vault/github/repos/reply" },
    }],
    Query[{
        with = { "vault/github/branches", "Request" },
        optional = { "vault/github/branches/reply" },
    }],
    Query[{ with = { "vault/github/commits", "Request" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(carriers, repo_asks, branch_asks, commit_asks, statuses, commands)
    -- The defaults are this world's own repository, folder and branch, so the panel opens on the
    -- world the player stands in; until this world's row is here, nothing is chosen.
    local me = statuses:iter()[1]
    local here = me and parse_scope(me:get("core/world/status").scope_key)
    for _, carrier in ipairs(carriers:iter_mut()) do
        local kids = carrier:get("Children") or {}
        local state = carrier:get_mut("git/panel/state")
        local answered = repo_asks:iter_many(kids)[1]
        local said = answered and answered:has("vault/github/repos/reply") and answered:get("vault/github/repos/reply")
        local options = said and said.repos and listed(said.repos) or {}
        -- Only this world's own repository is chosen for the player: any other would be asked for
        -- its branches unbidden, a read of a repository the player never picked. With it not listed,
        -- none is chosen until the player picks one.
        if state.repo == nil and here ~= nil then
            for _, r in ipairs(options) do
                if r.owner:lower() == here.owner and tostring(r.name):lower() == here.name then
                    state.repo = r.owner .. "/" .. r.name
                    state.folder = here.folder
                    break
                end
            end
        end

        local owner, name = split(state.repo)
        local kept = nil
        for _, ask in ipairs(branch_asks:iter_many(kids)) do
            local wish = ask:get("vault/github/branches")
            if kept == nil and owner ~= nil and wish.owner == owner and wish.name == name then
                kept = ask
            else
                commands:entity(ask:id()):despawn()
            end
        end
        if owner ~= nil and kept == nil then
            ask_branches(commands, carrier:id(), owner, name)
        end
        local branches = kept and kept:has("vault/github/branches/reply") and kept:get("vault/github/branches/reply").branches
        if state.branch == nil and branches and branches[1] ~= nil then
            local mine = here ~= nil and owner:lower() == here.owner and name:lower() == here.name
            state.branch = mine and here.branch or branches[1]
        end

        local branch = state.branch
        kept = nil
        for _, ask in ipairs(commit_asks:iter_many(kids)) do
            local wish = ask:get("vault/github/commits")
            if kept == nil and owner ~= nil and wish.owner == owner and wish.name == name and wish.branch == branch then
                kept = ask
            else
                commands:entity(ask:id()):despawn()
            end
        end
        if owner ~= nil and branch ~= nil and kept == nil then
            ask_commits(commands, carrier:id(), owner, name, branch)
        end
    end
end):in_set("git/panel"):run_if({
    Query[{
        ["or"] = {
            added = { "git/panel/state", "core/world/status" },
            changed = { "git/panel/state", "vault/github/repos/reply", "vault/github/branches/reply", "core/world/status" },
        },
    }],
}, function(touched)
    return not touched:is_empty()
end)

-- Root answers each ask once. When the player signs in or out, in the Accounts panel or anywhere,
-- the answers given the other way are asked again.
app:add_systems(Update, {
    Query[{
        changed = { "vault/github/signin/reply" },
        with = { "vault/github/signin", "Request", "ChildOf" },
    }],
    Query[{
        with = { "vault/github/repos", "Request", "ChildOf" },
        optional = { "vault/github/repos/reply" },
    }],
    Query[{
        with = { "git/panel" },
        optional = { "Children" },
    }],
    Query[{
        with = { "vault/github/branches", "Request" },
        optional = { "vault/github/branches/reply" },
    }],
    Query[{
        with = { "vault/github/commits", "Request" },
        optional = { "vault/github/commits/reply" },
    }],
    Commands,
}, function(signins, repo_asks, carriers, branch_asks, commit_asks, commands)
    for _, s in ipairs(signins:iter()) do
        local said = s:get("vault/github/signin/reply")
        local repos = repo_asks:get(s:get("ChildOf"))
        local carrier = repos and carriers:get(repos:get("ChildOf"))
        if carrier ~= nil then
            local kids = carrier:get("Children") or {}
            if stale(said, repos:has("vault/github/repos/reply") and repos:get("vault/github/repos/reply") or nil) then
                commands:entity(repos:id()):despawn()
                ask_repos(commands, carrier:id())
            end
            for _, ask in ipairs(branch_asks:iter_many(kids)) do
                if stale(said, ask:has("vault/github/branches/reply") and ask:get("vault/github/branches/reply") or nil) then
                    local wish = ask:get("vault/github/branches")
                    commands:entity(ask:id()):despawn()
                    ask_branches(commands, carrier:id(), wish.owner, wish.name)
                end
            end
            for _, ask in ipairs(commit_asks:iter_many(kids)) do
                if stale(said, ask:has("vault/github/commits/reply") and ask:get("vault/github/commits/reply") or nil) then
                    local wish = ask:get("vault/github/commits")
                    commands:entity(ask:id()):despawn()
                    ask_commits(commands, carrier:id(), wish.owner, wish.name, wish.branch)
                end
            end
        end
    end
end):in_set("git/panel"):run_if({
    Query[{ changed = { "vault/github/signin/reply" } }],
}, function(changed)
    return not changed:is_empty()
end)

-- The button is in the bar only while the player is signed in to GitHub, as root answers the
-- panel's sign-in ask; before root has answered, nothing changes, so a re-ask doesn't flicker it.
-- It comes on a new bar (the sidebar built or reloaded), on the panel itself (added, or this mod
-- reloaded) and on a sign-in. A sign-out takes it, and the panel with it: with its button gone, the
-- panel could not be closed.
app:add_systems(Update, {
    Query[{
        with = { "git/panel", Mut["git/panel/state"] },
        optional = { "Children" },
    }],
    Query[{
        with = { "vault/github/repos", "Request" },
        optional = { "Children" },
    }],
    Query[{ with = { "vault/github/signin", "vault/github/signin/reply", "Request" } }],
    Query[{ with = { "sidebar/bar" } }],
    Query[{ with = { "git/panel/button" } }],
    Query[{ with = { "git/panel/view" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Commands,
}, function(carriers, repo_asks, signins, bars, buttons, views, own, commands)
    local bar = bars:iter()[1]
    for _, n in ipairs(own:iter()) do
        for _, carrier in ipairs(carriers:iter_many_mut(n:get("core/net/owns"))) do
            local repos = repo_asks:iter_many(carrier:get("Children") or {})[1]
            local said = repos and signins:iter_many(repos:get("Children") or {})[1]
            local login = said and said:get("vault/github/signin/reply").login
            if said and login ~= nil and bar ~= nil and buttons:is_empty() then
                commands:spawn({
                    ["sidebar/button"] = { icon = "icons/github.png", title = "GitHub", order = 3 },
                    ["git/panel/button"] = {},
                    ChildOf = bar:id(),
                })
            elseif said and login == nil then
                for _, b in ipairs(buttons:iter()) do
                    commands:entity(b:id()):despawn()
                end
                for _, view in ipairs(views:iter()) do
                    commands:entity(view:id()):despawn()
                end
                if carrier:get("git/panel/state").open then
                    local s = carrier:get_mut("git/panel/state")
                    s.open, s.typing = false, nil
                end
            end
        end
    end
end):in_set("git/panel"):run_if({
    Query[{ added = { "sidebar/bar" } }],
    Query[{
        ["or"] = {
            added = { "git/panel", "core/net/owner" },
            changed = { "core/net/owner" },
        },
        with = { "git/panel", "core/net/owner" },
    }],
    Query[{ changed = { "vault/github/signin/reply" } }],
}, function(new_bars, new_carriers, signins)
    return not new_bars:is_empty() or not new_carriers:is_empty() or not signins:is_empty()
end)

-- A new button that was open before a reload opens again, by the path a click takes. It waits for the
-- sidebar to make it an icon: an icon drawn active reacts to `sidebar/button/open` on a node.
app:add_systems(Update, {
    Query[{
        added = { "Node" },
        with = { "git/panel/button" },
    }],
    Query[{ with = { "git/panel", "git/panel/state" } }],
    Query[{ with = { "sidebar/button/open" } }],
    Commands,
}, function(icons, carriers, open_buttons, commands)
    for _, icon in ipairs(icons:iter()) do
        local carrier = carriers:iter()[1]
        local state = carrier and carrier:get("git/panel/state")
        if state ~= nil and state.open then
            local order = 0
            for _, o in ipairs(open_buttons:iter()) do
                local opened = o:get("sidebar/button/open")
                order = math.max(order, opened.order)
            end
            commands:entity(icon:id()):insert({ ["sidebar/button/open"] = { order = order + 1 } })
        end
    end
end):in_set("git/panel")

app:add_systems(Update, {
    Query[{
        added = { "sidebar/button/open" },
        with = { "git/panel/button" },
    }],
    Query[{ with = { "sidebar/container" } }],
    Query[{ with = { "git/panel", Mut["git/panel/state"] }, optional = { "Children" } }],
    Query[{
        any_of = { "vault/github/repos", "vault/github/branches", "vault/github/commits" },
        with = { "Request" },
        optional = {
            "vault/github/branches", "vault/github/commits",
            "vault/github/repos/reply", "vault/github/branches/reply", "vault/github/commits/reply",
        },
    }],
    Commands,
}, function(opened, containers, carriers, reads, commands)
    for _, _ in ipairs(opened:iter()) do
        local container = containers:iter()[1]
        local carrier = carriers:iter_mut()[1]
        if container ~= nil and carrier ~= nil then
            commands:spawn({
                ["sidebar/panel"] = { width = 280 },
                ["git/panel/view"] = {},
                ChildOf = container:id(),
            })
            -- A new panel asks again what the player denied, each in its ask's place.
            for _, ask in ipairs(reads:iter_many(carrier:get("Children") or {})) do
                local said = opt(ask, "vault/github/repos/reply") or opt(ask, "vault/github/branches/reply")
                    or opt(ask, "vault/github/commits/reply")
                if said ~= nil and said.error == "denied" then
                    commands:entity(ask:id()):despawn()
                    local b, c = opt(ask, "vault/github/branches"), opt(ask, "vault/github/commits")
                    if b ~= nil then
                        ask_branches(commands, carrier:id(), b.owner, b.name)
                    elseif c ~= nil then
                        ask_commits(commands, carrier:id(), c.owner, c.name, c.branch)
                    else
                        ask_repos(commands, carrier:id())
                    end
                end
            end
            if not carrier:get("git/panel/state").open then
                carrier:get_mut("git/panel/state").open = true
            end
        end
    end
end):in_set("git/panel")

-- Only a button still here closing is someone closing the panel. A reload takes the button too, and
-- its edge comes the same: that closes nothing, because the panel is to come back.
app:add_systems(Update, {
    Query[{
        removed = { "sidebar/button/open" },
        with = { "git/panel/button" },
    }],
    Query[{ with = { "git/panel/button" } }],
    Query[{ with = { "git/panel/view" } }],
    Query[{ with = { Mut["git/panel/state"] } }],
    Commands,
}, function(closed, buttons, views, states, commands)
    local ids = {}
    for _, b in ipairs(closed:iter()) do
        ids[#ids + 1] = b:id()
    end
    for _, _ in ipairs(buttons:iter_many(ids)) do
        for _, view in ipairs(views:iter()) do
            commands:entity(view:id()):try_despawn()
        end
        for _, row in ipairs(states:iter_mut()) do
            local s = row:get_mut("git/panel/state")
            s.open, s.typing = false, nil
        end
    end
end):in_set("git/panel")

-- The folder field: what the player types while it is open. The text being typed lives on the
-- field's own text, which a rebuild reads back, so the kept folder changes only on Enter and Escape
-- leaves it as it was. The panel is open only in the open sidebar, which holds UI input, so game
-- keys don't fire while it is typed into. Runs only while the field is open.
app:add_systems(Update, {
    MessageReader[KeyboardInput],
    Query[{ with = { "git/panel", Mut["git/panel/state"] } }],
    Query[{ with = { "git/panel/view" } }],
    Query[{ with = { "git/panel/row" } }],
    Query[{ with = { Mut["Text"] } }],
}, function(keys, carriers, views, rows, texts)
    local events = keys:read()
    local carrier = carriers:iter_mut()[1]
    local view = views:iter()[1]
    local field = nil
    for _, row in ipairs(view and rows:iter_many(rows:iter_descendants(view:id())) or {}) do
        local t = texts:iter_many_mut(texts:iter_descendants_depth_first(row:id()))[1]
        if t ~= nil and t:get("Text"):match("^Folder: ") then field = t end
    end
    if carrier ~= nil then
        local s = carrier:get("git/panel/state")
        local draft = field and field:get("Text"):match("^Folder: (.*)_$") or s.folder or ""
        local typing = s.typing == true
        for _, ev in ipairs(events) do
            if typing and ev.state == "Pressed" then
                local key = ev.logical_key
                -- A character key reads back as a one-item list (measured), its `SmolStr` inside.
                local typed = type(key) == "table" and key.Character ~= nil and (key.Character[1] or key.Character) or nil
                if type(typed) == "string" then
                    if #draft < 100 and typed:match("^[%w%-%._/]$") then draft = draft .. typed end
                elseif key == "Backspace" then
                    draft = draft:sub(1, -2)
                elseif key == "Escape" then
                    typing = false
                    carrier:get_mut("git/panel/state").typing = nil
                elseif key == "Enter" then
                    typing = false
                    local kept = carrier:get_mut("git/panel/state")
                    kept.folder, kept.typing = draft ~= "" and draft or nil, nil
                end
            end
        end
        if field ~= nil and typing then
            field:get_mut("Text"):set_if_neq(folder_text(nil, true, draft))
        end
    end
end):in_set("git/panel"):run_if({
    Query[{ with = { "git/panel/state" } }],
}, function(states)
    for _, row in ipairs(states:iter()) do
        if row:get("git/panel/state").typing then return true end
    end
    return false
end)

-- The rows are rebuilt only when what they say changes, read from the texts they hold: a rebuild
-- takes the buttons the player may be pointing at.
app:add_systems(Update, {
    Query[{ with = { "git/panel/view", Mut["sidebar/panel"] } }],
    Query[{
        with = { "git/panel", "git/panel/state" },
        optional = { "Children" },
    }],
    Query[{ with = { "sidebar/panel/scroll" } }],
    Query[{ with = { "git/panel/row" } }],
    Query[{ with = { "Text" } }],
    Query[{
        any_of = {
            "vault/github/repos",
            "vault/github/branches",
            "vault/github/commits",
            "vault/github/repos/reply",
            "vault/github/branches/reply",
            "vault/github/commits/reply",
            "vault/github/signin/reply",
        },
        with = { "Request" },
        optional = { "Children" },
    }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Query[{ with = { "core/world/flip" } }],
    Query[{ with = { "git/world/head/pull" } }],
    Query[{ with = { "scope/portal", "scope/portal/locked" } }],
    Query[{
        with = { "core/registry/sessions", "Request" },
        optional = { "core/registry/sessions/reply" },
    }],
    Query[{
        any_of = { "core/registry/despawn", "core/world/unload", "core/world/restart" },
        with = { "Request" },
        optional = {
            "core/registry/despawn", "core/world/unload", "core/world/restart",
            "core/registry/despawn/reply", "core/world/unload/reply", "core/world/restart/reply",
        },
    }],
    Query[{ with = { "scope/portal" }, without = { "placement" } }],
    Query[{ with = { "core/net", "core/net/owns" } }],
    Query[{ with = { "core/net", "core/permission/grants" } }],
    Commands,
}, function(views, carriers, scrolls, rows, texts, asks, statuses, flips, pulls, locked, standing, row_asks,
            placed, own, granted, commands)
    local view = views:iter_mut()[1]
    local carrier = carriers:iter()[1]
    local parts = view and scrolls:iter_descendants(view:id()) or {}
    local scroll = scrolls:iter_many(parts)[1]
    if carrier ~= nil and scroll ~= nil then
        local state = carrier:get("git/panel/state")
        local me = statuses:iter()[1]
        local scope = me and me:get("core/world/status").scope_key
        local owner, name = split(state.repo)

        local repos, branches, commits, signed_out = {}, {}, {}, false
        -- `add_url`: root's install page, on its repositories reply. `denied`: a read the player
        -- denied. `missing`: the chosen repository's reply says the app isn't installed on it.
        local add_url, denied, missing = nil, false, nil
        local function read(said)
            if said and said.error == "denied" then
                denied = true
            elseif said and said.reason == "not-installed" then
                missing = { url = type(said.install_url) == "string" and said.install_url or nil }
            end
        end
        for _, ask in ipairs(asks:iter_many(carrier:get("Children") or {})) do
            if ask:has("vault/github/repos") then
                local said = ask:has("vault/github/repos/reply") and ask:get("vault/github/repos/reply")
                repos = said and said.repos and listed(said.repos) or repos
                if said and type(said.install_url) == "string" then add_url = said.install_url end
                denied = denied or (said and said.error == "denied") or false
                for _, s in ipairs(asks:iter_many(ask:get("Children") or {})) do
                    local who = s:has("vault/github/signin/reply") and s:get("vault/github/signin/reply")
                    signed_out = signed_out or (who and who.login == nil)
                end
            elseif ask:has("vault/github/branches") then
                local wish = ask:get("vault/github/branches")
                local said = ask:has("vault/github/branches/reply") and ask:get("vault/github/branches/reply")
                if wish.owner == owner and wish.name == name then
                    if said and said.branches then branches = said.branches end
                    read(said)
                end
            elseif ask:has("vault/github/commits") then
                local wish = ask:get("vault/github/commits")
                local said = ask:has("vault/github/commits/reply") and ask:get("vault/github/commits/reply")
                if wish.owner == owner and wish.name == name and wish.branch == state.branch then
                    if said and said.commits then commits = said.commits end
                    read(said)
                end
            end
        end
        -- One line under the actions: the denied read, else the app missing from the chosen
        -- repository, with Install when root names its install page.
        local notice = nil
        if denied then
            notice = { text = DENIED }
        elseif missing ~= nil then
            notice = { text = not_installed(state.repo), url = missing.url }
        end

        local shown, open, draft = {}, {}, nil
        local held = rows:iter_many(parts)
        for _, row in ipairs(held) do
            local list = {}
            for _, line in ipairs(texts:iter_many(texts:iter_descendants_depth_first(row:id()))) do
                list[#list + 1] = line:get("Text")
                shown[#shown + 1] = line:get("Text")
            end
            if list[1] ~= nil then open[list[1]] = list[3] == "▲" end
            if state.typing and list[1] ~= nil then draft = draft or list[1]:match("^Folder: (.*)_$") end
        end
        local folder_line = folder_text(state.folder, state.typing, draft)

        local repo_options = {}
        for _, r in ipairs(repos) do
            local full = r.owner .. "/" .. r.name
            repo_options[#repo_options + 1] = { text = r.name, value = full, selected = full == state.repo }
        end
        if add_url ~= nil then
            repo_options[#repo_options + 1] = { text = ADD_REPOSITORY, open = add_url }
        end
        local branch_options = {}
        for _, b in ipairs(branches) do
            branch_options[#branch_options + 1] = { text = b, value = b, selected = b == state.branch }
        end

        local key = owner ~= nil and state.branch ~= nil and scope_of(state.repo, state.branch, state.folder) or nil
        local current = key ~= nil and key == scope
        local flipping, failed = false, nil
        for _, f in ipairs(flips:iter()) do
            local ask = f:get("core/world/flip")
            if key ~= nil and ask.scope == key then
                flipping = flipping or ask.status == "resolving" or ask.status == "loading" or ask.status == "promoting"
                if ask.status == "failed" then failed = tostring(ask.reason or "failed") end
            end
        end
        local switch = "↗ Switch"
        if current then
            switch = "● Current"
        elseif flipping then
            switch = "⏳ Switching…"
        elseif failed ~= nil then
            switch = "⚠ " .. failed .. " — retry"
        end
        local pulling = not pulls:is_empty()
        local refused = nil
        for _, p in ipairs(locked:iter()) do
            if p:get("scope/portal").target == key then
                refused = "⚠ portal refused: " .. tostring(p:get("scope/portal/locked").reason)
            end
        end

        -- Root answers the latest 10; the panel shows 8.
        local lines = {}
        for i = 1, math.min(8, #commits) do
            local message = tostring(commits[i].message or "")
            local line = message:match("^([^\n]+)") or message
            if #line > 30 then line = line:sub(1, 27) .. "..." end
            lines[i] = { sha = tostring(commits[i].sha or ""), line = line }
        end

        -- SESSIONS: root's list of the registry's sessions, and the worlds root holds for this player.
        local my_root = me and me:get("core/world/status").scope_root
        -- `held` is root's word for the worlds Stop on this PC counts as held, so a held line shows
        -- exactly where Stop is not refused `not-held`.
        local sessions, list_error = nil, nil
        local holds = {}
        for _, ask in ipairs(standing:iter_many(carrier:get("Children") or {})) do
            if ask:has("core/registry/sessions") then
                local said = opt(ask, "core/registry/sessions/reply")
                if said ~= nil then
                    sessions, list_error = said.sessions, said.error
                    for _, h in ipairs(said.held or {}) do
                        if type(h) == "table" and h.scope ~= nil then
                            holds[h.scope] = h.playing and "playing" or "background"
                        end
                    end
                end
            end
        end
        local world_rows, listed_scope = {}, {}
        for _, s in ipairs(sessions or {}) do
            if type(s) == "table" and s.scope ~= nil and not listed_scope[s.scope] then
                listed_scope[s.scope] = true
                world_rows[#world_rows + 1] = { scope = s.scope, scope_root = s.scope_root,
                    counts = string.format("%d▸ %d◌", tonumber(s.active) or 0, tonumber(s.background) or 0) }
            end
        end
        local extra = {}
        for k in pairs(holds) do
            if not listed_scope[k] then extra[#extra + 1] = k end
        end
        table.sort(extra)
        for _, k in ipairs(extra) do world_rows[#world_rows + 1] = { scope = k } end
        -- What this user may do in this world, as its server grants it on this client's own net entity.
        local writer = false
        for _, n in ipairs(granted:iter()) do
            local grants = n:get("core/permission/grants")
            for _, name in ipairs(grants.names or {}) do
                writer = writer or name == "writer"
            end
        end
        -- Each row's own asks, by scope: what its buttons say and its refusal line.
        local by_scope = {}
        for _, ask in ipairs(row_asks:iter_many(carrier:get("Children") or {})) do
            local b
            if ask:has("core/registry/despawn") then
                b = by_scope[opt(ask, "core/registry/despawn").scope] or {}
                b.despawn = { said = opt(ask, "core/registry/despawn/reply") }
                by_scope[opt(ask, "core/registry/despawn").scope] = b
            elseif ask:has("core/world/unload") then
                b = by_scope[opt(ask, "core/world/unload").scope] or {}
                b.unload = { said = opt(ask, "core/world/unload/reply") }
                by_scope[opt(ask, "core/world/unload").scope] = b
            else
                b = by_scope[opt(ask, "core/world/restart").scope] or {}
                b.restart = { said = opt(ask, "core/world/restart/reply") }
                by_scope[opt(ask, "core/world/restart").scope] = b
            end
        end
        for _, w in ipairs(world_rows) do
            local b = by_scope[w.scope] or {}
            local d = b.despawn and b.despawn.said
            local u = b.unload and b.unload.said
            local r = b.restart and b.restart.said
            w.current = scope ~= nil and w.scope == scope
            w.label = (w.current and "● " or "") .. short(w.scope)
            -- One Stop per row. This world's grants say whether the player may stop its
            -- repository's worlds for everyone, on any Gateway; a world of another repository is
            -- stopped for everyone from inside it, where its own grants say.
            w.everyone = writer and w.scope_root ~= nil and w.scope_root == my_root
            if b.despawn and (d == nil or d.status == "asking" or d.status == "requested") then
                w.x = "..."
            elseif state.armed ~= nil and state.armed.scope == w.scope then
                w.x = "sure?"
            else
                w.x = "■ Stop for everyone"
            end
            w.held = holds[w.scope]
            w.stop = (b.unload and u == nil) and "..." or "■ Stop here"
            w.restart = (b.restart and (r == nil or r.status == "restarting")) and "..." or "↻ Restart"
            if d and d.status == "refused" then
                w.refused = despawn_refused(d.reason)
            elseif u and u.status == "refused" then
                w.refused = stop_refused(u.reason)
            elseif r and r.status == "refused" then
                w.refused = restart_refused(r.reason)
            end
        end
        local header_line = nil
        if sessions == nil then
            header_line = "Loading sessions…"
        elseif list_error ~= nil then
            header_line = "⚠ sessions unavailable (" .. tostring(list_error) .. ")"
        elseif world_rows[1] == nil then
            header_line = "No visible sessions"
        end
        -- The portals this player placed here, each with Close: a despawn of an entity this client
        -- owns asks the server, which despawns it everywhere.
        local mine = {}
        for _, n in ipairs(own:iter()) do
            for _, p in ipairs(placed:iter_many(n:get("core/net/owns"))) do
                mine[#mine + 1] = { id = p:id(), label = "🌀 " .. short(p:get("scope/portal").target) }
            end
        end

        local wanted = {}
        if signed_out then
            wanted[1] = "Sign in to GitHub in Accounts"
        else
            for _, p in ipairs({
                { label = "REPOSITORY", chosen = name, options = repo_options },
                { label = "BRANCH", chosen = state.branch, options = branch_options },
            }) do
                wanted[#wanted + 1] = p.label
                wanted[#wanted + 1] = p.chosen or "(none)"
                wanted[#wanted + 1] = open[p.label] and "▲" or "▼"
                for _, o in ipairs(p.options) do wanted[#wanted + 1] = o.text end
            end
            wanted[#wanted + 1] = folder_line
            if key ~= nil then
                wanted[#wanted + 1] = switch
                if current then wanted[#wanted + 1] = pulling and "⏳ Pulling…" or "⭳ Pull" end
                wanted[#wanted + 1] = "🌀 Portal"
            end
            if notice ~= nil then
                wanted[#wanted + 1] = notice.text
                if notice.url ~= nil then wanted[#wanted + 1] = "Install" end
            end
            if refused ~= nil then wanted[#wanted + 1] = refused end
            wanted[#wanted + 1] = "SESSIONS"
            if header_line ~= nil then wanted[#wanted + 1] = header_line end
            for _, w in ipairs(world_rows) do
                wanted[#wanted + 1] = w.label
                if w.counts ~= nil then wanted[#wanted + 1] = w.counts end
                if not w.current then wanted[#wanted + 1] = "^" end
                if w.everyone then wanted[#wanted + 1] = w.x end
                if w.held ~= nil then
                    wanted[#wanted + 1] = w.held
                    if not w.everyone then wanted[#wanted + 1] = w.stop end
                    wanted[#wanted + 1] = w.restart
                end
                if w.refused ~= nil then wanted[#wanted + 1] = w.refused end
            end
            if mine[1] ~= nil then wanted[#wanted + 1] = "PORTALS" end
            for _, m in ipairs(mine) do
                wanted[#wanted + 1] = m.label
                wanted[#wanted + 1] = "Close"
            end
            if lines[1] ~= nil then wanted[#wanted + 1] = "RECENT COMMITS" end
            for _, c in ipairs(lines) do
                wanted[#wanted + 1] = c.sha
                wanted[#wanted + 1] = c.line
            end
        end
        local same = #shown == #wanted
        for i = 1, #wanted do
            same = same and shown[i] == wanted[i]
        end

        if not same then
            for _, row in ipairs(held) do
                commands:entity(row:id()):despawn()
            end
            if signed_out then
                local row = commands:spawn({
                    ["git/panel/row"] = {},
                    Node = { width = { Percent = 100 }, flex_shrink = 0, margin = { top = { Px = 8 } } },
                    ChildOf = scroll:id(),
                }):id()
                commands:spawn({
                    Text = { text = "Sign in to GitHub in Accounts" },
                    TextFont = { font_size = 12 },
                    ["ui/style"] = { text = "text_dim" },
                    ChildOf = row,
                })
            else
                local pickers = {
                    spawn_picker(commands, scroll:id(), "REPOSITORY", name, open["REPOSITORY"], repo_options),
                    spawn_picker(commands, scroll:id(), "BRANCH", state.branch, open["BRANCH"], branch_options),
                }
                -- Opening one picker closes the other.
                for i, picker in ipairs(pickers) do
                    local other = i == 1 and pickers[2] or pickers[1]
                    commands:entity(picker.trigger):observe(On[Pointer[Click]], {
                        Query[{ with = { Mut["Node"] } }],
                        Query[{ with = { Mut["Text"] } }],
                    }, function(_, nodes, arrows)
                        local arrow = arrows:iter_many({ picker.arrow })[1]
                        local opening = arrow ~= nil and arrow:get("Text") ~= "▲"
                        close(nodes, arrows, other)
                        if opening then
                            for _, list in ipairs(nodes:iter_many_mut({ picker.list })) do
                                list:get_mut("Node").display = "Flex"
                            end
                            for _, a in ipairs(arrows:iter_many_mut({ picker.arrow })) do
                                a:get_mut("Text"):set_if_neq("▲")
                            end
                        else
                            close(nodes, arrows, picker)
                        end
                    end)
                end
                -- An option with an address is "+ Add a repository…": it asks root to open the
                -- install page, and the choice stays as it was.
                local function install_on_click(button, url, picker)
                    commands:entity(button):observe(On[Pointer[Click]], {
                        Query[{ with = { "git/panel" }, optional = { "Children" } }],
                        Query[{ with = { "vault/open_url", "Request" } }],
                        Query[{ with = { Mut["Node"] } }],
                        Query[{ with = { Mut["Text"] } }],
                        Query[{ with = { "core/net", "core/net/owns" } }],
                        Commands,
                    }, function(_, owners, opens, nodes, arrows, own, click_commands)
                        for _, n in ipairs(own:iter()) do
                            for _, o in ipairs(owners:iter_many(n:get("core/net/owns"))) do
                                ask_open(click_commands, o:id(), url, opens:iter_many(o:get("Children") or {}))
                            end
                        end
                        if picker ~= nil then close(nodes, arrows, picker) end
                    end)
                end
                for _, pick in ipairs(pickers[1].picks) do
                    local value = pick.value
                    if pick.open ~= nil then
                        install_on_click(pick.button, pick.open, pickers[1])
                    else
                        commands:entity(pick.button):observe(On[Pointer[Click]], {
                            Query[{ with = { "git/panel", Mut["git/panel/state"] } }],
                            Query[{ with = { Mut["Node"] } }],
                            Query[{ with = { Mut["Text"] } }],
                            Query[{ with = { "core/net", "core/net/owns" } }],
                        }, function(_, owners, nodes, arrows, own)
                            for _, n in ipairs(own:iter()) do
                                for _, o in ipairs(owners:iter_many_mut(n:get("core/net/owns"))) do
                                    local s = o:get_mut("git/panel/state")
                                    s.repo = value
                                    s.branch = nil
                                    s.folder = nil
                                end
                            end
                            close(nodes, arrows, pickers[1])
                        end)
                    end
                end
                for _, pick in ipairs(pickers[2].picks) do
                    local value = pick.value
                    commands:entity(pick.button):observe(On[Pointer[Click]], {
                        Query[{ with = { "git/panel", Mut["git/panel/state"] } }],
                        Query[{ with = { Mut["Node"] } }],
                        Query[{ with = { Mut["Text"] } }],
                        Query[{ with = { "core/net", "core/net/owns" } }],
                    }, function(_, owners, nodes, arrows, own)
                        for _, n in ipairs(own:iter()) do
                            for _, o in ipairs(owners:iter_many_mut(n:get("core/net/owns"))) do
                                o:get_mut("git/panel/state").branch = value
                            end
                        end
                        close(nodes, arrows, pickers[2])
                    end)
                end

                -- The folder: a click opens its field, where the folder is typed (the keys' system).
                local folder_row = commands:spawn({
                    ["git/panel/row"] = {},
                    Node = { width = { Percent = 100 }, flex_direction = "Column", flex_shrink = 0, margin = { top = { Px = 8 } } },
                    ChildOf = scroll:id(),
                }):id()
                local folder_field = commands:spawn({
                    Button = {},
                    Node = {
                        width = { Percent = 100 },
                        height = { Px = 30 },
                        flex_direction = "Row",
                        align_items = "Center",
                        padding = { left = { Px = 8 }, right = { Px = 8 } },
                        border = { left = { Px = 1 }, right = { Px = 1 }, top = { Px = 1 }, bottom = { Px = 1 } },
                    },
                    BorderRadius = {
                        top_left = { Px = 4 }, top_right = { Px = 4 },
                        bottom_left = { Px = 4 }, bottom_right = { Px = 4 },
                    },
                    ["ui/style"] = state.typing and { background = "bg", border = "accent" }
                        or { background = "row_bg", hover = "row_hover", border = "border" },
                    ChildOf = folder_row,
                })
                commands:spawn({
                    Text = { text = folder_line },
                    TextFont = { font_size = 12 },
                    ["ui/style"] = { text = (state.typing and "accent") or (state.folder ~= nil and "text" or "text_dim") },
                    ChildOf = folder_field:id(),
                })
                if not state.typing then
                    folder_field:observe(On[Pointer[Click]], {
                        Query[{ with = { "git/panel", Mut["git/panel/state"] } }],
                        Query[{ with = { "core/net", "core/net/owns" } }],
                    }, function(_, owners, own)
                        for _, n in ipairs(own:iter()) do
                            for _, o in ipairs(owners:iter_many_mut(n:get("core/net/owns"))) do
                                o:get_mut("git/panel/state").typing = true
                            end
                        end
                    end)
                end

                if key ~= nil then
                    local actions = commands:spawn({
                        ["git/panel/row"] = {},
                        Node = {
                            width = { Percent = 100 },
                            flex_direction = "Row",
                            flex_shrink = 0,
                            column_gap = { Px = 6 },
                            margin = { top = { Px = 8 } },
                        },
                        ChildOf = scroll:id(),
                    }):id()
                    local switch_button = spawn_action(commands, actions, switch, not current, current or flipping, nil)
                    local pull_button = current
                        and spawn_action(commands, actions, pulling and "⏳ Pulling…" or "⭳ Pull", not pulling, pulling, 76)
                    local portal_button = spawn_action(commands, actions, "🌀 Portal", not current, current, nil)
                    -- A click after a failure is the retry: root's driver retires the failed ask.
                    if not current then
                        switch_button:observe(On[Pointer[Click]], {
                            Query[{
                                with = { "git/panel", "git/panel/state" },
                                optional = { "Children" },
                            }],
                            Query[{ with = { "vault/github/commits", "Request" } }],
                            Query[{ with = { "core/net", "core/net/owns" } }],
                            Commands,
                        }, function(_, owners, commit_asks, own, click_commands)
                            for _, n in ipairs(own:iter()) do
                                for _, o in ipairs(owners:iter_many(n:get("core/net/owns"))) do
                                    local s = o:get("git/panel/state")
                                    local o_owner, o_name = split(s.repo)
                                    if o_owner ~= nil and s.branch ~= nil then
                                        click_commands:spawn({
                                            ["core/world/flip"] = { scope = scope_of(s.repo, s.branch, s.folder) },
                                            WorldShared = {},
                                            ["core/net/sync"] = false,
                                            ["core/script/owner"] = false,
                                        })
                                        for _, ask in ipairs(commit_asks:iter_many(o:get("Children") or {})) do
                                            click_commands:entity(ask:id()):despawn()
                                        end
                                        ask_commits(click_commands, o:id(), o_owner, o_name, s.branch)
                                    end
                                end
                            end
                        end)
                    end
                    if current and not pulling then
                        pull_button:observe(On[Pointer[Click]], {
                            Query[{ with = { "git/world/head" } }],
                            Query[{ with = { "git/world/head/pull" } }],
                            Commands,
                        }, function(_, heads, asked, click_commands)
                            local head = heads:iter()[1]
                            local sha = head and head:get("git/world/head").sha
                            if sha ~= nil and asked:is_empty() then
                                click_commands:spawn({ ["git/world/head/pull"] = { sha = sha }, ["core/script/owner"] = false })
                            end
                        end)
                    end
                    -- The world's server spawns the portal, for the player to place, or refuses it.
                    -- While the server's last answer stands, it takes an ask for the target it
                    -- answered as answered already, and never answers it: a click then asks nothing.
                    if not current then
                        portal_button:observe(On[Pointer[Click]], {
                            Query[{
                                with = { "git/panel", "git/panel/state" },
                                optional = { "git/panel/response" },
                            }],
                            Query[{ with = { "core/net", "core/net/owns" } }],
                            Commands,
                        }, function(_, owners, own, click_commands)
                            for _, n in ipairs(own:iter()) do
                                for _, o in ipairs(owners:iter_many(n:get("core/net/owns"))) do
                                    local s = o:get("git/panel/state")
                                    local standing = o:has("git/panel/response") and o:get("git/panel/response").op ~= nil
                                    if s.repo ~= nil and s.branch ~= nil and not standing then
                                        click_commands:entity(o:id()):insert({
                                            ["git/panel/request"] = { op = "portal", target_sk = scope_of(s.repo, s.branch, s.folder) },
                                        })
                                    end
                                end
                            end
                        end)
                    end
                end

                if notice ~= nil then
                    local row = commands:spawn({
                        ["git/panel/row"] = {},
                        Node = {
                            width = { Percent = 100 },
                            flex_direction = "Row",
                            flex_shrink = 0,
                            align_items = "Center",
                            column_gap = { Px = 6 },
                            padding = { left = { Px = 8 } },
                            margin = { top = { Px = 8 } },
                        },
                        ChildOf = scroll:id(),
                    }):id()
                    commands:spawn({
                        Text = { text = notice.text },
                        TextFont = { font_size = 11 },
                        Node = { flex_grow = 1, flex_shrink = 1, min_width = { Px = 0 } },
                        ["ui/style"] = { text = "text_dim" },
                        ChildOf = row,
                    })
                    if notice.url ~= nil then
                        install_on_click(spawn_action(commands, row, "Install", true, false, 64):id(), notice.url, nil)
                    end
                end

                if refused ~= nil then
                    local row = commands:spawn({
                        ["git/panel/row"] = {},
                        Node = { width = { Percent = 100 }, flex_shrink = 0, padding = { left = { Px = 8 } }, margin = { top = { Px = 4 } } },
                        ChildOf = scroll:id(),
                    }):id()
                    commands:spawn({
                        Text = { text = refused },
                        TextFont = { font_size = 9 },
                        ["ui/style"] = { text = "text_dim" },
                        ChildOf = row,
                    })
                end

                local function line_row(height, background)
                    return commands:spawn({
                        ["git/panel/row"] = {},
                        Node = {
                            width = { Percent = 100 },
                            height = { Px = height },
                            flex_shrink = 0,
                            flex_direction = "Row",
                            align_items = "Center",
                            column_gap = { Px = 6 },
                            padding = { left = { Px = 8 }, right = { Px = 8 } },
                        },
                        ["ui/style"] = background ~= nil and { background = background } or nil,
                        ChildOf = scroll:id(),
                    }):id()
                end
                local function text_in(row, text, size, style)
                    commands:spawn({
                        Text = { text = text },
                        TextFont = { font_size = size },
                        ["ui/style"] = { text = style },
                        ChildOf = row,
                    })
                end
                local function spacer(row)
                    commands:spawn({ Node = { flex_grow = 1 }, ChildOf = row })
                end
                local function small(row, text, live, width, armed)
                    local button = commands:spawn({
                        Button = {},
                        Node = {
                            width = { Px = width },
                            height = { Px = 20 },
                            flex_shrink = 0,
                            justify_content = "Center",
                            align_items = "Center",
                        },
                        BorderRadius = {
                            top_left = { Px = 3 }, top_right = { Px = 3 },
                            bottom_left = { Px = 3 }, bottom_right = { Px = 3 },
                        },
                        ["ui/style"] = armed and { background = "accent" }
                            or (live and { background = "icon_bg", hover = "icon_hover" } or { background = "row_alt" }),
                        ChildOf = row,
                    })
                    text_in(button:id(), text, 10, "text")
                    return button
                end

                local sessions_header = commands:spawn({
                    ["git/panel/row"] = {},
                    Node = { width = { Percent = 100 }, flex_shrink = 0, margin = { top = { Px = 8 }, bottom = { Px = 4 } } },
                    ChildOf = scroll:id(),
                }):id()
                text_in(sessions_header, "SESSIONS", 10, "text_dim")
                if header_line ~= nil then text_in(line_row(22), header_line, 10, "text_dim") end
                for i, w in ipairs(world_rows) do
                    local background = i % 2 == 0 and "row_alt" or "row_bg"
                    local row = line_row(24, background)
                    local target = w.scope
                    text_in(row, w.label, 10, w.current and "text_dim" or "text")
                    spacer(row)
                    if w.counts ~= nil then text_in(row, w.counts, 9, "text_dim") end
                    if not w.current then
                        -- Switch's ask.
                        small(row, "^", true, 24, false):observe(On[Pointer[Click]], { Commands }, function(_, click_commands)
                            click_commands:spawn({
                                ["core/world/flip"] = { scope = target },
                                WorldShared = {},
                                ["core/net/sync"] = false,
                                ["core/script/owner"] = false,
                            })
                        end)
                    end
                    if w.everyone then
                        local x = small(row, w.x, w.x ~= "...",
                            (w.x == "sure?" and 40) or (w.x == "..." and 24) or 116, w.x == "sure?")
                        if w.x ~= "..." then
                            -- The first click arms it; a second within ARM_SECONDS asks root, in place of
                            -- any earlier ask for the world.
                            x:observe(On[Pointer[Click]], {
                                Res[Time],
                                Query[{
                                    with = { "git/panel", Mut["git/panel/state"] },
                                    optional = { "Children" },
                                }],
                                Query[{ with = { "core/registry/despawn", "Request" } }],
                                Query[{ with = { "core/net", "core/net/owns" } }],
                                Commands,
                            }, function(_, time, owners, despawns, own, click_commands)
                                local now = time:elapsed_secs()
                                for _, n in ipairs(own:iter()) do
                                    for _, o in ipairs(owners:iter_many_mut(n:get("core/net/owns"))) do
                                        local s = o:get("git/panel/state")
                                        if s.armed ~= nil and s.armed.scope == target and now - s.armed.at <= ARM_SECONDS then
                                            for _, d in ipairs(despawns:iter_many(o:get("Children") or {})) do
                                                if d:get("core/registry/despawn").scope == target then
                                                    click_commands:entity(d:id()):despawn()
                                                end
                                            end
                                            click_commands:spawn({
                                                ["core/registry/despawn"] = { scope = target },
                                                Request = {},
                                                ["core/script/owner"] = false,
                                                ChildOf = o:id(),
                                            })
                                            o:get_mut("git/panel/state").armed = nil
                                        else
                                            o:get_mut("git/panel/state").armed = { scope = target, at = now }
                                        end
                                    end
                                end
                            end)
                        end
                    end
                    if w.held ~= nil then
                        local line = line_row(22, background)
                        text_in(line, w.held, 9, "text_dim")
                        spacer(line)
                        local stop = not w.everyone and small(line, w.stop, w.stop ~= "...", 76, false)
                        local restart = small(line, w.restart, w.restart ~= "...", 72, false)
                        -- Each asks root in place of any earlier ask of its kind for the world.
                        if stop and w.stop ~= "..." then
                            stop:observe(On[Pointer[Click]], {
                                Query[{ with = { "git/panel" }, optional = { "Children" } }],
                                Query[{ with = { "core/world/unload", "Request" } }],
                                Query[{ with = { "core/net", "core/net/owns" } }],
                                Commands,
                            }, function(_, owners, unloads, own, click_commands)
                                for _, n in ipairs(own:iter()) do
                                    for _, o in ipairs(owners:iter_many(n:get("core/net/owns"))) do
                                        for _, u in ipairs(unloads:iter_many(o:get("Children") or {})) do
                                            if u:get("core/world/unload").scope == target then
                                                click_commands:entity(u:id()):despawn()
                                            end
                                        end
                                        click_commands:spawn({
                                            ["core/world/unload"] = { scope = target },
                                            Request = {},
                                            ["core/script/owner"] = false,
                                            ChildOf = o:id(),
                                        })
                                    end
                                end
                            end)
                        end
                        if w.restart ~= "..." then
                            restart:observe(On[Pointer[Click]], {
                                Query[{ with = { "git/panel" }, optional = { "Children" } }],
                                Query[{ with = { "core/world/restart", "Request" } }],
                                Query[{ with = { "core/net", "core/net/owns" } }],
                                Commands,
                            }, function(_, owners, restarts, own, click_commands)
                                for _, n in ipairs(own:iter()) do
                                    for _, o in ipairs(owners:iter_many(n:get("core/net/owns"))) do
                                        for _, r in ipairs(restarts:iter_many(o:get("Children") or {})) do
                                            if r:get("core/world/restart").scope == target then
                                                click_commands:entity(r:id()):despawn()
                                            end
                                        end
                                        click_commands:spawn({
                                            ["core/world/restart"] = { scope = target },
                                            Request = {},
                                            ["core/script/owner"] = false,
                                            ChildOf = o:id(),
                                        })
                                    end
                                end
                            end)
                        end
                    end
                    if w.refused ~= nil then
                        local line = line_row(16, nil)
                        text_in(line, w.refused, 9, "text_dim")
                    end
                end

                if mine[1] ~= nil then
                    local portals_header = commands:spawn({
                        ["git/panel/row"] = {},
                        Node = { width = { Percent = 100 }, flex_shrink = 0, margin = { top = { Px = 8 }, bottom = { Px = 4 } } },
                        ChildOf = scroll:id(),
                    }):id()
                    text_in(portals_header, "PORTALS", 10, "text_dim")
                end
                for i, m in ipairs(mine) do
                    local row = line_row(24, i % 2 == 0 and "row_alt" or "row_bg")
                    local portal = m.id
                    text_in(row, m.label, 10, "text")
                    spacer(row)
                    small(row, "Close", true, 52, false):observe(On[Pointer[Click]], { Commands }, function(_, click_commands)
                        click_commands:entity(portal):try_despawn()
                    end)
                end

                if lines[1] ~= nil then
                    local header = commands:spawn({
                        ["git/panel/row"] = {},
                        Node = { width = { Percent = 100 }, flex_shrink = 0, margin = { top = { Px = 8 }, bottom = { Px = 4 } } },
                        ChildOf = scroll:id(),
                    }):id()
                    commands:spawn({
                        Text = { text = "RECENT COMMITS" },
                        TextFont = { font_size = 10 },
                        ["ui/style"] = { text = "text_dim" },
                        ChildOf = header,
                    })
                end
                for i, c in ipairs(lines) do
                    local row = commands:spawn({
                        ["git/panel/row"] = {},
                        Node = {
                            width = { Percent = 100 },
                            height = { Px = 22 },
                            flex_shrink = 0,
                            flex_direction = "Row",
                            align_items = "Center",
                            column_gap = { Px = 6 },
                            padding = { left = { Px = 8 }, right = { Px = 8 } },
                        },
                        ["ui/style"] = { background = i % 2 == 0 and "row_alt" or "row_bg" },
                        ChildOf = scroll:id(),
                    }):id()
                    commands:spawn({
                        Text = { text = c.sha },
                        TextFont = { font_size = 9 },
                        ["ui/style"] = { text = "accent" },
                        ChildOf = row,
                    })
                    commands:spawn({
                        Text = { text = c.line },
                        TextFont = { font_size = 10 },
                        ["ui/style"] = { text = "text" },
                        ChildOf = row,
                    })
                end
            end
        end

        if view:get("sidebar/panel").title == nil then
            view:get_mut("sidebar/panel").title = "GitHub"
        end
    end
end):in_set("git/panel/render"):after("git/panel"):run_if({
    Query[{ with = { "git/panel/view" } }],
    Query[{ added = { "sidebar/panel/scroll" } }],
    Query[{
        ["or"] = {
            added = { "vault/github/repos", "vault/github/branches", "vault/github/commits" },
            changed = {
                "git/panel/state",
                "vault/github/repos/reply",
                "vault/github/branches/reply",
                "vault/github/commits/reply",
                "vault/github/signin/reply",
            },
        },
    }],
    Query[{
        ["or"] = {
            changed = { "core/world/flip" },
            removed = { "core/world/flip" },
        },
    }],
    Query[{
        changed = { "core/world/status" },
        with = { "WorldShared" },
        without = { "WorldMirror" },
    }],
    Query[{
        ["or"] = {
            added = { "git/world/head/pull" },
            removed = { "git/world/head/pull" },
        },
    }],
    Query[{
        ["or"] = {
            changed = { "scope/portal/locked" },
            removed = { "scope/portal/locked" },
        },
    }],
    Query[{
        ["or"] = {
            added = {
                "core/registry/sessions/reply",
                "core/registry/despawn", "core/world/unload", "core/world/restart",
                "core/registry/despawn/reply", "core/world/unload/reply", "core/world/restart/reply",
            },
            changed = {
                "core/registry/sessions/reply",
                "core/registry/despawn/reply", "core/world/unload/reply", "core/world/restart/reply",
            },
            removed = { "core/registry/despawn", "core/world/unload", "core/world/restart" },
        },
    }],
    Query[{
        ["or"] = {
            added = { "core/net/owner" },
            changed = { "core/net/owner" },
            removed = { "placement", "scope/portal" },
        },
    }],
    Query[{
        ["or"] = {
            added = { "core/permission/grants" },
            changed = { "core/permission/grants" },
            removed = { "core/permission/grants" },
        },
        with = { "core/net" },
    }],
}, function(views, scrolls, asks, flips, statuses, pulls, locks, sessions, portals, grants)
    -- Root's replies and the flip asks cross from root's VM, and a mirrored edge arrives as surely as
    -- a local one, so their edges are all this waits on.
    return not views:is_empty() and (not scrolls:is_empty() or not asks:is_empty() or not flips:is_empty()
        or not statuses:is_empty() or not pulls:is_empty() or not locks:is_empty() or not sessions:is_empty()
        or not portals:is_empty() or not grants:is_empty())
end)

return {}
