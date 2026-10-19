-- The colors UI roles stand for, one theme per world. A theme mod (`ui/theme/dark`) extends
-- this one and writes its colors when `ui/theme` arrives; `ui/style` paints styled nodes from
-- it, and restyles them all when it changes. Without a theme, nothing is colored.
--
-- ui/theme = {
--     <role> = { r = <0..1>, g = <0..1>, b = <0..1>, a = <0..1> },
-- }

return {}
