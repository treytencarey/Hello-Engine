-- git/merge/notice: what happened to an edit, said to the person who made it. A plain-text
-- notification: a title and a line, both read off its own component. Local UI: never synced.
--
-- git/merge/notice = {
--     title = <a word or two>,
--     text = <the line>,
-- }
--
-- git/merge/notice/row: each line, a child of the notice.

-- A changed notice is drawn again: its old lines go, and the new ones take their place.
app:add_systems(First, {
    Query[{
        changed = { "git/merge/notice" },
        optional = { "Children" },
    }],
    Query[{ with = { "git/merge/notice/row" } }],
    Commands,
}, function(notices, rows, commands)
    for _, e in ipairs(notices:iter()) do
        local notice = e:get("git/merge/notice")
        for _, row in ipairs(rows:iter_many(e:get("Children") or {})) do
            commands:entity(row:id()):try_despawn()
        end
        commands:spawn({
            ["git/merge/notice/row"] = {},
            Text = { text = notice.title },
            TextFont = { font_size = 9 },
            ["ui/style"] = { text = "accent" },
            ChildOf = e:id(),
        })
        commands:spawn({
            ["git/merge/notice/row"] = {},
            Text = { text = notice.text },
            TextFont = { font_size = 11 },
            ["ui/style"] = { text = "text" },
            ChildOf = e:id(),
        })
    end
end):in_set("git/merge/notice")

return {
    base = "notification",
    defaults = {
        ["git/merge/notice"] = { title = "EDIT", text = "" },
    },
}
