-- The client half of a console: this client's copy of a door follows the server's record of its
-- re-point, and goes back to its authored value when the record goes. Each side spawns its own copy
-- of the scene, so the door's `Name` is what the record names.

local Door = require("modules/scope/portal/console/shared/door.lua")

-- On a record's arrival or change, and on a door arriving (a late scene, one written again), the
-- door takes the record's target and `at`. Written only when it differs: the view asks again on
-- every change.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            added = { "scope/portal/console/target" },
            changed = { "scope/portal/console/target" },
        },
    }],
    Query[{
        added = { "scope/portal" },
        with = { "Name" },
        without = { "placement" },
    }],
    Query[{
        with = { Mut["scope/portal"], "Name" },
        without = { "placement" },
    }],
    Query[{ with = { "scope/portal/console/target" } }],
}, function(changed, arrived, doors, records)
    local wanted = {}
    for _, r in ipairs(records:iter()) do
        local record = r:get("scope/portal/console/target")
        wanted[record.door] = record
    end
    local touched = {}
    for _, r in ipairs(changed:iter()) do
        local record = r:get("scope/portal/console/target")
        touched[record.door] = true
    end
    for _, d in ipairs(doors:iter_mut()) do
        local name = d:get("Name").name
        local record = wanted[name]
        if record ~= nil and (touched[name] or arrived:contains(d:id())) then
            local portal = d:get("scope/portal")
            if portal.target ~= record.target or portal.at ~= record.at then
                local p = d:get_mut("scope/portal")
                p.target, p.at = record.target, record.at
            end
        end
    end
end):in_set("scope/portal/console/client"):run_if({
    Query[{
        ["or"] = {
            added = { "scope/portal/console/target" },
            changed = { "scope/portal/console/target" },
        },
    }],
    Query[{
        added = { "scope/portal" },
        with = { "Name" },
        without = { "placement" },
    }],
}, function(changed, arrived)
    return not (changed:is_empty() and arrived:is_empty())
end)

-- A record gone (the door pointed back, or the server stopping): the door named in its last value
-- takes its authored value again, unless another record names it now.
app:add_systems(Update, {
    Query[{
        ["or"] = {
            removed = { "scope/portal/console/target" },
        },
        optional = { "scope/portal/console/target" },
    }],
    Query[{
        with = { Mut["scope/portal"], "Name" },
        without = { "placement" },
        optional = { "GltfExtras" },
    }],
    Query[{ with = { "scope/portal/console/target" } }],
}, function(gone, doors, records)
    local named = {}
    for _, r in ipairs(gone:iter()) do
        local was = r:get("scope/portal/console/target")
        if was ~= nil then named[was.door] = true end
    end
    for _, r in ipairs(records:iter()) do
        named[r:get("scope/portal/console/target").door] = nil
    end
    for _, d in ipairs(doors:iter_mut()) do
        if named[d:get("Name").name] then
            local authored = Door.authored(d)
            local portal = d:get("scope/portal")
            if authored ~= nil and (portal.target ~= authored.target or portal.at ~= authored.at) then
                local p = d:get_mut("scope/portal")
                p.target, p.at = authored.target, authored.at
            end
        end
    end
end):in_set("scope/portal/console/client")
