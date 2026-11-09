-- The server half of the "GitHub" panel: what the owner asks of this world's server, on a slot only
-- the owner writes, and the answer, which only the owner hears. A portal it opens is the world's:
-- everyone sees it, and the owner places it. It builds no UI.
--
-- git/panel = {}
--
-- git/panel/request = {
--     op = "portal",
--     target_sk = <the scope key of the world the portal leads to>,
-- }
--
-- git/panel/response = {
--     op = "portal",
--     scope = <the target asked for>,
--     status = "opened" | "failed",
--     message = <why, when failed>,
-- }

-- `git/panel` is on the player, which everyone sees: the slot and its answer reach the owner alone.
app:add_systems(First, {
    Query[{
        added = { "git/panel" },
        with = { "core/net/sync" },
    }],
    Commands,
}, function(carriers, commands)
    for _, e in ipairs(carriers:iter()) do
        if type(e:get("core/net/sync")) == "table" then
            commands:entity(e:id()):entry("core/net/sync"):and_modify(function(sync)
                sync["git/panel/request"] = { authority = "client", target = "owner" }
                sync["git/panel/response"] = { authority = "server", target = "owner" }
            end)
        end
    end
end):in_set("git/panel/server")

-- `git/panel` taken off an entity that stays: the sync this half added goes. A despawned carrier has
-- no row in `synced`.
app:add_systems(First, {
    Query[{ removed = { "git/panel" } }],
    Query[{ with = { "core/net/sync" } }],
    Commands,
}, function(removed, synced, commands)
    local gone = {}
    for _, e in ipairs(removed:iter()) do
        gone[#gone + 1] = e:id()
    end
    for _, e in ipairs(synced:iter_many(gone)) do
        if type(e:get("core/net/sync")) == "table" then
            commands:entity(e:id()):entry("core/net/sync"):and_modify(function(sync)
                sync["git/panel/request"] = nil
                sync["git/panel/response"] = nil
            end)
        end
    end
end):in_set("git/panel/server")

-- The ask is the owner's word: only the target is taken from it, and only a string of bounded length
-- naming another world than this one. Root canonicalizes the target when a client's view observes
-- it, so a target root refuses ends as a locked portal with root's reason. The cap counts the portals
-- the owner holds here, and those this run opened. The answer stands until the owner takes its ask
-- back, and then goes. An ask the standing answer already answers is not answered again: a reload
-- of this file runs the system over every standing ask.
app:add_systems(Update, {
    Query[{
        changed = { "git/panel/request" },
        with = { "git/panel", "core/net/owner" },
        without = { "WorldMirror", "core/net/peer/mirror" },
        optional = { "git/panel/response", "Transform" },
    }],
    Query[{ with = { "scope/portal", "core/net/owner" } }],
    Query[{
        with = { "core/world/status", "WorldShared" },
        without = { "WorldMirror" },
    }],
    Commands,
}, function(asking, portals, rows, commands)
    local me = rows:iter()[1]
    local mine = me and me:get("core/world/status").scope_key
    local held = {}
    for _, p in ipairs(portals:iter()) do
        local client_id = p:get("core/net/owner").client_id
        held[client_id] = (held[client_id] or 0) + 1
    end
    for _, e in ipairs(asking:iter()) do
        local ask = e:get("git/panel/request")
        local said = e:has("git/panel/response") and e:get("git/panel/response") or {}
        local client_id = e:get("core/net/owner").client_id
        local op = type(ask) == "table" and ask.op or nil
        if op == nil then
            if said.op ~= nil then
                commands:entity(e:id()):insert({ ["git/panel/response"] = {} })
            end
        elseif op == "portal" and not (said.op == "portal" and said.scope == ask.target_sk) then
            local target = ask.target_sk
            local named = type(target) == "string" and target ~= "" and #target <= 512
            local why = (not named and "not a scope key")
                or (target == mine and "this world's own scope")
                or ((held[client_id] or 0) >= 8 and "8 portals already")
                or nil
            if why ~= nil then
                commands:entity(e:id()):insert({
                    ["git/panel/response"] = {
                        op = "portal",
                        scope = named and target or nil,
                        status = "failed",
                        message = why,
                    },
                })
                print(string.format("[GIT/PANEL] client %s's portal refused: %s", tostring(client_id), why))
            else
                held[client_id] = (held[client_id] or 0) + 1
                local at = e:has("Transform") and e:get("Transform").translation or { x = 0, y = 0, z = 0 }
                commands:spawn({
                    ["scope/portal"] = { target = target },
                    ["scope/portal/view"] = { mode = "3d" },
                    placement = {},
                    Transform = { translation = { x = at.x, y = at.y, z = at.z } },
                    ["core/net/owner"] = { client_id = client_id },
                    ["core/net/sync"] = {
                        placement = { authority = "client" },
                        Transform = { authority = "client", reliable = false },
                        ["scope/portal"] = { authority = "server" },
                        ["scope/portal/view"] = { authority = "server" },
                        ["scope/portal/hosted"] = { authority = "server" },
                    },
                    ["core/script/owner"] = false,
                })
                commands:entity(e:id()):insert({
                    ["git/panel/response"] = { op = "portal", scope = target, status = "opened" },
                })
                print(string.format("[GIT/PANEL] client %s opened a portal to %s", tostring(client_id), target))
            end
        end
    end
end):in_set("git/panel/server")

return {
    ["core/net/sync"] = {
        authority = "server",
        target = "owner",
    },
}
