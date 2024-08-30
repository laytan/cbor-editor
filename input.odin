package pong

import    "core:text/edit"
import    "core:strings"
import    "core:math/linalg"

import fs "vendor:fontstash"

import    "r"

import clay "clay/bindings/odin/clay-odin"

Input :: struct {
    keys:     bit_set[Key],
	new_keys: bit_set[Key],
	scroll:   [2]f64,
	cursor:   [2]i32,
}

Key :: enum {
	None,
	Mouse_Left,
	Mouse_Middle,
	Mouse_Right,
	Shift,
	Ctrl,
	Alt,
	Backspace,
	Delete,
	Enter,
	Left,
	Right,
	Home,
	End,
	Tab,
	A,
	X,
	C,
	V,
	Z,
    Up,
    Down,
    W,
    S,
}

Action :: enum {
	Press,
	Release,
}

// NOTE: can be improved, much hardcode, hacky way of doing tabs.
cursor_to_buffer_idx :: proc() -> int {
	cursor := linalg.to_f32(state.inp.cursor)

	line_nr := cursor.y / 16
	line_nr += f32(state.inp.scroll.y) / 16 / state.renderer.dpi

	text := strings.to_string(state.builder)
	idx: int
	l: int
	curr_line: string
	for line in strings.split_lines_iterator(&text) {
		if l == int(line_nr) {
			curr_line = line
			break
		}
		l += 1
		idx += len(line)+1
	}

	txt := curr_line

	r.fs_apply(&state.fs_renderer, size=16)
	tab_width := r.fs_width(&state.fs_renderer, "    ")

	at_x: f32
	at_i: int
	tabs: for tabbed in strings.split_after_iterator(&txt, "\t") {
		tabbed := tabbed
		if len(tabbed) > 0 && tabbed[0] == '\t' {
			tabbed = tabbed[1:]
			at_x += tab_width
			if at_x >= f32(state.inp.cursor.x) * state.renderer.dpi {
				break
			}
			at_i += 1
		}

		for iter := fs.TextIterInit(&state.fs_renderer.fs, at_x, 0, tabbed); true; {
			quad: fs.Quad
			fs.TextIterNext(&state.fs_renderer.fs, &iter, &quad) or_break
			at_x = quad.x1
			if at_x >= f32(state.inp.cursor.x) * state.renderer.dpi {
				break tabs
			}
			at_i += 1
		}
	}
	idx += at_i

	return idx
}

i_press_release :: proc(key: Key, action: Action) {
	#partial switch key {
	case .None: return
	case .Mouse_Left, .Mouse_Middle, .Mouse_Right:
		switch action {
		case .Release:
			state.inp.keys     -= {key}
			state.inp.new_keys -= {key}

		case .Press:
			state.inp.keys     += {key}
			state.inp.new_keys += {key}

			idx := cursor_to_buffer_idx()
			state.editor.selection = {idx, idx}
		case:
			unreachable()
		}
	case:
		switch action {
		case .Release:
			state.inp.keys     -= {key}
			state.inp.new_keys -= {key}

		case .Press:
			state.inp.keys     += {key}
			state.inp.new_keys += {key}

			#partial switch key {
			case .Z:         
				if .Ctrl in state.inp.keys {
					if .Shift in state.inp.keys {
						edit.perform_command(&state.editor, .Redo)
					} else {
						edit.perform_command(&state.editor, .Undo)
					}
				}

			case .A:
				if .Ctrl in state.inp.keys {
					edit.perform_command(&state.editor, .Select_All)
				}

			case .C:
				if .Ctrl in state.inp.keys {
					edit.perform_command(&state.editor, .Copy)
				}

			case .X:
				if .Ctrl in state.inp.keys {
					edit.perform_command(&state.editor, .Cut)
				}

			case .V:
				if .Ctrl in state.inp.keys {
					edit.perform_command(&state.editor, .Paste)
				}

			// TODO:
			// Delete,
			// Delete_Word_Left,
			// Delete_Word_Right,

			// Start,
			// End,

			// Select_Start,
			// Select_End,

			case .Left:
				if .Ctrl in state.inp.keys {
					curr := state.editor.selection[0]
					pos := strings.last_index_byte(string(state.builder.buf[:curr]), '\n')
					if pos == -1 {
						pos = 0
					}
					state.editor.line_start = pos + 1
				}

				if .Shift in state.inp.keys {
					if .Alt in state.inp.keys {
						edit.perform_command(&state.editor, .Select_Word_Left)
					} else if .Ctrl in state.inp.keys {
						edit.perform_command(&state.editor, .Select_Line_Start)
					} else {
						edit.perform_command(&state.editor, .Select_Left)
					}
				} else if .Alt in state.inp.keys {
					edit.perform_command(&state.editor, .Word_Left)
				} else if .Ctrl in state.inp.keys {
					edit.perform_command(&state.editor, .Line_Start)
				} else {
					edit.perform_command(&state.editor, .Left)
				}

			case .Right:
				if .Ctrl in state.inp.keys {
					curr := state.editor.selection[0]
					pos  := strings.index_byte(string(state.builder.buf[curr:]), '\n')
					if pos == -1 {
						pos = len(state.builder.buf)-1
					}
					state.editor.line_end = curr + pos
				}

				if .Shift in state.inp.keys {
					if .Alt in state.inp.keys {
						edit.perform_command(&state.editor, .Select_Word_Right)
					} else if .Ctrl in state.inp.keys {
						edit.perform_command(&state.editor, .Select_Line_End)
					} else {
						edit.perform_command(&state.editor, .Select_Right)
					}
				} else if .Alt in state.inp.keys {
					edit.perform_command(&state.editor, .Word_Right)
				} else if .Ctrl in state.inp.keys {
					edit.perform_command(&state.editor, .Line_End)
				} else {
					edit.perform_command(&state.editor, .Right)
				}

			case .Up:
				curr     := state.editor.selection[0]
				line_idx := strings.last_index_byte(string(state.builder.buf[:curr]), '\n') + 1
				column   := curr-line_idx

				prev_line      := strings.last_index_byte(string(state.builder.buf[:max(0, line_idx-1) ]), '\n') + 1
				prev_prev_line := strings.last_index_byte(string(state.builder.buf[:max(0, prev_line-1)]), '\n') + 1

				state.editor.up_index = clamp(prev_line+column, prev_prev_line, len(state.builder.buf)-1)

				if .Shift in state.inp.keys {
					edit.perform_command(&state.editor, .Select_Up)
				} else {
					edit.perform_command(&state.editor, .Up)
				}

			case .Down:
					curr := state.editor.selection[0]
				line_idx := strings.last_index_byte(string(state.builder.buf[:curr]), '\n') + 1
				column   := curr-line_idx

				next_line      := curr      + strings.index_byte(string(state.builder.buf[curr:]), '\n') + 1
				next_next_line := next_line + max(0, strings.index_byte(string(state.builder.buf[next_line:]), '\n'))

				state.editor.down_index = clamp(next_line+column, 0, next_next_line)

				if .Shift in state.inp.keys {
					edit.perform_command(&state.editor, .Select_Down)
				} else {
					edit.perform_command(&state.editor, .Down)
				}

			case .Backspace: edit.perform_command(&state.editor, .Backspace)
			case .Enter:     edit.perform_command(&state.editor, .New_Line)

			case .Tab: edit.input_rune(&state.editor, '\t')
			}

		case:
			unreachable()
		}
	}
}

i_move :: proc(pos: [2]i32) {
	state.inp.cursor = pos

	if .Mouse_Left in state.inp.keys {
		idx := cursor_to_buffer_idx()
		state.editor.selection[1] = idx
	}

	clay.SetPointerPosition(linalg.array_cast(state.inp.cursor, f32) * state.renderer.dpi)
}

i_scroll :: proc(delta: [2]f64) {
	delta := delta
	delta.y *= 4 // speed it up

	state.inp.scroll += delta
}

i_char :: proc(ch: rune) {
	edit.input_rune(&state.editor, ch)
}
