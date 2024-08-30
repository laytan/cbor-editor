//+build !js
package pong

import "core:time"
import "core:math"
import "core:strings"
import "core:os"

import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

OS :: struct {
	window: glfw.WindowHandle,
}

os_init :: proc() {
	if !glfw.Init() {
		panic("[glfw] init failure")
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	state.os.window = glfw.CreateWindow(800, 450, "CBOR", nil, nil)
	assert(state.os.window != nil)

	glfw.SetKeyCallback(state.os.window, key_callback)
	glfw.SetMouseButtonCallback(state.os.window, mouse_button_callback)
	glfw.SetCursorPosCallback(state.os.window, cursor_pos_callback)
	glfw.SetScrollCallback(state.os.window, scroll_callback)
	glfw.SetCharCallback(state.os.window, char_callback)
	glfw.SetFramebufferSizeCallback(state.os.window, size_callback)
	glfw.SetDropCallback(state.os.window, drop_callback)
}

os_run :: proc() {
	for !glfw.WindowShouldClose(state.os.window) {
		glfw.PollEvents()
		do_frame()
	}

	glfw.DestroyWindow(state.os.window)
	glfw.Terminate()
}

@(private="file")
do_frame :: proc() {
	@static frame_time: time.Tick
	if frame_time == {} {
		frame_time = time.tick_now()
	}

	new_frame_time := time.tick_now()
	dt := time.tick_diff(frame_time, new_frame_time)
	frame_time = new_frame_time

	frame(f32(time.duration_seconds(dt)))
	glfw.WaitEvents()
}

os_get_render_bounds :: proc() -> (width, height: u32) {
	iw, ih := glfw.GetFramebufferSize(state.os.window)
	return u32(iw), u32(ih)
}

os_get_screen_size :: proc() -> (width, height: u32) {
	iw, ih := glfw.GetWindowSize(state.os.window)
	return u32(iw), u32(ih)
}

os_get_dpi :: proc() -> f32 {
	sw, sh := glfw.GetWindowContentScale(state.os.window)
	if sw != sh {
		panic("weird screen size")
	}
	return sw
}

os_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return glfwglue.GetSurface(instance, state.os.window)
}

os_get_clipboard :: proc(_: rawptr) -> (string, bool) {
	return glfw.GetClipboardString(state.os.window), true
}

os_set_clipboard :: proc(_: rawptr, text: string) -> bool {
	ctext := strings.clone_to_cstring(text, context.temp_allocator)
	glfw.SetClipboardString(state.os.window, ctext)
	return true
}

os_save :: proc(data: []byte) {
	err := os.write_entire_file_or_err(string(state.file_path[:]), data)
	assert(err == nil)
}

@(private="file")
KEY_MAP := [?]Key{
	glfw.MOUSE_BUTTON_LEFT    = .Mouse_Left,
	glfw.MOUSE_BUTTON_MIDDLE  = .Mouse_Middle,
	glfw.MOUSE_BUTTON_RIGHT   = .Mouse_Right,

	glfw.KEY_LEFT_SHIFT  = .Shift,
	glfw.KEY_RIGHT_SHIFT = .Shift,

	glfw.KEY_LEFT_CONTROL  = .Ctrl,
	glfw.KEY_RIGHT_CONTROL = .Ctrl,

	glfw.KEY_LEFT_ALT  = .Alt,
	glfw.KEY_RIGHT_ALT = .Alt,

	glfw.KEY_BACKSPACE = .Backspace,
	glfw.KEY_DELETE    = .Delete,
	glfw.KEY_ENTER     = .Enter,
	glfw.KEY_LEFT      = .Left,
	glfw.KEY_RIGHT     = .Right,
	glfw.KEY_HOME      = .Home,
	glfw.KEY_END       = .End,
	glfw.KEY_TAB       = .Tab,

	glfw.KEY_A         = .A,
	glfw.KEY_X         = .X,
	glfw.KEY_C         = .C,
	glfw.KEY_V         = .V,
	glfw.KEY_Z         = .Z,

	glfw.KEY_UP        = .Up,
	glfw.KEY_DOWN      = .Down,
	glfw.KEY_W         = .W,
	glfw.KEY_S         = .S,
}

@(private="file")
key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = state.ctx

	if key >= len(KEY_MAP)-1 {
		return
	}

	ikey := KEY_MAP[key]

	iaction: Action
	switch action {
	case glfw.PRESS, glfw.REPEAT: iaction = .Press
	case glfw.RELEASE:            iaction = .Release
	case:                         unreachable()
	}

	i_press_release(ikey, iaction)
}

@(private="file")
mouse_button_callback :: proc "c" (window: glfw.WindowHandle, key, action, mods: i32) {
	key_callback(window, key, 0, action, mods)
}

@(private="file")
cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, x, y: f64) {
	context = state.ctx
	i_move({i32(math.round(x)), i32(math.round(y))})
}

@(private="file")
scroll_callback :: proc "c" (window: glfw.WindowHandle, x, y: f64) {
	context = state.ctx
	i_scroll({-x, -y})
}

@(private="file")
char_callback :: proc "c" (window: glfw.WindowHandle, ch: rune) {
	context = state.ctx
	i_char(ch)
}

@(private="file")
size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	context = state.ctx
	resize()
	do_frame()
}

@(private="file")
drop_callback :: proc "c" (window: glfw.WindowHandle, count: i32, paths: [^]cstring) {
	context = state.ctx
	if count > 0 {
		data, ok := os.read_entire_file(string(paths[0]), context.temp_allocator)
		assert(ok, "reading file failed")
		on_file(string(paths[0]), data)
	}
}
