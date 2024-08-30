package pong

import    "base:runtime"

import    "core:log"
import    "core:strings"
import    "core:fmt"
import    "core:encoding/cbor"
import    "core:text/edit"
import    "core:math/linalg"
import    "core:strconv"
import    "core:math"

import    "vendor:wgpu"

import    "r"

import clay "clay/bindings/odin/clay-odin"

state: struct {
	ctx:            runtime.Context,

	os:             OS,

    inp:            Input,

	renderer:       r.Renderer,

	fs_renderer:    r.Font_Renderer,

	sprite_render:  r.Sprite,
	sprites:        [dynamic]r.Sprite_Data,

	editor:         edit.State,
	builder:        strings.Builder,
	file_path:      [dynamic]byte,
}

main :: proc() {
	context.logger = log.create_multi_logger(
		log.create_console_logger(),
		// {
		// 	procedure = mu_log_proc,
		// 	options = { .Level, .Time, .Short_File_Path, .Line },
		// },
	)

	state.ctx = context

	edit.init(&state.editor, context.allocator, context.allocator)
	state.editor.set_clipboard = os_set_clipboard
	state.editor.get_clipboard = os_get_clipboard
	strings.builder_init(&state.builder)
	strings.write_string(&state.builder, CBOR)
	edit.setup_once(&state.editor, &state.builder)
	edit.move_to(&state.editor, .End)

	append(&state.file_path, "scratch.cbor")

	r.clay_init(&state.fs_renderer, &state.sprites)
	min_memory_size := clay.MinMemorySize()
	arena := clay.CreateArenaWithCapacityAndMemory(min_memory_size, make([^]byte, min_memory_size))
	clay.Initialize(arena)
	clay.SetMeasureTextFunction(r.clay_measure_text)

	os_init()

	width, height := os_get_render_bounds()
	screen_width, screen_height := os_get_screen_size()

	instance := wgpu.CreateInstance()
	surface  := os_get_surface(instance)
	r.init(&state.renderer, instance, surface, .Warning, width, height, screen_width, screen_height, os_get_dpi(), on_initialized)

	on_initialized :: proc() {
		r.fs_init(&state.fs_renderer, &state.renderer)
		r.sprite_init(&state.sprite_render, &state.renderer)

		os_run()
	}
}

resize :: proc() {
	width, height := os_get_render_bounds()
	screen_width, screen_height := os_get_screen_size()
	dpi := os_get_dpi()
	r.resize(&state.renderer, width, height, screen_width, screen_height, dpi)
	r.fs_resize(&state.fs_renderer)
	r.sprite_resize(&state.sprite_render)
}

on_file :: proc(path: string, data: []byte) {
	clear(&state.file_path)
	append(&state.file_path, path)

	value, err := cbor.decode(string(data), allocator=context.temp_allocator)
	fmt.assertf(err == nil, "decode error: %v", err)	

	diag := cbor.to_diagnostic_format(value, allocator=context.temp_allocator)

	state.editor.selection = 0
	strings.builder_reset(&state.builder)
	edit.input_text(&state.editor, diag)
	state.editor.selection = 0
}

CBOR :: `{
	"base64": 34("MTYgaXMgYSBuaWNlIG51bWJlcg=="),
	"biggest": 2(h'0f951a9fd3c158afdff08ab8e0'),
	"biggie": 18446744073709551615,
	"child": {
		"dyn": [
			"one",
			"two",
			"three",
			"four"
		],
		"mappy": {
			"one": 1,
			"two": 2,
			"four": 4,
			"three": 3
		},
		"my_integers": [
			1,
			2,
			3,
			4,
			5,
			6,
			7,
			8,
			9,
			10
		]
	},
	"comp": [
		32.0000,
		33.0000
	],
	"cstr": "Hellnope",
	"ennie": 0,
	"ennieb": 512,
	"iamint": -256,
	"important": "!",
	"my_bytes": h'',
	"neg": -69,
	"no": null,
	"nos": undefined,
	"now": 1(1701117968),
	"nowie": {
		"_nsec": 1701117968000000000
	},
	"onetwenty": 12345,
	"pos": 1212,
	"quat": [
		17.0000,
		18.0000,
		19.0000,
		16.0000
	],
	"renamed :)": 123123.12500000,
	"small_onetwenty": -18446744073709551615,
	"smallest": 3(h'0f951a9fd3c158afdff08ab8e0'),
	"smallie": -18446744073709551616,
	"str": "Hellope",
	"value": {
		16: "16 is a nice number",
		32: 69
	},
	"yes": true
}`

// TODO:
// - bind the rest of the command of core:text/edit
// - zooming
// - if action while caret not on screen, first focus view/scroll on caret
// - horizontal scrolling
// - only draw text that is on screen
// - fix bug removing all content
// - error handling in the parser and display those errors
// - always doing preventDefault is probably bad
// - Cmd+foo keybinds on MacOS

frame :: proc(dt: f32) {
	context = state.ctx

	defer free_all(context.temp_allocator)
	defer state.inp.new_keys = {}
	clear(&state.sprites)
	r.clear(&state.renderer, {30./255., 30./255., 46./255., 1})

	_sc_width, _sc_height := os_get_render_bounds()
	sc_width, sc_height := f32(_sc_width), f32(_sc_height)

	state.editor.current_time._nsec += i64(dt*1e9)

	text := strings.to_string(state.builder)

	fs := &state.fs_renderer
	r.fs_apply(fs, size=16)
	lh := r.fs_lh(fs)

	RED :: [4]f32{0, 0, 255, 255}

	clay.BeginLayout(i32(_sc_width), i32(_sc_height))
	if clay.Rectangle(clay.ID("screen"), clay.Layout({ sizing = { width = clay.SizingFixed(sc_width), height = clay.SizingFixed(sc_height) } }), clay.RectangleConfig({})) {
		if clay.Rectangle(clay.ID("main"), clay.Layout({ padding = {16, 16}, layoutDirection = .TOP_TO_BOTTOM, sizing = { width = clay.SizingGrow({}), height = clay.SizingGrow({}) } }), clay.RectangleConfig({})) {
			if clay.Rectangle(clay.ID("top"), clay.Layout({ sizing = { width = clay.SizingGrow({}) } }), clay.RectangleConfig({})) {
				clay.Text(clay.ID("title"), clay.MakeString(string(state.file_path[:])), clay.TextConfig(UI_TEXT))
				if clay.Rectangle(clay.ID("right"), clay.Layout({ sizing = { width = clay.SizingGrow({}) }, childAlignment = { x = .RIGHT }, childGap = 16 }), clay.RectangleConfig({})) {

					when #defined(os_open) {
						if Button("Open") do os_open()
					}

					when #defined(os_save) {
						if Button("Save") {
							t: Tokenizer
							t.source = string(state.builder.buf[:])
							t.full   = t.source
							t.line   = 1
							val, ok := parse(&t, context.temp_allocator)
							assert(ok)
							data, err := cbor.encode(val, cbor.ENCODE_FULLY_DETERMINISTIC, context.temp_allocator)
							assert(err == nil)
							os_save(data)
						}
					}

					when #defined(os_save_as) {
						if Button("Save As") {
							t: Tokenizer
							t.source = string(state.builder.buf[:])
							t.full   = t.source
							t.line   = 1
							val, ok := parse(&t, context.temp_allocator)
							assert(ok)
							data, err := cbor.encode(val, cbor.ENCODE_FULLY_DETERMINISTIC, context.temp_allocator)
							assert(err == nil)
							os_save_as(data)
						}
					}
				}
			} // top

			pos := -f32(state.inp.scroll.y)
			r.fs_draw_text(fs, text, pos={0, pos}, size=16, color={166, 218, 149, 255}, align_v=.Top)

			caret, selection_end := edit.sorted_selection(&state.editor)

			line := strings.count(text[:caret], "\n")
			y := f32(line) * lh - f32(state.inp.scroll.y)

			current_line_start := max(0, strings.last_index_byte(text[:caret], '\n'))
			current_line := strings.trim(text[current_line_start:caret], "\n")
			x := r.fs_width(fs, current_line)

			caret_pos := [2]f32{x, y}
			append(&state.sprites, r.Sprite_Data{
				location = {4*17, 2*17},
				size     = {16, 16},
				anchor   = {0, 0},
				position = caret_pos,
				scale    = {16/16, lh/16},
				rotation = 0,
				color    = 0xAAa6da95,
			})

			if selection_end > caret {
				selected := text[caret:selection_end]
				start := caret_pos
				for line in strings.split_lines_iterator(&selected) {
					width := r.fs_width(&state.fs_renderer, line)

					append(&state.sprites, r.Sprite_Data{
						location = {4*17, 2*17},
						size     = {16, 16},
						anchor   = {0, 0},
						position = start,
						scale    = {width/16, lh/16},
						rotation = 0,
						color    = 0x66a6da95,
					})

					start.x  = 0
					start.y += lh
				}
			}

			if clay.Rectangle(clay.ID("bottom"), clay.Layout({ sizing = { width = clay.SizingGrow({}), height = clay.SizingGrow({}) }, childAlignment = { x = .RIGHT, y = .BOTTOM } }), clay.RectangleConfig({})) {
				// FPS over last 30 frames.
				@static frame_times: [30]f32
				@static frame_times_idx: int

				frame_times[frame_times_idx % len(frame_times)] = dt
				frame_times_idx += 1

				frame_time: f32
				for time in frame_times {
					frame_time += time
				}

				buf: [24]byte
				fps := strconv.itoa(buf[:], int(math.round(len(frame_times)/frame_time)))
				clay.Text(clay.ID("fps"), clay.MakeString(fps), clay.TextConfig(UI_TEXT))
			} // bottom
		} // main

		SCROLLBAR_WIDTH        :: 16
		SCROLLBAR_THUMB_HEIGHT :: 64
		SCROLLBAR_COLOR        :: [4]f32{244, 138, 173, 100}
		SCROLLBAR_THUMB_COLOR  :: [4]f32{244, 138, 173, 255}
		if clay.Rectangle(clay.ID("scrollbar"), clay.Layout({ sizing = { width = clay.SizingFixed(SCROLLBAR_WIDTH), height = clay.SizingGrow({}) }, layoutDirection = .TOP_TO_BOTTOM }), clay.RectangleConfig({ color = SCROLLBAR_COLOR })) {

			lines      := f32(strings.count(text, "\n"))
			max_scroll := f64((lines+1) * lh - sc_height)

			// NOTE: clamping scroll, while we are technically in the drawing phase of the loop.
			state.inp.scroll.y = clamp(state.inp.scroll.y, 0, max_scroll)

			lines_scrolled := f32(state.inp.scroll.y) / lh
			percentage     := clamp(lines_scrolled / (lines - sc_height / lh), 0, 1)
			thumb_y        := percentage * sc_height - SCROLLBAR_THUMB_HEIGHT/2

			fmt.println(thumb_y)

			if clay.Rectangle(clay.ID("thumb-offset"), clay.Layout({ sizing = { height = clay.SizingFixed(thumb_y) } }), clay.RectangleConfig({})) {}
			if clay.Rectangle(clay.ID("thumb"), clay.Layout({ sizing = { height = clay.SizingFixed(SCROLLBAR_THUMB_HEIGHT), width = clay.SizingGrow({}) } }), clay.RectangleConfig({ color = SCROLLBAR_THUMB_COLOR })) {}
		} // scrollbar
	} // screen
	render_commands := clay.EndLayout(i32(_sc_width), i32(_sc_height))
	r.clay_render(&render_commands)

	r.sprite_render(&state.sprite_render, state.sprites[:])
	r.fs_render(&state.fs_renderer)
	r.present(&state.renderer)
}

UI_TEXT :: clay.TextElementConfig{
	fontId    = u16(r.Font.UI),
	fontSize  = FONT_SIZE,
	textColor = 255,
}

FONT_SIZE :: 18

Button :: proc($ID: string) -> (clicked: bool) {
	hovered := clay.PointerOver(clay.ID(ID))

	if hovered && .Mouse_Left in state.inp.new_keys {
		clicked = true
	}

	color: [4]f32
	switch {
	case clicked: color = {239,  95, 143, 255}
	case hovered: color = {242, 121, 161, 255}
	case:         color = {244, 138, 173, 255}
	}

	if clay.Rectangle(clay.ID(ID), clay.Layout({ padding = {12, 6} }), clay.RectangleConfig({ color = color })) {
		clay.Text(clay.ID(ID + "-text"), clay.MakeString(ID), clay.TextConfig(UI_TEXT))
	}
	return
}
