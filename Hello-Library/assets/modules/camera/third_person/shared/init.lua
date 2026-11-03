-- Its tuning, for both sides: the server's value is what crosses, and a value is whole.
return {
    base = "camera/3d",
    defaults = {
        ["camera/third_person"] = {
            sensitivity = 0.003,
            min_pitch = -1.2,
            max_pitch = 0.2,
            zoom_step = 0.5,
            min_distance = 2,
            max_distance = 20,
        },
    },
}
