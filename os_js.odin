package pong

import "base:builtin"

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
// import "core:path/slashpath"

import "vendor:wgpu"
import "vendor:wasm/js"

import "r"
import "js/clipboard"

foreign import lib "cbor"

OS :: struct {
	initialized: bool,
}

os_init :: proc() {
	assert(js.add_window_event_listener(.Key_Down, nil, key_down_callback))
	assert(js.add_window_event_listener(.Key_Up, nil, key_up_callback))
	assert(js.add_window_event_listener(.Mouse_Down, nil, mouse_down_callback))
	assert(js.add_window_event_listener(.Mouse_Up, nil, mouse_up_callback))
	assert(js.add_event_listener("wgpu-canvas", .Mouse_Move, nil, mouse_move_callback))
	assert(js.add_window_event_listener(.Wheel, nil, scroll_callback))
	assert(js.add_window_event_listener(.Resize,   nil, size_callback))

	clipboard.attach()
}

// NOTE: frame loop is done by the runtime.js repeatedly calling `step`.
os_run :: proc() {
	state.os.initialized = true
}

@(private="file", export)
step :: proc(dt: f32) -> bool {
	context = state.ctx

	if !state.os.initialized {
		return true
	}

	frame(dt)

	return true
}

os_get_render_bounds :: proc() -> (width, height: u32) {
	rect := js.get_bounding_client_rect("body")
	return u32(f32(rect.width) * os_get_dpi()), u32(f32(rect.height) * os_get_dpi())
}

os_get_screen_size :: proc() -> (width, height: u32) {
	rect := js.get_bounding_client_rect("body")
	return u32(rect.width), u32(rect.height)
}

os_get_dpi :: proc() -> f32 {
	dpi := js.device_pixel_ratio()
	return f32(dpi)
}

os_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return wgpu.InstanceCreateSurface(
		instance,
		&wgpu.SurfaceDescriptor{
			nextInChain = &wgpu.SurfaceDescriptorFromCanvasHTMLSelector{
				sType = .SurfaceDescriptorFromCanvasHTMLSelector,
				selector = "#wgpu-canvas",
			},
		},
	)
}

os_get_clipboard :: proc(_: rawptr) -> (string, bool) {
	return clipboard.get_text()
}

os_set_clipboard :: proc(_: rawptr, text: string) -> bool {
	clipboard.set_text(text)
	return true
}

@(private="file")
KEY_MAP := map[string]Key{
	"ShiftLeft"    = .Shift,
	"ShiftRight"   = .Shift,
	"ControlLeft"  = .Ctrl,
	"ControlRight" = .Ctrl,
	"AltLeft"      = .Alt,
	"AltRight"     = .Alt,
	"Backspace"    = .Backspace,
	"Delete"       = .Delete,
	"Enter"        = .Enter,
	"ArrowLeft"    = .Left,
	"ArrowRight"   = .Right,
	"Home"         = .Home,
	"End"          = .End,
	"KeyA"         = .A,
	"KeyX"         = .X,
	"KeyC"         = .C,
	"KeyV"         = .V,
	"KeyZ"         = .Z,
	"ArrowUp"      = .Up,
	"ArrowDown"    = .Down,
	"KeyW"         = .W,
	"KeyS"         = .S,
	"Tab"          = .Tab,
}

os_open :: proc() {
	@(default_calling_convention="contextless")
	foreign lib {
		os_js_open :: proc() ---
	}
	os_js_open()
}

os_save :: proc(data: []byte) {
	@(default_calling_convention="contextless")
	foreign lib {
		os_js_save :: proc(name: string, data: []byte) ---
	}
	// name := slashpath.base(string(state.file_path[:]), new=false)
	os_js_save(string(state.file_path[:]), data)
}

@(private="file", export)
os_js_file_alloc :: proc "contextless" (size: i32) -> ([^]byte) {
	context = state.ctx
	return make([^]byte, size, context.temp_allocator)
}

@(private="file", export)
os_js_file_callback :: proc "contextless" (name: string, data: []byte) {
	context = state.ctx
	on_file(name, data)
}

@(private="file")
key_down_callback :: proc(e: js.Event) {
	js.event_prevent_default()

	context = state.ctx

	if k, ok := KEY_MAP[e.data.key.code]; ok {
		i_press_release(k, .Press)
	}

	if .Ctrl in state.inp.keys {
		return
	}

	ch, size := utf8.decode_rune(e.data.key.key)
	if len(e.data.key.key) == size && unicode.is_print(ch) {
		i_char(ch)
	}
}

@(private="file")
key_up_callback :: proc(e: js.Event) {
	context = state.ctx
	i_press_release(KEY_MAP[e.data.key.code], .Release)
	js.event_prevent_default()
}

@(private="file")
mouse_down_callback :: proc(e: js.Event) {
	context = state.ctx
	switch e.data.mouse.button {
	case 0: i_press_release(.Mouse_Left,   .Press)
	case 1: i_press_release(.Mouse_Middle, .Press)
	case 2: i_press_release(.Mouse_Right,  .Press)
	}
	js.event_prevent_default()
}

@(private="file")
mouse_up_callback :: proc(e: js.Event) {
	context = state.ctx
	switch e.data.mouse.button {
	case 0: i_press_release(.Mouse_Left,   .Release)
	case 1: i_press_release(.Mouse_Middle, .Release)
	case 2: i_press_release(.Mouse_Right,  .Release)
	}
	js.event_prevent_default()
}

@(private="file")
mouse_move_callback :: proc(e: js.Event) {
	context = state.ctx
	i_move({i32(e.data.mouse.offset.x), i32(e.data.mouse.offset.y)})
}

@(private="file")
scroll_callback :: proc(e: js.Event) {
	context = state.ctx
	i_scroll({e.data.wheel.delta.x, e.data.wheel.delta.y})
}

@(private="file")
size_callback :: proc(e: js.Event) {
	context = state.ctx
	resize()
}
