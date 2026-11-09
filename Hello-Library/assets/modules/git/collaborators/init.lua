-- A sidebar panel, "Collaborators", for one repository's collaborators, with an Invite button on
-- each row that asks root to invite that person into this world. The repository is the one
-- git/panel has chosen, else this world's own. Root holds every token and makes every call; the
-- panel asks it and shows what it answers. Local UI: never synced.
--
-- git/collaborators = {}
--
-- git/collaborators/state = {
--     open = <whether the panel is open>,
-- }
--
-- git/collaborators/button = {}
-- git/collaborators/view = {}
-- git/collaborators/row = {}

local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")
local Time = require("bevy::time::Time")

-- On, the player's own row gets "Debug", which makes a local invite card to a fresh branch of this
-- world's repository, so the accept path can be tried with one account. Off when committed.
local DEBUG_INVITES = false

-- The repository the panel lists, as owner and name, and whether it is this world's own: the
-- one git/panel chose, else the one this world's row names.
local function listed(choice, row)
    local own = row and row:get("core/world/status").scope_root
    local owner, name = tostring(own or ""):match("^github:([^/]+)/(.+)$")
    local repo = choice and choice.repo
    if repo and repo.owner ~= nil and repo.name ~= nil then
        local same = owner ~= nil and tostring(repo.owner):lower() == owner and tostring(repo.name):lower() == name
        return repo.owner, repo.name, same
    end
    return owner, name, owner ~= nil
end

-- A login as GitHub compares them: without case or a leading "@".
local function plain(login)
    return (tostring(login or ""):gsub("^@", ""):lower())
end

app:add_systems(First, {
    Query[{
        added = { "git/collaborators" },
        optional = { "git/collaborators/state" },
    }],
    Commands,
}, function(carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        if not e:has("git/collaborators/state") then
            commands:entity(e:id()):insert({ ["git/collaborators/state"] = { open = false } })
        end
    end
end):in_set("git/collaborators")

-- `git/collaborators` taken off an entity that stays: its sends close. A despawned carrier takes its
-- children itself, and the panel's own asks go with the panel.
app:add_systems(First, {
    Query[{
        removed = { "git/collaborators" },
        optional = { "Children" },
    }],
    Query[{ with = { "core/registry/invites/send", "Request" } }],
    Commands,
}, function(removed, sends, commands)
    for _, e in ipairs(removed:iter()) do
        for _, ask in ipairs(sends:iter_many(e:get("Children") or {})) do
            commands:entity(ask:id()):try_despawn()
        end
    end
end):in_set("git/collaborators")

-- The button goes in the bar for a local player with the panel: on a new bar (the sidebar built
-- or reloaded), and on the panel itself (added, or this mod reloaded).
app:add_systems(Update, {
    Query[{ with = { "git/collaborators", "core/net/local" } }],
    Query[{ with = { "sidebar/bar" } }],
    Query[{ with = { "git/collaborators/button" } }],
    Commands,
}, function(carriers, bars, buttons, commands)
    local bar = bars:iter()[1]
    if bar ~= nil and not carriers:is_empty() and buttons:is_empty() then
        commands:spawn({
            ["sidebar/button"] = { title = "Collaborators", order = 4 },
            ["git/collaborators/button"] = {},
            ChildOf = bar:id(),
        })
    end
end):in_set("git/collaborators"):run_if({
    Query[{ added = { "sidebar/bar" } }],
    Query[{
        ["or"] = {
            added = { "git/collaborators", "core/net/local" },
        },
        with = { "git/collaborators", "core/net/local" },
    }],
}, function(new_bars, new_carriers)
    return not new_bars:is_empty() or not new_carriers:is_empty()
end)

-- A new button that was open before a reload opens again, by the path a click takes, once the
-- sidebar has made it an icon.
app:add_systems(Update, {
    Query[{
        added = { "Node" },
        with = { "git/collaborators/button" },
    }],
    Query[{ with = { "git/collaborators", "git/collaborators/state" } }],
    Query[{ with = { "sidebar/button/open" } }],
    Commands,
}, function(icons, carriers, open_buttons, commands)
    for _, icon in ipairs(icons:iter()) do
        local carrier = carriers:iter()[1]
        local state = carrier and carrier:get("git/collaborators/state")
        if state ~= nil and state.open then
            local order = 0
            for _, o in ipairs(open_buttons:iter()) do
                order = math.max(order, o:get("sidebar/button/open").order)
            end
            commands:entity(icon:id()):insert({ ["sidebar/button/open"] = { order = order + 1 } })
        end
    end
end):in_set("git/collaborators")

-- Opened: the panel goes in the container, with the asks it shows from as its children, so they
-- close with it. They are not the carrier's: the player's other panels hold asks of the same
-- shape there.
app:add_systems(Update, {
    Query[{
        added = { "sidebar/button/open" },
        with = { "git/collaborators/button" },
    }],
    Query[{ with = { "sidebar/container" } }],
    Query[{ with = { "git/collaborators", Mut["git/collaborators/state"] } }],
    Commands,
}, function(opened, containers, carriers, commands)
    for _, _ in ipairs(opened:iter()) do
        local container = containers:iter()[1]
        local carrier = carriers:iter_mut()[1]
        if container ~= nil and carrier ~= nil then
            local view = commands:spawn({
                ["sidebar/panel"] = { width = 280 },
                ["git/collaborators/view"] = {},
                ChildOf = container:id(),
            }):id()
            commands:spawn({ ["vault/github/signin"] = {}, Request = {}, ["core/script/owner"] = false, ChildOf = view })
            commands:spawn({ ["core/registry/invites"] = {}, Request = {}, ["core/script/owner"] = false, ChildOf = view })
            if not carrier:get("git/collaborators/state").open then
                carrier:get_mut("git/collaborators/state").open = true
            end
        end
    end
end):in_set("git/collaborators")

-- Only a button still here closing is someone closing the panel. A reload takes the button too,
-- and its edge comes the same: that closes nothing, because the panel is to come back.
app:add_systems(Update, {
    Query[{
        removed = { "sidebar/button/open" },
        with = { "git/collaborators/button" },
    }],
    Query[{ with = { "git/collaborators/button" } }],
    Query[{ with = { "git/collaborators/view" } }],
    Query[{ with = { Mut["git/collaborators/state"] } }],
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
            row:get_mut("git/collaborators/state").open = false
        end
    end
end):in_set("git/collaborators")

-- The panel asks root for the listed repository's collaborators, again when that repository
-- changes: git/panel chose another, or this world's row moved.
app:add_systems(Update, {
    Query[{
        with = { "git/collaborators/view" },
        optional = { "Children" },
    }],
    Query[{
        with = { "git/collaborators" },
        optional = { "git/panel/state" },
    }],
    Query[{
        with = { "core/world/status" },
        without = { "WorldMirror" },
    }],
    Query[{ with = { "vault/github/repos", "Request" } }],
    Commands,
}, function(views, carriers, rows, repos, commands)
    local carrier = carriers:iter()[1]
    local owner, name = listed(carrier and carrier:has("git/panel/state") and carrier:get("git/panel/state"), rows:iter()[1])
    for _, view in ipairs(views:iter()) do
        local kept = false
        for _, ask in ipairs(repos:iter_many(view:get("Children") or {})) do
            local wish = ask:get("vault/github/repos")
            if not kept and owner ~= nil and wish.owner == owner and wish.name == name then
                kept = true
            else
                commands:entity(ask:id()):despawn()
            end
        end
        if owner ~= nil and not kept then
            commands:spawn({
                ["vault/github/repos"] = { owner = owner, name = name },
                Request = {},
                ["core/script/owner"] = false,
                ChildOf = view:id(),
            })
        end
    end
end):in_set("git/collaborators"):run_if({
    Query[{ added = { "git/collaborators/view" } }],
    Query[{ changed = { "git/panel/state" } }],
    Query[{ removed = { "git/panel/state" } }],
    Query[{
        changed = { "core/world/status" },
        without = { "WorldMirror" },
    }],
}, function(views, choices, unchosen, rows)
    return not views:is_empty() or not choices:is_empty() or not unchosen:is_empty() or not rows:is_empty()
end)

-- The rows, rebuilt from root's replies on their edges. An Invite click asks root on a new request
-- and closes the last one for that login; root takes a send only into the asker's own repository,
-- so a list of another repository has no buttons.
app:add_systems(Update, {
    Query[{
        with = { "git/collaborators/view", Mut["sidebar/panel"] },
        optional = { "Children" },
    }],
    Query[{
        with = { "git/collaborators", "git/collaborators/state" },
        optional = { "git/panel/state", "sidebar/invites/state", "Children" },
    }],
    Query[{
        with = { "core/world/status" },
        without = { "WorldMirror" },
    }],
    Query[{ with = { "sidebar/panel/scroll" } }],
    Query[{ with = { "git/collaborators/row" } }],
    Query[{
        with = { "vault/github/signin", "Request" },
        optional = { "vault/github/signin/reply" },
    }],
    Query[{
        with = { "core/registry/invites", "Request" },
        optional = { "core/registry/invites/reply" },
    }],
    Query[{
        with = { "vault/github/repos", "Request" },
        optional = { "vault/github/repos/reply" },
    }],
    Query[{
        with = { "core/registry/invites/send", "Request" },
        optional = { "core/registry/invites/send/reply" },
    }],
    Commands,
}, function(views, carriers, rows, scrolls, shown, signins, lists, repos, sends, commands)
    local view = views:iter_mut()[1]
    local carrier = carriers:iter()[1]
    local parts = view and scrolls:iter_descendants(view:id()) or {}
    local scroll = scrolls:iter_many(parts)[1]
    if carrier ~= nil and scroll ~= nil then
        local asks = view:get("Children") or {}
        local known, me = false, nil
        for _, ask in ipairs(signins:iter_many(asks)) do
            if ask:has("vault/github/signin/reply") then
                known, me = true, ask:get("vault/github/signin/reply").login
            end
        end
        local list = nil
        for _, ask in ipairs(lists:iter_many(asks)) do
            if ask:has("core/registry/invites/reply") then list = ask:get("core/registry/invites/reply") end
        end
        local row = rows:iter()[1]
        local owner, name, own = listed(carrier:has("git/panel/state") and carrier:get("git/panel/state"), row)
        local said = nil
        for _, ask in ipairs(repos:iter_many(asks)) do
            local wish = ask:get("vault/github/repos")
            if wish.owner == owner and wish.name == name and ask:has("vault/github/repos/reply") then
                said = ask:get("vault/github/repos/reply")
            end
        end
        local sent = sends:iter_many(carrier:get("Children") or {})

        for _, old in ipairs(shown:iter_many(parts)) do
            commands:entity(old:id()):despawn()
        end
        local function line(text, role, size)
            commands:spawn({
                ["git/collaborators/row"] = {},
                Text = { text = text },
                TextFont = { font_size = size },
                Node = { margin = { top = { Px = 8 }, bottom = { Px = 4 } }, padding = { left = { Px = 8 }, right = { Px = 8 } } },
                ["ui/style"] = { text = role },
                ChildOf = scroll:id(),
            })
        end

        local collaborators = said and said.collaborators or {}
        if owner == nil then
            line("No repository selected.", "text_dim", 12)
        elseif known and me == nil then
            line("Sign in to GitHub in Accounts", "text_dim", 12)
        elseif said == nil then
            line("Loading collaborators...", "text_dim", 12)
        elseif said.error ~= nil then
            line("Error: " .. tostring(said.error), "text_bad", 11)
        elseif #collaborators == 0 then
            line("No collaborators found.", "text_dim", 12)
        else
            line(string.format("COLLABORATORS (%d)", #collaborators), "text_dim", 10)

            -- What the website says, then the last send's result, then what an invite of the
            -- player's own said (sidebar/invites).
            local online = list ~= nil and list.error == nil
            if list == nil then
                line("Checking website...", "text_dim", 10)
            elseif list.error == "sign-in-required" then
                line("Sign in on the Profile panel to send invites", "text_bad", 10)
            elseif list.error ~= nil then
                line("Website offline - invites unavailable", "text_dim", 10)
            end
            local last = sent[#sent]
            if online and last ~= nil then
                local wish = last:get("core/registry/invites/send")
                local reply = last:has("core/registry/invites/send/reply") and last:get("core/registry/invites/send/reply") or {}
                if reply.status == "ok" then
                    line("Invited " .. tostring(wish.invitee), "accent", 10)
                elseif reply.status ~= "refused" then
                    line("Inviting " .. tostring(wish.invitee) .. "...", "accent", 10)
                elseif reply.reason == "not-a-collaborator" then
                    line("Only collaborators of this world can invite", "text_bad", 10)
                elseif reply.reason == "sign-in-required" then
                    line("Sign in on the Profile panel to send invites", "text_bad", 10)
                else
                    line("Invite failed: " .. tostring(reply.reason), "text_bad", 10)
                end
            end
            local invites = carrier:has("sidebar/invites/state") and carrier:get("sidebar/invites/state") or {}
            if invites.feedback ~= nil and invites.feedback ~= "" then
                line(tostring(invites.feedback), invites.feedback_kind == "ok" and "accent"
                    or (invites.feedback_kind == "error" and "text_bad" or "text_dim"), 10)
            end

            local busy = {}
            for _, ask in ipairs(sent) do
                local reply = ask:has("core/registry/invites/send/reply") and ask:get("core/registry/invites/send/reply") or {}
                if reply.status ~= "ok" and reply.status ~= "refused" then
                    busy[plain(ask:get("core/registry/invites/send").invitee)] = true
                end
            end

            for i, c in ipairs(collaborators) do
                local entry = commands:spawn({
                    ["git/collaborators/row"] = {},
                    Node = {
                        width = { Percent = 100 },
                        height = { Px = 40 },
                        flex_shrink = 0,
                        flex_direction = "Row",
                        align_items = "Center",
                        column_gap = { Px = 8 },
                        padding = { left = { Px = 8 }, right = { Px = 8 } },
                    },
                    ["ui/style"] = { background = i % 2 == 0 and "row_alt" or "row_bg" },
                    ChildOf = scroll:id(),
                }):id()
                -- The avatar's circle holds the login's first letter; an image would go inside it.
                local avatar = commands:spawn({
                    Node = {
                        width = { Px = 28 },
                        height = { Px = 28 },
                        flex_shrink = 0,
                        justify_content = "Center",
                        align_items = "Center",
                    },
                    BorderRadius = {
                        top_left = { Px = 14 }, top_right = { Px = 14 },
                        bottom_left = { Px = 14 }, bottom_right = { Px = 14 },
                    },
                    ["ui/style"] = { background = "icon_active" },
                    ChildOf = entry,
                }):id()
                commands:spawn({
                    Text = { text = (tostring(c.login ~= "" and c.login or "?")):sub(1, 1):upper() },
                    TextFont = { font_size = 13 },
                    ["ui/style"] = { text = "text" },
                    ChildOf = avatar,
                })
                local info = commands:spawn({
                    Node = {
                        flex_grow = 1,
                        flex_direction = "Column",
                        justify_content = "Center",
                        row_gap = { Px = 1 },
                        overflow = { x = "Hidden", y = "Hidden" },
                    },
                    ChildOf = entry,
                }):id()
                commands:spawn({
                    Text = { text = tostring(c.login) },
                    TextFont = { font_size = 12 },
                    ["ui/style"] = { text = "text" },
                    ChildOf = info,
                })
                commands:spawn({
                    Text = { text = tostring(c.role or "collaborator") },
                    TextFont = { font_size = 9 },
                    ["ui/style"] = { text = c.role == "admin" and "accent" or "text_dim" },
                    ChildOf = info,
                })

                -- Buttons follow the info column; the row has room for more after Invite.
                local self_row = me ~= nil and plain(c.login) == plain(me)
                if c.github_id ~= nil and own and (not self_row or DEBUG_INVITES) then
                    local enabled = self_row or (online and not busy[plain(c.login)])
                    local button = commands:spawn({
                        Button = {},
                        Node = {
                            width = { Px = 58 },
                            height = { Px = 24 },
                            flex_shrink = 0,
                            justify_content = "Center",
                            align_items = "Center",
                            border = { left = { Px = 1 }, right = { Px = 1 }, top = { Px = 1 }, bottom = { Px = 1 } },
                        },
                        BorderRadius = {
                            top_left = { Px = 4 }, top_right = { Px = 4 },
                            bottom_left = { Px = 4 }, bottom_right = { Px = 4 },
                        },
                        ["ui/style"] = {
                            background = enabled and "icon_bg" or "row_alt",
                            hover = enabled and "icon_hover" or nil,
                            border = "border",
                        },
                        ChildOf = entry,
                    })
                    commands:spawn({
                        Text = { text = self_row and "Debug" or "Invite" },
                        TextFont = { font_size = 11 },
                        ["ui/style"] = { text = enabled and "text" or "text_dim" },
                        ChildOf = button:id(),
                    })
                    local login = c.login
                    if enabled and self_row then
                        button:observe(On[Pointer[Click]], {
                            Res[Time],
                            Query[{
                                with = { "core/world/status" },
                                without = { "WorldMirror" },
                            }],
                            Commands,
                        }, function(_, time, here, click_commands)
                            local world_row = here:iter()[1]
                            local n = math.floor(time:elapsed_secs() * 1000)
                            if world_row ~= nil then
                                click_commands:spawn({
                                    ["sidebar/invites/notification"] = {
                                        invite_id = "debug-" .. n,
                                        sender_login = "you (debug)",
                                        scope_key = tostring(world_row:get("core/world/status").scope_root) .. ":debug-hub-" .. n,
                                        message = "Debug invite to a fresh hub world",
                                    },
                                    notification = {},
                                })
                            end
                        end)
                    elseif enabled then
                        button:observe(On[Pointer[Click]], {
                            Query[{
                                with = { "git/collaborators", "core/net/local" },
                                optional = { "Children" },
                            }],
                            Query[{ with = { "core/registry/invites/send", "Request" } }],
                            Query[{
                                with = { "core/world/status" },
                                without = { "WorldMirror" },
                            }],
                            Commands,
                        }, function(_, owners, open_sends, here, click_commands)
                            local world_row = here:iter()[1]
                            for _, owner in ipairs(owners:iter()) do
                                for _, ask in ipairs(open_sends:iter_many(owner:get("Children") or {})) do
                                    if plain(ask:get("core/registry/invites/send").invitee) == plain(login) then
                                        click_commands:entity(ask:id()):try_despawn()
                                    end
                                end
                                if world_row ~= nil then
                                    click_commands:spawn({
                                        ["core/registry/invites/send"] = {
                                            scope = world_row:get("core/world/status").scope_key,
                                            invitee = login,
                                        },
                                        Request = {},
                                        ["core/script/owner"] = false,
                                        ChildOf = owner:id(),
                                    })
                                end
                            end
                        end)
                    end
                end
            end
        end

        if view:get("sidebar/panel").title == nil then
            view:get_mut("sidebar/panel").title = "Collaborators"
        end
    end
end):in_set("git/collaborators/render"):after("git/collaborators"):run_if({
    Query[{ with = { "git/collaborators/view" } }],
    Query[{ added = { "sidebar/panel/scroll" } }],
    Query[{ changed = { "vault/github/repos" } }],
    Query[{ changed = { "vault/github/repos/reply" } }],
    Query[{ changed = { "vault/github/signin/reply" } }],
    Query[{ changed = { "core/registry/invites/reply" } }],
    Query[{ changed = { "core/registry/invites/send" } }],
    Query[{ changed = { "core/registry/invites/send/reply" } }],
    Query[{ removed = { "core/registry/invites/send" } }],
    Query[{ changed = { "sidebar/invites/state" } }],
    Query[{ changed = { "git/panel/state" } }],
    Query[{ removed = { "git/panel/state" } }],
    Query[{
        changed = { "core/world/status" },
        without = { "WorldMirror" },
    }],
}, function(views, scrolls, asks, repos, signins, lists, sends, sent, closed, invites, choices, unchosen, rows)
    return not views:is_empty() and (not scrolls:is_empty() or not asks:is_empty() or not repos:is_empty()
        or not signins:is_empty() or not lists:is_empty() or not sends:is_empty() or not sent:is_empty()
        or not closed:is_empty() or not invites:is_empty() or not choices:is_empty() or not unchosen:is_empty()
        or not rows:is_empty())
end)

return {}
