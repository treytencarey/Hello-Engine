-- Publishes what an agent is thinking, so a client can draw it: its own component carries it across,
-- the one place an agent's insides reach the network. It is opt-in: put it on the agent. At each
-- thought it reads what the mods keep and decides nothing. It names no behaviour: what is chosen is
-- the `Name` the option entity gives itself.
--
-- ai/debug = {
--     chosen = <the chosen option's name, absent with none>,
--     vision_range = <metres>,
--     vision_fov_deg = <degrees>,
--     awareness_range = <metres>,
--     hearing_range = <metres>,
--     path = { { x, y, z }, ... }: what it has left to walk,
--     seen = { { x, y, z }, ... }: where it remembers seeing things,
--     sound = { { x, y, z }, ... }: where it remembers hearing things,
-- }

local function places(list, field)
    local out = {}
    for _, entry in ipairs(list) do
        local at = field and entry[field] or entry
        out[#out + 1] = { x = at.x, y = at.y, z = at.z }
    end
    return out
end

app:add_systems(Update, {
    Query[{
        changed = { "ai/agent/tick" },
        with = { "ai/agent/memory", Mut["ai/debug"] },
        optional = { "ai/agent/options", "ai/perception", "ai/nav/path", "ai/steering/state" },
    }],
    Query[{ with = { "ai/agent/chosen", "Name" } }],
}, function(agents, chosen)
    for _, a in ipairs(agents:iter_mut()) do
        local p = a:get("ai/perception") or {}
        local memory = a:get("ai/agent/memory")
        local option = chosen:iter_many(a:get("ai/agent/options") or {})[1]

        local path = a:get("ai/nav/path")
        local steer = a:get("ai/steering/state")
        local left = {}
        if path ~= nil and path.path ~= nil then
            local cursor = steer ~= nil and steer.for_solved == path.solved_id and steer.cursor or 1
            for i = cursor, #path.path do
                left[#left + 1] = path.path[i]
            end
        end

        a:set({
            ["ai/debug"] = {
                chosen = option and option:get("Name").name,
                vision_range = p.vision_range,
                vision_fov_deg = p.vision_fov_deg,
                awareness_range = p.awareness_range,
                hearing_range = p.hearing_range,
                path = places(left),
                seen = places(memory.seen, "at"),
                sound = places(memory.sound, "at"),
            },
        })
    end
end):in_set("ai/debug/publish")

return {
    ["core/net/sync"] = {
        authority = "server",
    },
}
