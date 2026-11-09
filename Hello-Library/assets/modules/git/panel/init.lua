-- A sidebar panel, "GitHub": the player's repositories and a repository's branches, asked of root,
-- with Switch to move to a branch's world, Portal to drop a portal to it, Pull on this world's own
-- branch, and the branch's latest commits. Root holds the token and makes every GitHub call; the
-- panel asks root and shows only what root answers. Local UI: nothing here is synced.
--
-- git/panel = {}
--
-- git/panel/state = {
--     open = <whether the panel is open>,
--     repo = <the chosen repository, "<owner>/<name>">,
--     branch = <the chosen branch>,
-- }
--
-- git/panel/button = {}
-- git/panel/view = {}
-- git/panel/row = {}

local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local Scroll = require("bevy::picking::prelude::Scroll")

-- Core's canonical form lowercases the owner and the name, and keeps the branch as it is.
local function scope_of(repo, branch)
    return "github:" .. repo:lower() .. ":" .. branch
end

local function split(repo)
    if repo == nil then return nil end
    return repo:match("^([^/]+)/(.+)$")
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
-- once signed out.
local function stale(said, reply)
    return reply ~= nil and (said.login ~= nil) == (reply.error ~= nil)
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
    -- The wheel scrolls the list, not the panel under it as well.
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
            l:get_mut("ScrollPosition").y = math.max(0, math.min(room, at - event.event.y * 20))
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
            picks[#picks + 1] = { button = row, value = option.value }
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
    Commands,
}, function(carriers, asks, commands)
    for _, e in ipairs(carriers:iter()) do
        if not e:has("git/panel/state") then
            commands:entity(e:id()):insert({ ["git/panel/state"] = { open = false } })
        end
        if asks:iter_many(e:get("Children") or {})[1] == nil then
            ask_repos(commands, e:id())
        end
    end
end):in_set("git/panel")

-- `git/panel` taken off an entity that stays: its asks close. A despawned carrier takes its children
-- itself. The flip asks, portals and pulls it spawned are the player's, and stay.
app:add_systems(First, {
    Query[{
        removed = { "git/panel" },
        optional = { "Children" },
    }],
    Query[{
        any_of = { "vault/github/repos", "vault/github/branches", "vault/github/commits" },
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
    Commands,
}, function(carriers, repo_asks, branch_asks, commit_asks, commands)
    for _, carrier in ipairs(carriers:iter_mut()) do
        local kids = carrier:get("Children") or {}
        local state = carrier:get_mut("git/panel/state")
        local answered = repo_asks:iter_many(kids)[1]
        local said = answered and answered:has("vault/github/repos/reply") and answered:get("vault/github/repos/reply")
        local first = said and said.repos and listed(said.repos)[1]
        if state.repo == nil and first then
            state.repo = first.owner .. "/" .. first.name
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
            state.branch = branches[1]
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
            added = { "git/panel/state" },
            changed = { "git/panel/state", "vault/github/repos/reply", "vault/github/branches/reply" },
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
        with = { "git/panel", "core/net/local", Mut["git/panel/state"] },
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
    Commands,
}, function(carriers, repo_asks, signins, bars, buttons, views, commands)
    local bar = bars:iter()[1]
    for _, carrier in ipairs(carriers:iter_mut()) do
        local repos = repo_asks:iter_many(carrier:get("Children") or {})[1]
        local said = repos and signins:iter_many(repos:get("Children") or {})[1]
        local login = said and said:get("vault/github/signin/reply").login
        if said and login ~= nil and bar ~= nil and buttons:is_empty() then
            commands:spawn({
                ["sidebar/button"] = { title = "GitHub", order = 3 },
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
                carrier:get_mut("git/panel/state").open = false
            end
        end
    end
end):in_set("git/panel"):run_if({
    Query[{ added = { "sidebar/bar" } }],
    Query[{
        ["or"] = {
            added = { "git/panel", "core/net/local" },
        },
        with = { "git/panel", "core/net/local" },
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
    Query[{ with = { "git/panel", Mut["git/panel/state"] } }],
    Commands,
}, function(opened, containers, carriers, commands)
    for _, _ in ipairs(opened:iter()) do
        local container = containers:iter()[1]
        local carrier = carriers:iter_mut()[1]
        if container ~= nil and carrier ~= nil then
            commands:spawn({
                ["sidebar/panel"] = { width = 280 },
                ["git/panel/view"] = {},
                ChildOf = container:id(),
            })
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
            row:get_mut("git/panel/state").open = false
        end
    end
end):in_set("git/panel")

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
    Commands,
}, function(views, carriers, scrolls, rows, texts, asks, statuses, flips, pulls, locked, commands)
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
        for _, ask in ipairs(asks:iter_many(carrier:get("Children") or {})) do
            if ask:has("vault/github/repos") then
                local said = ask:has("vault/github/repos/reply") and ask:get("vault/github/repos/reply")
                repos = said and said.repos and listed(said.repos) or repos
                for _, s in ipairs(asks:iter_many(ask:get("Children") or {})) do
                    local who = s:has("vault/github/signin/reply") and s:get("vault/github/signin/reply")
                    signed_out = signed_out or (who and who.login == nil)
                end
            elseif ask:has("vault/github/branches") then
                local wish = ask:get("vault/github/branches")
                local said = ask:has("vault/github/branches/reply") and ask:get("vault/github/branches/reply")
                if wish.owner == owner and wish.name == name and said and said.branches then
                    branches = said.branches
                end
            elseif ask:has("vault/github/commits") then
                local wish = ask:get("vault/github/commits")
                local said = ask:has("vault/github/commits/reply") and ask:get("vault/github/commits/reply")
                if wish.owner == owner and wish.name == name and wish.branch == state.branch and said and said.commits then
                    commits = said.commits
                end
            end
        end

        local shown, open = {}, {}
        local held = rows:iter_many(parts)
        for _, row in ipairs(held) do
            local list = {}
            for _, line in ipairs(texts:iter_many(texts:iter_descendants_depth_first(row:id()))) do
                list[#list + 1] = line:get("Text")
                shown[#shown + 1] = line:get("Text")
            end
            if list[1] ~= nil then open[list[1]] = list[3] == "▲" end
        end

        local repo_options = {}
        for _, r in ipairs(repos) do
            local full = r.owner .. "/" .. r.name
            repo_options[#repo_options + 1] = { text = r.name, value = full, selected = full == state.repo }
        end
        local branch_options = {}
        for _, b in ipairs(branches) do
            branch_options[#branch_options + 1] = { text = b, value = b, selected = b == state.branch }
        end

        local key = owner ~= nil and state.branch ~= nil and scope_of(state.repo, state.branch) or nil
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
            if key ~= nil then
                wanted[#wanted + 1] = switch
                if current then wanted[#wanted + 1] = pulling and "⏳ Pulling…" or "⭳ Pull" end
                wanted[#wanted + 1] = "🌀 Portal"
            end
            if refused ~= nil then wanted[#wanted + 1] = refused end
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
                for _, pick in ipairs(pickers[1].picks) do
                    local value = pick.value
                    commands:entity(pick.button):observe(On[Pointer[Click]], {
                        Query[{ with = { "git/panel", "core/net/local", Mut["git/panel/state"] } }],
                        Query[{ with = { Mut["Node"] } }],
                        Query[{ with = { Mut["Text"] } }],
                    }, function(_, owners, nodes, arrows)
                        for _, o in ipairs(owners:iter_mut()) do
                            local s = o:get_mut("git/panel/state")
                            s.repo = value
                            s.branch = nil
                        end
                        close(nodes, arrows, pickers[1])
                    end)
                end
                for _, pick in ipairs(pickers[2].picks) do
                    local value = pick.value
                    commands:entity(pick.button):observe(On[Pointer[Click]], {
                        Query[{ with = { "git/panel", "core/net/local", Mut["git/panel/state"] } }],
                        Query[{ with = { Mut["Node"] } }],
                        Query[{ with = { Mut["Text"] } }],
                    }, function(_, owners, nodes, arrows)
                        for _, o in ipairs(owners:iter_mut()) do
                            o:get_mut("git/panel/state").branch = value
                        end
                        close(nodes, arrows, pickers[2])
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
                                with = { "git/panel", "core/net/local", "git/panel/state" },
                                optional = { "Children" },
                            }],
                            Query[{ with = { "vault/github/commits", "Request" } }],
                            Commands,
                        }, function(_, owners, commit_asks, click_commands)
                            for _, o in ipairs(owners:iter()) do
                                local s = o:get("git/panel/state")
                                local o_owner, o_name = split(s.repo)
                                if o_owner ~= nil and s.branch ~= nil then
                                    click_commands:spawn({
                                        ["core/world/flip"] = { scope = scope_of(s.repo, s.branch) },
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
                    -- The portal is the player's, not the panel's: it outlives the panel, and the
                    -- world's server approves it or refuses it.
                    if not current then
                        portal_button:observe(On[Pointer[Click]], {
                            Query[{
                                with = { "git/panel", "core/net/local", "git/panel/state" },
                                optional = { "Transform" },
                            }],
                            Commands,
                        }, function(_, owners, click_commands)
                            for _, o in ipairs(owners:iter()) do
                                local s = o:get("git/panel/state")
                                if s.repo ~= nil and s.branch ~= nil then
                                    local at = o:has("Transform") and o:get("Transform").translation or { x = 0, y = 0, z = 0 }
                                    click_commands:spawn({
                                        placement = {},
                                        Transform = { translation = at },
                                        ["scope/portal"] = { target = scope_of(s.repo, s.branch) },
                                        ["scope/portal/view"] = { mode = "3d" },
                                        ["core/net/sync"] = {
                                            placement = { authority = "client" },
                                            Transform = { authority = "client", reliable = false },
                                            ["scope/portal"] = { authority = "server" },
                                            ["scope/portal/view"] = { authority = "server" },
                                            ["scope/portal/hosted"] = { authority = "server" },
                                        },
                                        ["core/script/owner"] = false,
                                    })
                                end
                            end
                        end)
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
}, function(views, scrolls, asks, flips, statuses, pulls, locks)
    -- Root's replies and the flip asks cross from root's VM, and a mirrored edge arrives as surely as
    -- a local one, so their edges are all this waits on.
    return not views:is_empty() and (not scrolls:is_empty() or not asks:is_empty() or not flips:is_empty()
        or not statuses:is_empty() or not pulls:is_empty() or not locks:is_empty())
end)

return {}
