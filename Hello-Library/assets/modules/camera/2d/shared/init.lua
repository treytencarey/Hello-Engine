-- Its tuning, for both sides: the server's value is what crosses, and a value is whole.
return {
    base = "camera",
    defaults = {
        ["camera/2d"] = {
            zoom_step = 0.1,
            min_distance = 0.25,
            max_distance = 4,
            z = 1000,
        },
    },
}
