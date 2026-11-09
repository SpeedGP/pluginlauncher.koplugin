-- Same conventions as KOReader's own .luacheckrc.
std = "luajit"
unused_args = false
self = false

globals = {
    "G_reader_settings",
}

ignore = {
    "211/__*", -- unused local variable
    "231/__",  -- local variable is set but never accessed
    "631",     -- line is too long
}

-- The tests reuse a few variables on purpose.
files["spec/*.lua"] = {
    ignore = { "211", "311", "421", "431" },
}
