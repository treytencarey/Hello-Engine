-- The server carries `camera/3d` only so the chain reaches `camera`, whose sync it declares.
-- The eye and its offset are the client's view and are not synced.
return { base = "camera" }
