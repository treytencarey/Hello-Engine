-- A sidebar panel for the player's two sign-ins, Hello! (the Site) and GitHub. Root runs both and
-- keeps the tokens: this panel asks root and shows only what root answers, who the player is, or
-- the code and the address to enter it at while a sign-in waits. It opens no browser.
--
-- sidebar/profile = {}
--
-- sidebar/profile/state = {
--     open = <whether the panel is open>,
-- }
--
-- sidebar/profile/button = {}
-- sidebar/profile/view = {}
-- sidebar/profile/row = {}

local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local Time = require("bevy::time::Time")

-- What one sign-in's row says. `known`: root has answered the standing ask. `who`: the name root
-- gave, while signed in. `wish` and `said`: the player's last sign-in or sign-out ask and root's
-- answer to it, if any.
local function account(title, known, who, wish, said)
    local row = { title = title, status = "Not signed in", role = "text_dim" }
    if who ~= nil then
        row.status, row.role, row.label = tostring(who), "text_good", "Sign out"
    elseif not known or (wish ~= nil and said == nil) then
        row.status = "Asking..."
    elseif wish ~= nil and wish.start and said.pending then
        row.status = "Waiting for sign-in..."
        if said.user_code ~= nil then
            row.hint = said.verification_uri ~= nil and ("Enter the code at " .. tostring(said.verification_uri) .. ":")
                or "Enter the code:"
            row.code = tostring(said.user_code)
        end
    else
        if wish ~= nil and wish.start and said.error ~= nil then
            row.status, row.role = tostring(said.error), "text_bad"
        end
        row.label = "Sign in"
    end
    return row
end

-- The texts a row holds, in the order they are spawned.
local function texts_of(row)
    local out = { row.title, row.status }
    if row.hint ~= nil then out[#out + 1] = row.hint end
    if row.code ~= nil then out[#out + 1] = row.code end
    if row.label ~= nil then out[#out + 1] = row.label end
    return out
end

-- Spawns a row and answers its button, for the caller's click, or nil.
local function spawn_account(commands, parent, row)
    local card = commands:spawn({
        ["sidebar/profile/row"] = {},
        Node = {
            width = { Percent = 100 },
            flex_direction = "Column",
            flex_shrink = 0,
            margin = { bottom = { Px = 8 } },
            padding = { left = { Px = 8 }, right = { Px = 8 }, top = { Px = 8 }, bottom = { Px = 8 } },
            border = { left = { Px = 1 }, right = { Px = 1 }, top = { Px = 1 }, bottom = { Px = 1 } },
        },
        BorderRadius = {
            top_left = { Px = 4 }, top_right = { Px = 4 },
            bottom_left = { Px = 4 }, bottom_right = { Px = 4 },
        },
        ["ui/style"] = { background = "row_bg", border = "border" },
        ChildOf = parent,
    }):id()
    local line = commands:spawn({
        Node = {
            width = { Percent = 100 },
            flex_direction = "Row",
            justify_content = "SpaceBetween",
            align_items = "Center",
            column_gap = { Px = 8 },
            margin = { bottom = { Px = 4 } },
        },
        ChildOf = card,
    }):id()
    commands:spawn({
        Text = { text = row.title },
        TextFont = { font_size = 13 },
        ["ui/style"] = { text = "text" },
        ChildOf = line,
    })
    commands:spawn({
        Text = { text = row.status },
        TextFont = { font_size = 11 },
        Node = { flex_shrink = 1, min_width = { Px = 0 } },
        ["ui/style"] = { text = row.role },
        ChildOf = line,
    })
    if row.hint ~= nil then
        commands:spawn({
            Text = { text = row.hint },
            TextFont = { font_size = 10 },
            Node = { margin = { bottom = { Px = 4 } } },
            ["ui/style"] = { text = "text_dim" },
            ChildOf = card,
        })
    end
    if row.code ~= nil then
        local box = commands:spawn({
            Node = {
                width = { Percent = 100 },
                height = { Px = 44 },
                justify_content = "Center",
                align_items = "Center",
                margin = { bottom = { Px = 4 } },
            },
            ["ui/style"] = { background = "bg" },
            ChildOf = card,
        }):id()
        commands:spawn({
            Text = { text = row.code },
            TextFont = { font_size = 22 },
            ["ui/style"] = { text = "accent" },
            ChildOf = box,
        })
    end
    if row.label == nil then
        return nil
    end
    local button = commands:spawn({
        Button = {},
        Node = {
            width = { Percent = 100 },
            height = { Px = 28 },
            justify_content = "Center",
            align_items = "Center",
            border = { left = { Px = 1 }, right = { Px = 1 }, top = { Px = 1 }, bottom = { Px = 1 } },
        },
        BorderRadius = {
            top_left = { Px = 4 }, top_right = { Px = 4 },
            bottom_left = { Px = 4 }, bottom_right = { Px = 4 },
        },
        ["ui/style"] = { background = row.label == "Sign out" and "row_alt" or "icon_bg", hover = "row_hover", border = "border" },
        ChildOf = card,
    })
    commands:spawn({
        Text = { text = row.label },
        TextFont = { font_size = 12 },
        ["ui/style"] = { text = "text" },
        ChildOf = button:id(),
    })
    return button
end

-- The carrier asks root who is signed in, on each sign-in, and keeps both asks open: root's answers
-- change with the sessions. The asks carry nothing of this mod's, and outlive a reload of it, so a
-- sign-in waiting for the player goes on; a reload re-fires this edge, and asks already open stay.
-- What the panel keeps through a reload lives on the carrier, which a reload leaves alone. `sidebar`
-- taken off the carrier takes the state with it, as a part of its name: a closed panel starts again.
app:add_systems(First, {
    Query[{
        added = { "sidebar/profile" },
        optional = { "sidebar/profile/state", "Children" },
    }],
    Query[{
        removed = { "sidebar/profile/state" },
        with = { "sidebar/profile" },
    }],
    Query[{ with = { "core/player/session/signin", "Request" } }],
    Query[{ with = { "vault/github/signin", "Request" } }],
    Commands,
}, function(carriers, stripped, sites, githubs, commands)
    for _, e in ipairs(carriers:iter()) do
        if not e:has("sidebar/profile/state") then
            commands:entity(e:id()):insert({ ["sidebar/profile/state"] = { open = false } })
        end
        local kids = e:get("Children") or {}
        local site_asked, github_asked = false, false
        for _, ask in ipairs(sites:iter_many(kids)) do
            local wish = ask:get("core/player/session/signin")
            site_asked = site_asked or not (wish.start or wish.sign_out)
        end
        for _, ask in ipairs(githubs:iter_many(kids)) do
            local wish = ask:get("vault/github/signin")
            github_asked = github_asked or not (wish.start or wish.sign_out)
        end
        if not site_asked then
            commands:spawn({
                ["core/player/session/signin"] = {},
                Request = {},
                ["core/script/owner"] = false,
                ChildOf = e:id(),
            })
        end
        if not github_asked then
            commands:spawn({
                ["vault/github/signin"] = {},
                Request = {},
                ["core/script/owner"] = false,
                ChildOf = e:id(),
            })
        end
    end
    for _, e in ipairs(stripped:iter()) do
        commands:entity(e:id()):try_insert({ ["sidebar/profile/state"] = { open = false } })
    end
end):in_set("sidebar/profile/init")

-- `sidebar/profile` taken off an entity that stays: its asks close. A despawned carrier takes its
-- children itself.
app:add_systems(First, {
    Query[{
        removed = { "sidebar/profile" },
        optional = { "Children" },
    }],
    Query[{
        any_of = { "core/player/session/signin", "vault/github/signin" },
        with = { "Request" },
    }],
    Commands,
}, function(removed, asks, commands)
    for _, e in ipairs(removed:iter()) do
        for _, ask in ipairs(asks:iter_many(e:get("Children") or {})) do
            commands:entity(ask:id()):try_despawn()
        end
    end
end):in_set("sidebar/profile/removed")

-- The button goes in the bar for a local player with the panel: on a new bar (the sidebar built
-- or reloaded), and on the panel itself (added, or this mod reloaded).
app:add_systems(Update, {
    Query[{ with = { "sidebar/profile", "core/net/local" } }],
    Query[{ with = { "sidebar/bar" } }],
    Query[{ with = { "sidebar/profile/button" } }],
    Commands,
}, function(carriers, bars, buttons, commands)
    local bar = bars:iter()[1]
    if bar ~= nil and not carriers:is_empty() and buttons:is_empty() then
        commands:spawn({
            ["sidebar/button"] = { title = "Accounts", order = 0 },
            ["sidebar/profile/button"] = {},
            ChildOf = bar:id(),
        })
    end
end):in_set("sidebar/profile/add_button"):run_if({
    Query[{ added = { "sidebar/bar" } }],
    Query[{
        ["or"] = {
            added = { "sidebar/profile", "core/net/local" },
        },
        with = { "sidebar/profile", "core/net/local" },
    }],
}, function(new_bars, new_carriers)
    return not new_bars:is_empty() or not new_carriers:is_empty()
end)

-- A new button that was open before a reload opens again, by the path a click takes. It waits for the
-- sidebar to make it an icon: an icon drawn active reacts to `sidebar/button/open` on a node.
app:add_systems(Update, {
    Query[{
        added = { "Node" },
        with = { "sidebar/profile/button" },
    }],
    Query[{ with = { "sidebar/profile", "sidebar/profile/state" } }],
    Query[{ with = { "sidebar/button/open" } }],
    Commands,
}, function(icons, carriers, open_buttons, commands)
    for _, icon in ipairs(icons:iter()) do
        local carrier = carriers:iter()[1]
        local state = carrier and carrier:get("sidebar/profile/state")
        if state ~= nil and state.open then
            local order = 0
            for _, o in ipairs(open_buttons:iter()) do
                local opened = o:get("sidebar/button/open")
                order = math.max(order, opened.order)
            end
            commands:entity(icon:id()):insert({ ["sidebar/button/open"] = { order = order + 1 } })
        end
    end
end):in_set("sidebar/profile/restore")

app:add_systems(Update, {
    Query[{
        added = { "sidebar/button/open" },
        with = { "sidebar/profile/button" },
    }],
    Query[{ with = { "sidebar/container" } }],
    Query[{ with = { "sidebar/profile", Mut["sidebar/profile/state"] } }],
    Commands,
}, function(opened, containers, carriers, commands)
    for _, _ in ipairs(opened:iter()) do
        local container = containers:iter()[1]
        local carrier = carriers:iter_mut()[1]
        if container ~= nil and carrier ~= nil then
            commands:spawn({
                ["sidebar/panel"] = {},
                ["sidebar/profile/view"] = {},
                ChildOf = container:id(),
            })
            if not carrier:get("sidebar/profile/state").open then
                carrier:get_mut("sidebar/profile/state").open = true
            end
        end
    end
end):in_set("sidebar/profile/open")

-- Only a button still here closing is someone closing the panel. A reload takes the button too, and
-- its edge comes the same: that closes nothing, because the panel is to come back.
app:add_systems(Update, {
    Query[{
        removed = { "sidebar/button/open" },
        with = { "sidebar/profile/button" },
    }],
    Query[{ with = { "sidebar/profile/button" } }],
    Query[{ with = { "sidebar/profile/view" } }],
    Query[{ with = { Mut["sidebar/profile/state"] } }],
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
            row:get_mut("sidebar/profile/state").open = false
        end
    end
end):in_set("sidebar/profile/close")

-- The rows are rebuilt only when what they say changes, read from the texts they hold. A click asks
-- root on a new request and closes the last one it made for that sign-in, so a finished sign-out
-- or a failed sign-in never asks again; the standing ask stays.
app:add_systems(Update, {
    Query[{ with = { "sidebar/profile/view", Mut["sidebar/panel"] } }],
    Query[{
        with = { "sidebar/profile", "sidebar/profile/state" },
        optional = { "Children" },
    }],
    Query[{ with = { "sidebar/panel/scroll" } }],
    Query[{ with = { "sidebar/profile/row" } }],
    Query[{ with = { "Text" } }],
    Query[{
        with = { "core/player/session/signin", "Request" },
        optional = { "core/player/session/signin/reply" },
    }],
    Query[{
        with = { "vault/github/signin", "Request" },
        optional = { "vault/github/signin/reply" },
    }],
    Commands,
}, function(views, carriers, scrolls, rows, texts, sites, githubs, commands)
    local view = views:iter_mut()[1]
    local carrier = carriers:iter()[1]
    local parts = view and scrolls:iter_descendants(view:id()) or {}
    local scroll = scrolls:iter_many(parts)[1]
    if carrier ~= nil and scroll ~= nil then
        local kids = carrier:get("Children") or {}

        local site_known, site_who, site_wish, site_said = false, nil, nil, nil
        for _, ask in ipairs(sites:iter_many(kids)) do
            local wish = ask:get("core/player/session/signin")
            local said = ask:has("core/player/session/signin/reply") and ask:get("core/player/session/signin/reply") or nil
            if wish.start or wish.sign_out then
                site_wish, site_said = wish, said
                if wish.start and said ~= nil and said.user ~= nil then
                    site_who = said.user.name or said.user.id
                end
            elseif said ~= nil then
                site_known = true
                if said.user ~= nil and site_who == nil then
                    site_who = said.user.name or said.user.id
                end
            end
        end

        local github_known, github_who, github_wish, github_said = false, nil, nil, nil
        for _, ask in ipairs(githubs:iter_many(kids)) do
            local wish = ask:get("vault/github/signin")
            local said = ask:has("vault/github/signin/reply") and ask:get("vault/github/signin/reply") or nil
            if wish.start or wish.sign_out then
                github_wish, github_said = wish, said
                if wish.start and said ~= nil and said.login ~= nil then
                    github_who = said.login
                end
            elseif said ~= nil then
                github_known = true
                if said.login ~= nil and github_who == nil then
                    github_who = said.login
                end
            end
        end

        local site = account("Hello!", site_known, site_who, site_wish, site_said)
        local github = account("GitHub", github_known, github_who, github_wish, github_said)

        local wanted = { "SIGN-INS" }
        for _, text in ipairs(texts_of(site)) do wanted[#wanted + 1] = text end
        for _, text in ipairs(texts_of(github)) do wanted[#wanted + 1] = text end
        local shown = {}
        local held = rows:iter_many(parts)
        for _, row in ipairs(held) do
            for _, line in ipairs(texts:iter_many(texts:iter_descendants_depth_first(row:id()))) do
                shown[#shown + 1] = line:get("Text")
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
            local header = commands:spawn({
                ["sidebar/profile/row"] = {},
                Node = { width = { Percent = 100 }, flex_shrink = 0, margin = { bottom = { Px = 6 } } },
                ChildOf = scroll:id(),
            }):id()
            commands:spawn({
                Text = { text = "SIGN-INS" },
                TextFont = { font_size = 10 },
                ["ui/style"] = { text = "text_dim" },
                ChildOf = header,
            })

            local site_button = spawn_account(commands, scroll:id(), site)
            if site_button ~= nil and site.label == "Sign in" then
                site_button:observe(On[Pointer[Click]], {
                    Query[{
                        with = { "sidebar/profile", "core/net/local" },
                        optional = { "Children" },
                    }],
                    Query[{ with = { "core/player/session/signin", "Request" } }],
                    Commands,
                }, function(_, owners, asks, click_commands)
                    for _, owner in ipairs(owners:iter()) do
                        for _, ask in ipairs(asks:iter_many(owner:get("Children") or {})) do
                            local wish = ask:get("core/player/session/signin")
                            if wish.start or wish.sign_out then
                                click_commands:entity(ask:id()):try_despawn()
                            end
                        end
                        click_commands:spawn({
                            ["core/player/session/signin"] = { start = true },
                            Request = {},
                            ["core/script/owner"] = false,
                            ChildOf = owner:id(),
                        })
                    end
                end)
            elseif site_button ~= nil then
                site_button:observe(On[Pointer[Click]], {
                    Query[{
                        with = { "sidebar/profile", "core/net/local" },
                        optional = { "Children" },
                    }],
                    Query[{ with = { "core/player/session/signin", "Request" } }],
                    Commands,
                }, function(_, owners, asks, click_commands)
                    for _, owner in ipairs(owners:iter()) do
                        for _, ask in ipairs(asks:iter_many(owner:get("Children") or {})) do
                            local wish = ask:get("core/player/session/signin")
                            if wish.start or wish.sign_out then
                                click_commands:entity(ask:id()):try_despawn()
                            end
                        end
                        click_commands:spawn({
                            ["core/player/session/signin"] = { sign_out = true },
                            Request = {},
                            ["core/script/owner"] = false,
                            ChildOf = owner:id(),
                        })
                    end
                end)
            end

            local github_button = spawn_account(commands, scroll:id(), github)
            if github_button ~= nil and github.label == "Sign in" then
                github_button:observe(On[Pointer[Click]], {
                    Query[{
                        with = { "sidebar/profile", "core/net/local" },
                        optional = { "Children" },
                    }],
                    Query[{ with = { "vault/github/signin", "Request" } }],
                    Commands,
                }, function(_, owners, asks, click_commands)
                    for _, owner in ipairs(owners:iter()) do
                        for _, ask in ipairs(asks:iter_many(owner:get("Children") or {})) do
                            local wish = ask:get("vault/github/signin")
                            if wish.start or wish.sign_out then
                                click_commands:entity(ask:id()):try_despawn()
                            end
                        end
                        click_commands:spawn({
                            ["vault/github/signin"] = { start = true },
                            Request = {},
                            ["core/script/owner"] = false,
                            ChildOf = owner:id(),
                        })
                    end
                end)
            elseif github_button ~= nil then
                github_button:observe(On[Pointer[Click]], {
                    Query[{
                        with = { "sidebar/profile", "core/net/local" },
                        optional = { "Children" },
                    }],
                    Query[{ with = { "vault/github/signin", "Request" } }],
                    Commands,
                }, function(_, owners, asks, click_commands)
                    for _, owner in ipairs(owners:iter()) do
                        for _, ask in ipairs(asks:iter_many(owner:get("Children") or {})) do
                            local wish = ask:get("vault/github/signin")
                            if wish.start or wish.sign_out then
                                click_commands:entity(ask:id()):try_despawn()
                            end
                        end
                        click_commands:spawn({
                            ["vault/github/signin"] = { sign_out = true },
                            Request = {},
                            ["core/script/owner"] = false,
                            ChildOf = owner:id(),
                        })
                    end
                end)
            end
        end

        if view:get("sidebar/panel").title == nil then
            view:get_mut("sidebar/panel").title = "Accounts"
        end
    end
end):in_set("sidebar/profile/render"):after("sidebar/profile/close"):run_if({
    Res[Time],
    Query[{ with = { "sidebar/profile/view" } }],
    Query[{ added = { "sidebar/panel/scroll" } }],
    Query[{ changed = { "core/player/session/signin/reply" } }],
    Query[{ changed = { "vault/github/signin/reply" } }],
    Query[{ changed = { "core/player/session/signin" } }],
    Query[{ changed = { "vault/github/signin" } }],
}, function(time, views, scrolls, site_replies, github_replies, site_asks, github_asks)
    -- A reply crosses from root, and an edge that crosses from another VM can be missed: while the
    -- panel is open it is looked at again twice a second.
    local t = time:elapsed_secs()
    return not views:is_empty() and (not scrolls:is_empty() or not site_replies:is_empty()
        or not github_replies:is_empty() or not site_asks:is_empty() or not github_asks:is_empty()
        or math.floor(t * 2) ~= math.floor((t - time:delta_secs()) * 2))
end)

return {}
