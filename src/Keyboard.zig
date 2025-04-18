pub const Keyboard = @This();

const xkb = @cImport({
    @cInclude("xkbcommon/xkbcommon.h");
});

const keycode_offset = 8;

xkb_state: *xkb.xkb_state = undefined,
xkb_context: *xkb.xkb_context = undefined,
xkb_keymap: *xkb.xkb_keymap = undefined,

pub fn initContext(self: *Keyboard) void {
    self.xkb_context = xkb.xkb_context_new(xkb.XKB_CONTEXT_NO_FLAGS) orelse unreachable;
}

pub fn setKeymap(self: *Keyboard, keymap: [*:0]const u8) void {
    xkb.xkb_keymap_unref(self.xkb_keymap);
    xkb.xkb_state_unref(self.xkb_state);

    self.xkb_keymap = xkb.xkb_keymap_new_from_string(self.xkb_context, keymap, xkb.XKB_KEYMAP_FORMAT_TEXT_V1, xkb.XKB_KEYMAP_COMPILE_NO_FLAGS) orelse unreachable;
    self.xkb_state = xkb.xkb_state_new(self.xkb_keymap) orelse unreachable;
}

pub fn deinit(self: Keyboard) void {
    xkb.xkb_keymap_unref(self.xkb_keymap);
    xkb.xkb_state_unref(self.xkb_state);
    xkb.xkb_context_unref(self.xkb_context);
}

pub fn getOneSym(self: Keyboard, keycode: xkb.xkb_keycode_t) u32 {
    return xkb.xkb_state_key_get_one_sym(self.xkb_state, keycode + keycode_offset);
}

pub fn getName(_: Keyboard, keysym: xkb.xkb_keycode_t, buf: []u8) void {
    _ = xkb.xkb_keysym_get_name(keysym, @ptrCast(buf), @sizeOf(@TypeOf(buf)));
}

pub fn updateKey(self: Keyboard, keycode: xkb.xkb_keycode_t, pressed: bool) void {
    _ = xkb.xkb_state_update_key(self.xkb_state, keycode + keycode_offset, if (pressed) xkb.XKB_KEY_DOWN else xkb.XKB_KEY_UP);
}

pub fn updateMods(self: Keyboard, mods_depressed: xkb.xkb_mod_mask_t, mods_latched: xkb.xkb_mod_mask_t, mods_locked: xkb.xkb_mod_mask_t) void {
    _ = xkb.xkb_state_update_mask(self.xkb_state, mods_depressed, mods_latched, mods_locked, 0, 0, 0);
}

pub fn keyRepeats(self: Keyboard, keycode: xkb.xkb_keycode_t) bool {
    return xkb.xkb_keymap_key_repeats(self.xkb_keymap, keycode + keycode_offset) == 1;
}
