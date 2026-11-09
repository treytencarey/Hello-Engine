-- The player's invites to other worlds: one card each, answered through root, and what follows an
-- accepted one. Root holds the Site session and answers; this mod asks it and shows what it says.
-- An accepted invite has root load the host's world join-only, then asks this world's server for a
-- portal to it on `git/panel/request`, the slot the player's panel asks on, and the server stands
-- it 3 m ahead of the player. Local UI: never synced.
--
-- sidebar/invites = {}
--
-- sidebar/invites/state = {
--     feedback = <the last thing an answer, its world or its portal said>,
--     feedback_kind = "ok" | "error" | "stale",
-- }
--
-- sidebar/invites/notification = {
--     invite_id = <the invite's id in root's list, or "debug-<n>">,
--     sender_login = <who sent it>,
--     scope_key = <the world it invites into>,
--     message = <the card's last line>,
-- }
--
-- sidebar/invites/notification/row = {}
--
-- sidebar/invites/request = {
--     op = "accept" | "decline" | "drop_portal",
--     invite_id = <the invite answered; none on a portal ask's record>,
--     scope_key = <its world>,
-- }

local On = require("bevy::ecs::prelude::On")
local Pointer = require("bevy::picking::prelude::Pointer")
local Click = require("bevy::picking::prelude::Click")

local function say(commands, carrier, kind, text)
    commands:entity(carrier):entry("sidebar/invites/state"):and_modify(function(state)
        state.feedback, state.feedback_kind = text, kind
    end)
end

-- The carrier asks root for its invites and keeps the ask open: root re-lists while one is open.
-- The ask carries nothing of this mod's and outlives a reload of it.
app:add_systems(First, {
    Query[{
        added = { "sidebar/invites" },
        optional = { "sidebar/invites/state", "Children" },
    }],
    Query[{
        removed = { "sidebar/invites/state" },
        with = { "sidebar/invites" },
    }],
    Query[{ with = { "core/registry/invites", "Request" } }],
    Commands,
}, function(carriers, stripped, lists, commands)
    for _, e in ipairs(carriers:iter()) do
        if not e:has("sidebar/invites/state") then
            commands:entity(e:id()):insert({ ["sidebar/invites/state"] = {} })
        end
        if #lists:iter_many(e:get("Children") or {}) == 0 then
            commands:spawn({
                ["core/registry/invites"] = {},
                Request = {},
                ["core/script/owner"] = false,
                ChildOf = e:id(),
            })
        end
    end
    -- `sidebar` taken off the player takes every `sidebar/` part with it, this state too.
    for _, e in ipairs(stripped:iter()) do
        commands:entity(e:id()):try_insert({ ["sidebar/invites/state"] = {} })
    end
end):in_set("sidebar/invites")

-- `sidebar/invites` taken off an entity that stays: its asks close. A hold still running goes with
-- its marker; one that ended waits only for root's answer, so it goes here. A despawned carrier
-- takes its children itself.
app:add_systems(First, {
    Query[{
        removed = { "sidebar/invites" },
        optional = { "Children" },
    }],
    Query[{ any_of = { "core/registry/invites", "core/world/load" } }],
    Query[{ with = { "core/registry/invites/answer", "Request", "ChildOf" } }],
    Query[{ with = { "sidebar/invites/request" } }],
    Commands,
}, function(removed, asks, answers, holds, commands)
    for _, e in ipairs(removed:iter()) do
        for _, ask in ipairs(asks:iter_many(e:get("Children") or {})) do
            commands:entity(ask:id()):try_despawn()
        end
        for _, answer in ipairs(answers:iter_many(answers:iter_descendants(e:id()))) do
            if not holds:contains(answer:get("ChildOf")) then
                commands:entity(answer:get("ChildOf")):try_despawn()
            end
        end
    end
end):in_set("sidebar/invites")

-- One card per invite in root's list, unless it was answered less than 30 s ago: root re-lists
-- every 20 s, so an answered invite stays listed for a while. A card whose invite left the list
-- fades out. A debug card is in no list.
app:add_systems(Update, {
    Query[{
        with = { "sidebar/invites" },
        optional = { "Children" },
    }],
    Query[{
        with = { "core/registry/invites", "Request" },
        without = { "RequestFrom", "WorldMirror" },
        optional = { "core/registry/invites/reply" },
    }],
    Query[{ with = { "sidebar/invites/request" } }],
    Query[{
        with = { "sidebar/invites/notification", Mut["notification"] },
        optional = { "notification/fade" },
    }],
    Commands,
}, function(carriers, lists, holds, cards, commands)
    local answered, listed, invites = false, {}, {}
    local held = {}
    for _, carrier in ipairs(carriers:iter()) do
        for _, ask in ipairs(lists:iter_many(carrier:get("Children") or {})) do
            if ask:has("core/registry/invites/reply") then
                answered = true
                for _, inv in ipairs(ask:get("core/registry/invites/reply").invites or {}) do
                    if inv.id ~= nil and not listed[inv.id] then
                        listed[inv.id] = true
                        invites[#invites + 1] = inv
                    end
                end
            end
        end
        for _, hold in ipairs(holds:iter_many(carrier:get("Children") or {})) do
            local r = hold:get("sidebar/invites/request")
            if r.invite_id ~= nil then held[r.invite_id] = true end
        end
    end
    local shown = {}
    for _, card in ipairs(cards:iter_mut()) do
        local inv = card:get("sidebar/invites/notification")
        shown[inv.invite_id] = true
        local debug = tostring(inv.invite_id):sub(1, 6) == "debug-"
        if answered and not debug and not listed[inv.invite_id] and not card:has("notification/fade")
            and not card:get("notification").dismiss then
            card:get_mut("notification").dismiss = true
        end
    end
    for _, inv in ipairs(invites) do
        if not shown[inv.id] and not held[inv.id] then
            commands:spawn({
                ["sidebar/invites/notification"] = {
                    invite_id = inv.id,
                    sender_login = inv.inviter,
                    scope_key = inv.scope,
                    message = "wants you in " .. tostring(inv.scope),
                },
                notification = {},
            })
        end
    end
end):in_set("sidebar/invites"):run_if({
    Query[{ changed = { "core/registry/invites/reply" } }],
    Query[{ removed = { "sidebar/invites/request" } }],
    Query[{ removed = { "sidebar/invites/notification" } }],
    Query[{ added = { "sidebar/invites" } }],
}, function(replies, holds_ended, cards_gone, carriers)
    return not replies:is_empty() or not holds_ended:is_empty() or not cards_gone:is_empty()
        or not carriers:is_empty()
end)

-- A card's content: what it says, then Accept and Decline. A click answers and starts the card's
-- exit at once. A real answer is held 30 s, a `cooldown` timer named after the hold's own
-- `sidebar/invites/request`, with root's request under it; a debug one is answered here.
-- A reload takes the rows this file spawned, and a card may outlive it under the overlay, so a
-- new carrier edge (a reload, or the player's arrival) redraws every card.
app:add_systems(Update, {
    Query[{
        changed = { "sidebar/invites/notification" },
        optional = { "Children" },
    }],
    Query[{ added = { "sidebar/invites" } }],
    Query[{
        with = { "sidebar/invites/notification" },
        optional = { "Children" },
    }],
    Query[{ with = { "sidebar/invites/notification/row" } }],
    Commands,
}, function(changed, arrived, cards, rows, commands)
    local redraw = arrived:is_empty() and changed:iter() or cards:iter()
    for _, card in ipairs(redraw) do
        local inv = card:get("sidebar/invites/notification")
        for _, row in ipairs(rows:iter_many(card:get("Children") or {})) do
            commands:entity(row:id()):try_despawn()
        end
        commands:spawn({
            ["sidebar/invites/notification/row"] = {},
            Text = { text = "INVITE" },
            TextFont = { font_size = 9 },
            ["ui/style"] = { text = "accent" },
            ChildOf = card:id(),
        })
        commands:spawn({
            ["sidebar/invites/notification/row"] = {},
            Text = { text = tostring(inv.sender_login or "someone") .. " invited you" },
            TextFont = { font_size = 12 },
            ["ui/style"] = { text = "text" },
            ChildOf = card:id(),
        })
        commands:spawn({
            ["sidebar/invites/notification/row"] = {},
            Text = { text = tostring(inv.scope_key or "") },
            TextFont = { font_size = 10 },
            ["ui/style"] = { text = "text_dim" },
            ChildOf = card:id(),
        })
        if inv.message ~= nil and inv.message ~= "" then
            commands:spawn({
                ["sidebar/invites/notification/row"] = {},
                Text = { text = tostring(inv.message) },
                TextFont = { font_size = 10 },
                ["ui/style"] = { text = "text_dim" },
                ChildOf = card:id(),
            })
        end
        local actions = commands:spawn({
            ["sidebar/invites/notification/row"] = {},
            Node = {
                width = { Percent = 100 },
                flex_direction = "Row",
                column_gap = { Px = 6 },
                margin = { top = { Px = 2 } },
            },
            ChildOf = card:id(),
        }):id()
        for _, choice in ipairs({
            { label = "Accept", role = "icon_active", action = "accept" },
            { label = "Decline", role = "icon_bg", action = "decline" },
        }) do
            local button = commands:spawn({
                Button = {},
                Node = {
                    flex_grow = 1,
                    height = { Px = 26 },
                    justify_content = "Center",
                    align_items = "Center",
                },
                BorderRadius = {
                    top_left = { Px = 4 }, top_right = { Px = 4 },
                    bottom_left = { Px = 4 }, bottom_right = { Px = 4 },
                },
                ["ui/style"] = { background = choice.role, hover = "row_hover" },
                ChildOf = actions,
            })
            commands:spawn({
                Text = { text = choice.label },
                TextFont = { font_size = 11 },
                ["ui/style"] = { text = "text" },
                ChildOf = button:id(),
            })
            local action = choice.action
            button:observe(On[Pointer[Click]], {
                Query[{ with = { "sidebar/invites", "core/net/local" } }],
                Query[{
                    with = { "sidebar/invites/notification", "notification" },
                    optional = { "notification/fade" },
                }],
                Commands,
            }, function(event, owners, notices, click_commands)
                local owner = owners:iter()[1]
                local notice = notices:iter_many(notices:iter_ancestors(event.entity))[1]
                if owner ~= nil and notice ~= nil then
                    local said = notice:get("sidebar/invites/notification")
                    local debug = tostring(said.invite_id):sub(1, 6) == "debug-"
                    if notice:has("notification/fade") or notice:get("notification").dismiss then
                        if debug then
                            say(click_commands, owner:id(), "stale", "That invite no longer exists")
                        end
                    else
                        click_commands:entity(notice:id()):entry("notification"):and_modify(function(n)
                            n.dismiss = true
                        end)
                        -- `cooldown` merges the component it is named after into this one, so its
                        -- fields stay readable while the hold runs, and go with it.
                        local hold = click_commands:spawn({
                            ["sidebar/invites/request"] = {
                                op = action,
                                invite_id = said.invite_id,
                                scope_key = said.scope_key,
                            },
                            cooldown = not debug and { ["sidebar/invites/request"] = { remaining = 30 } } or nil,
                            ["core/script/owner"] = false,
                            ChildOf = owner:id(),
                        }):id()
                        if not debug then
                            click_commands:spawn({
                                ["core/registry/invites/answer"] = { id = said.invite_id, action = action },
                                Request = {},
                                ["core/script/owner"] = false,
                                ChildOf = hold,
                            })
                        end
                    end
                end
            end)
        end
    end
end):in_set("sidebar/invites/render"):after("sidebar/invites"):run_if({
    Query[{ changed = { "sidebar/invites/notification" } }],
    Query[{ added = { "sidebar/invites" } }],
}, function(changed, arrived)
    return not changed:is_empty() or not arrived:is_empty()
end)

-- Root's answer lands on the card's own request. An accept has root load the host's world
-- join-only, never start it: an invite is a door. The answer goes with its hold once both are done.
app:add_systems(Update, {
    Query[{
        changed = { "core/registry/invites/answer/reply" },
        with = { "core/registry/invites/answer", "Request", "ChildOf" },
        without = { "RequestFrom", "WorldMirror" },
    }],
    Query[{
        with = { "sidebar/invites" },
        optional = { "Children" },
    }],
    Query[{ with = { "sidebar/invites/request" } }],
    Query[{ with = { "core/world/load" } }],
    Commands,
}, function(answers, carriers, holds, loads, commands)
    for _, ask in ipairs(answers:iter()) do
        local carrier = carriers:iter_many(carriers:iter_ancestors(ask:id()))[1]
        local said = ask:get("core/registry/invites/answer/reply")
        local wish = ask:get("core/registry/invites/answer")
        local hold = holds:get(ask:get("ChildOf"))
        if carrier ~= nil and (said.status == "ok" or said.status == "refused") then
            if said.status == "refused" then
                say(commands, carrier:id(), "error", said.reason == "sign-in-required" and "Sign in to answer invites"
                    or ("Invite " .. tostring(wish.action) .. " failed: " .. tostring(said.reason)))
            elseif wish.action == "accept" then
                local scope = said.scope or (hold and hold:get("sidebar/invites/request").scope_key)
                if scope ~= nil then
                    local loading = false
                    for _, load in ipairs(loads:iter_many(carrier:get("Children") or {})) do
                        loading = loading or load:get("core/world/load").scope == scope
                    end
                    if not loading then
                        commands:spawn({
                            ["core/world/load"] = { scope = scope, join_only = true },
                            WorldShared = {},
                            ["core/net/sync"] = false,
                            ["core/script/owner"] = false,
                            ChildOf = carrier:id(),
                        })
                    end
                    say(commands, carrier:id(), "ok", "Opening a door to " .. tostring(scope))
                end
            else
                say(commands, carrier:id(), "ok", "Invite declined")
            end
            if hold == nil then
                commands:entity(ask:get("ChildOf")):despawn()
            end
        end
    end
end):in_set("sidebar/invites")

-- A hold ended: it goes, with its request, once root has answered. The edge also comes for a hold
-- that despawned, which has no children left.
app:add_systems(Update, {
    Query[{
        removed = { "sidebar/invites/request" },
        with = { "ChildOf" },
        optional = { "Children" },
    }],
    Query[{
        with = { "core/registry/invites/answer", "Request" },
        without = { "RequestFrom", "WorldMirror" },
        optional = { "core/registry/invites/answer/reply" },
    }],
    Commands,
}, function(ended, asks, commands)
    for _, hold in ipairs(ended:iter()) do
        for _, ask in ipairs(asks:iter_many(hold:get("Children") or {})) do
            local said = ask:has("core/registry/invites/answer/reply") and ask:get("core/registry/invites/answer/reply") or {}
            if said.status == "ok" or said.status == "refused" then
                commands:entity(hold:id()):try_despawn()
            end
        end
    end
end):in_set("sidebar/invites")

-- The host's world is loaded (root's status on the carrier's own load ask), or a debug invite was
-- accepted: the world's server is asked for a portal to it, on `git/panel`'s request slot, and this
-- mod keeps a record of the ask until the server answers. The client checks what the server will,
-- and the server decides. A failed load says why, and its ask goes.
app:add_systems(Update, {
    Query[{
        changed = { "core/world/load" },
        with = { "ChildOf" },
    }],
    Query[{
        added = { "sidebar/invites/request" },
        with = { "ChildOf" },
    }],
    Query[{
        with = { "sidebar/invites" },
        optional = { "git/panel", "core/net/owner", "Children" },
    }],
    Query[{
        with = { "core/world/status" },
        without = { "WorldMirror" },
    }],
    Query[{
        with = { "scope/portal" },
        any_of = { "core/net/local", "core/net/owner" },
    }],
    Query[{ with = { "core/world/load" } }],
    Query[{ with = { "sidebar/invites/request" } }],
    Commands,
}, function(loads, answered, carriers, rows, portals, held, records, commands)
    local drops = {}
    for _, load in ipairs(loads:iter()) do
        local carrier = carriers:get(load:get("ChildOf"))
        local l = load:get("core/world/load")
        if carrier ~= nil and l.status == "ready" then
            drops[#drops + 1] = { carrier = carrier, scope = l.scope }
        elseif carrier ~= nil and l.status == "failed" then
            local ended = l.reason == "not-running" or l.reason == "no-gateway"
            say(commands, carrier:id(), ended and "stale" or "error",
                ended and "That world has ended" or ("Could not open that world: " .. tostring(l.reason)))
            commands:entity(load:id()):despawn()
        end
    end
    for _, hold in ipairs(answered:iter()) do
        local carrier = carriers:get(hold:get("ChildOf"))
        local r = hold:get("sidebar/invites/request")
        if carrier ~= nil and tostring(r.invite_id):sub(1, 6) == "debug-" then
            if r.op == "accept" then
                drops[#drops + 1] = { carrier = carrier, scope = r.scope_key }
            else
                say(commands, carrier:id(), "ok", "Invite declined")
            end
            commands:entity(hold:id()):despawn()
        end
    end

    local row = rows:iter()[1]
    local here = row and row:get("core/world/status").scope_key
    local asked = {}
    for _, drop in ipairs(drops) do
        local carrier, scope = drop.carrier, drop.scope
        local me = carrier:has("core/net/owner") and carrier:get("core/net/owner").client_id
        local mine, open = 0, false
        for _, p in ipairs(portals:iter()) do
            if p:has("core/net/local") or (me ~= nil and p:has("core/net/owner") and p:get("core/net/owner").client_id == me) then
                mine = mine + 1
                open = open or p:get("scope/portal").target == scope
            end
        end
        for _, record in ipairs(records:iter_many(carrier:get("Children") or {})) do
            local r = record:get("sidebar/invites/request")
            open = open or (r.op == "drop_portal" and r.scope_key == scope)
        end
        local why = ((here == nil or not carrier:has("git/panel")) and "No active scope to place a portal in")
            or (scope == here and "You are already in that world")
            or (mine >= 8 and "You have too many portals open")
            or nil
        if why ~= nil then
            say(commands, carrier:id(), "error", why)
            for _, load in ipairs(held:iter_many(carrier:get("Children") or {})) do
                if load:get("core/world/load").scope == scope then
                    commands:entity(load:id()):despawn()
                end
            end
        elseif not open and not asked[scope] then
            asked[scope] = true
            commands:entity(carrier:id()):insert({ ["git/panel/request"] = { op = "drop_portal", target_sk = scope } })
            commands:spawn({
                ["sidebar/invites/request"] = { op = "drop_portal", scope_key = scope },
                ["core/script/owner"] = false,
                ChildOf = carrier:id(),
            })
        end
    end
end):in_set("sidebar/invites")

-- The server answered this mod's portal ask on `git/panel/response`: opened says so; failed says the
-- cap, as the other checks passed here, and lets the world go. The record of the ask goes either way.
app:add_systems(Update, {
    Query[{
        changed = { "git/panel/response" },
        with = { "sidebar/invites" },
        optional = { "Children" },
    }],
    Query[{ with = { "sidebar/invites/request" } }],
    Query[{ with = { "core/world/load" } }],
    Commands,
}, function(answered, records, loads, commands)
    for _, carrier in ipairs(answered:iter()) do
        local said = carrier:get("git/panel/response")
        for _, record in ipairs(records:iter_many(carrier:get("Children") or {})) do
            local r = record:get("sidebar/invites/request")
            if r.op == "drop_portal" and said.op == "drop_portal" and said.scope == r.scope_key then
                if said.status == "opened" then
                    say(commands, carrier:id(), "ok", "Portal opened - walk through to join")
                else
                    say(commands, carrier:id(), "error", "You have too many portals open")
                    for _, load in ipairs(loads:iter_many(carrier:get("Children") or {})) do
                        if load:get("core/world/load").scope == r.scope_key then
                            commands:entity(load:id()):despawn()
                        end
                    end
                end
                commands:entity(record:id()):despawn()
            end
        end
    end
end):in_set("sidebar/invites")

-- The load ask lives while a portal of this player's names its world, so the observed world isn't
-- dropped between the two asks. Removal edges also come for entities that despawned.
app:add_systems(Update, {
    Query[{
        ["or"] = { removed = { "scope/portal" } },
        optional = { "scope/portal" },
    }],
    Query[{
        with = { "scope/portal" },
        optional = { "core/net/local", "core/net/owner" },
    }],
    Query[{
        with = { "sidebar/invites", "core/net/local" },
        optional = { "Children", "core/net/owner" },
    }],
    Query[{ with = { "core/world/load" } }],
    Commands,
}, function(gone, portals, carriers, loads, commands)
    for _, p in ipairs(gone:iter()) do
        local target = (p:get("scope/portal") or {}).target
        for _, carrier in ipairs(carriers:iter()) do
            local me = carrier:has("core/net/owner") and carrier:get("core/net/owner").client_id
            local still = false
            for _, q in ipairs(portals:iter()) do
                local owned = q:has("core/net/local")
                    or (me ~= nil and q:has("core/net/owner") and q:get("core/net/owner").client_id == me)
                still = still or (owned and q:get("scope/portal").target == target)
            end
            for _, load in ipairs(loads:iter_many(carrier:get("Children") or {})) do
                if not still and target ~= nil and load:get("core/world/load").scope == target then
                    commands:entity(load:id()):despawn()
                end
            end
        end
    end
end):in_set("sidebar/invites")

return {}
