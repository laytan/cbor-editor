package pong

import "core:fmt"
import "core:unicode"
import "core:unicode/utf8"
import "core:encoding/cbor"
import "core:math"
import "core:strconv"
import "core:strings"
import "core:encoding/hex"

Tokenizer :: struct {
	full:   string,
	source: string,
	ch:     rune,
	len:    int,
	line:   int,
	bol:    int,
	off:    int,
}

Type :: enum {
	Invalid,
	Open_Bracket,
	Close_Bracket,
	String,
	Bytes,
	Colon,
	Open_Tag,
	Close_Tag,
	Integer,
	Float,
	Open_Brace,
	Close_Brace,
	Comma,

	Null,
	Undefined,
	True,
	False,
	Infinity,
	NaN,

	Simple,

	EOF,
}

Token :: struct {
	type:   Type,
	pos:    Position,
	source: string,
}

Position :: struct {
	line: int,
	col:  int,
	off:  int,
}

next :: proc(t: ^Tokenizer) -> Token {
	next_rune :: proc(t: ^Tokenizer) -> (ch: rune, ok: bool) {
		t.source = t.source[t.len:]
		t.off += t.len

		t.ch, t.len = utf8.decode_rune(t.source)

		ch = t.ch
		ok = t.len > 0
		return
	}

	skip_whitespace :: proc(t: ^Tokenizer) {
		ch := t.ch
		for {
			if ch == '\n' {
				t.bol   = t.off
				t.line += 1
			} else if unicode.is_space(ch) {
			} else {
				break
			}

			ch = next_rune(t) or_break
		}
	}

	skip_numeric :: proc(t: ^Tokenizer) {
		for ch in next_rune(t) {
			switch ch {
			case '0'..='9':
			case: return
			}
		}
	}

	scan_escape :: proc(t: ^Tokenizer) -> bool {
		switch t.ch {
		case '"', '\'', '\\', '/', 'b', 'n', 'r', 't', 'f':
			next_rune(t)
			return true
		case 'u':
			// Expect 4 hexadecimal digits
			for i := 0; i < 4; i += 1 {
				r := next_rune(t) or_return
				switch r {
				case '0'..='9', 'a'..='f', 'A'..='F':
					// Okay
				case:
					return false
				}
			}
			return true
		case:
			// Ignore the next rune regardless
			next_rune(t)
		}
		return false
	}

	position :: proc(t: ^Tokenizer) -> Position {
		return {
			line = t.line,
			col  = t.off-t.bol,
			off  = t.off,
		}
	}

	if t.ch == 0 {
		next_rune(t)
	}

	skip_whitespace(t)

	if len(t.source) == 0 {
		return {
			type = .EOF,
			pos  = position(t),
		}
	}

	tok: Token
	tok.source = t.source[:t.len]
	tok.pos    = position(t)

	switch t.ch {
	case '{':
		tok.type = .Open_Bracket
	case '}':
		tok.type = .Close_Bracket
	case '"': 
		for ch in next_rune(t) {
			switch ch {
			case:
			case '\\':
				scan_escape(t)
			case '"':
				next_rune(t)
				tok.type = .String
				tok.source = t.full[tok.pos.off:t.off]
				// if !is_valid_string_literal(str, t.spec) {
				// 	err = .Invalid_String
				// }
				return tok
			}
		}

		tok.type = .Invalid
		tok.source = t.full[tok.pos.off:t.off]
		return tok

	case 'h':
		next := next_rune(t) or_break
		if next == '\'' {
			for ch in next_rune(t) {
				switch ch {
				case '0'..='9', 'a'..='f', 'A'..='F': // base 16
				case:
					tok.source = t.full[tok.pos.off:t.off]
					return tok
				case '\'':
					next_rune(t)
					tok.type = .Bytes
					tok.source = t.full[tok.pos.off:t.off]
					return tok
				}
			}
		}

		tok.type = .Invalid
		tok.source = t.full[tok.pos.off:t.off]
		return tok

	case 'a'..='z', 'A'..='Z':
		loop: for ch in next_rune(t) {
			switch ch {
			case 'A'..='Z', 'a'..='z':
			case: break loop
			}
		}

		tok.source = t.full[tok.pos.off:t.off]
		switch tok.source {
		case "null":      tok.type = .Null
		case "undefined": tok.type = .Undefined
		case "true":      tok.type = .True
		case "false":     tok.type = .False
		case "Infinity":  tok.type = .Infinity
		case "NaN":       tok.type = .NaN
		case "simple":
			// TODO: simple has an allowed integer range.
			
			if t.ch == '(' {
				next_rune(t) or_break
				if t.ch >= '0' && t.ch <= '9' {
					skip_numeric(t)

					if t.ch == ')' {
						next_rune(t) or_break
						tok.source = t.full[tok.pos.off:t.off]
						tok.type = .Simple
					}
				}
			}
		}
		return tok

	case ':':
		tok.type = .Colon
	case ',':
		tok.type = .Comma
	case ')':
		tok.type = .Close_Tag
	case '[':
		tok.type = .Open_Brace
	case ']':
		tok.type = .Close_Brace
	case '-', '+':
		next_rune(t)
		fallthrough
	case '0'..='9':
		tok.type = .Integer
		skip_numeric(t)
		tok.source = t.full[tok.pos.off:t.off]

		if len(tok.source) == 1 {
			switch tok.source[0] {
			case '+':
				tok.type = .Invalid
				return tok
			case '-': // -Infinity
				expected := []rune{'I', 'n', 'f', 'i', 'n', 'i', 't', 'y'}
				for e in expected {
					if t.ch != e {
						tok.type = .Invalid
						return tok
					}

					_, ok := next_rune(t)
					if !ok {
						tok.type = .Invalid
						return tok
					}
				}
			case:
			}
		}

		if t.ch == '.' {
			if ch, ok := next_rune(t); ok {
				if ch >= '0' && ch <= '9' {
					tok.type = .Float
					skip_numeric(t)
					tok.source = t.full[tok.pos.off:t.off]
				}
			}
		} else if t.ch == '(' {
			tok.type = .Open_Tag
			next_rune(t)
			tok.source = t.full[tok.pos.off:t.off]
		}

		return tok
	}

	next_rune(t)
	return tok
}

parse :: proc(t: ^Tokenizer, allocator := context.allocator) -> (v: cbor.Value, ok: bool) {

	parse_map :: proc(t: ^Tokenizer, allocator := context.allocator) -> (v: cbor.Value, ok: bool) {
		m := make([dynamic]cbor.Map_Entry, allocator) or_else panic("bad alloc")

		for {
			key := parse(t, allocator) or_return

			colon := next(t)
			if colon.type != .Colon {
				panic("expected colon")
			}

			value := parse(t, allocator) or_return

			_ = append(&m, cbor.Map_Entry{
				key   = key,
				value = value,
			}) or_else panic("bad alloc")

			comma := next(t)
			if comma.type == .Comma {
				continue
			} else if comma.type == .Close_Bracket {
				break
			}
		}

		mp := new(cbor.Map, allocator) or_else panic("bad alloc")
		mp^ = m[:]

		return mp, true
	}

	parse_array :: proc(t: ^Tokenizer, allocator := context.allocator) -> (v: cbor.Value, ok: bool) {
		arr := make([dynamic]cbor.Value, allocator) or_else panic("bad alloc")

		for {
			value := parse(t, allocator) or_else panic("bad")

			_ = append(&arr, value) or_else panic("bad")

			comma := next(t)
			if comma.type == .Comma {
				continue
			} else if comma.type == .Close_Brace {
				break
			}
		}

		arrp := new([]cbor.Value, allocator) or_else panic("bad alloc")
		arrp^ = arr[:]

		return arrp, true
	}

	tok := next(t)
	switch tok.type {
	case .EOF:      return nil, true
	case .Invalid:  panic("invalid")

	case .Infinity:
		sign := -1 if tok.source[0] == '-' else 1
		return math.inf_f64(sign), true

	case .NaN:
		return math.nan_f64(), true

	case .Null:
		return cbor.Nil{}, true

	case .Undefined:
		return cbor.Undefined{}, true

	case .True:
		return true, true

	case .False:
		return false, true

	case .Integer:
		value := strconv.parse_i128(tok.source) or_else panic("bad integer")

		uvalue, maj, err := cbor._int_to_uint(value)
		if err != nil do panic("bad integer")

		#partial switch maj {
		case .Unsigned: return uvalue, true
		case .Negative: return cbor.Negative_U64(uvalue), true
		case: unreachable()
		}

	case .Float:
		value := strconv.parse_f64(tok.source) or_else panic("bad float")
		return value, true

	case .Bytes:
		assert(strings.has_prefix(tok.source, "h'"))
		assert(strings.has_suffix(tok.source, "'"))

		source := tok.source[2:len(tok.source)-1]
		fmt.println(source)
		value := hex.decode(transmute([]byte)source, allocator) or_else panic("bad hex")

		valuep := new([]byte, allocator) or_else panic("bad alloc")
		valuep^ = value

		return valuep, true

	case .String:
		assert(strings.has_prefix(tok.source, "\""))
		assert(strings.has_suffix(tok.source, "\""))

		value, allocated := strconv.unquote_string(tok.source, allocator) or_else panic("bad string")
		if !allocated {
			value = strings.clone(value, allocator)
		}

		valuep := new(string, allocator)
		valuep^ = value

		return valuep, true

	case .Simple:
		assert(strings.has_prefix(tok.source, "simple("))
		assert(strings.has_suffix(tok.source, ")"))

		source := tok.source[len("simple("):len(tok.source)-1]
		value  := strconv.parse_u64_of_base(source, 10) or_else panic("bad simple")
		if value > u64(max(cbor.Simple)) {
			panic("bad simple")
		}
		return cbor.Simple(value), true

	case .Open_Tag:
		assert(tok.source[len(tok.source)-1] == '(')

		source := tok.source[:len(tok.source)-1]
		tag    := strconv.parse_u64_of_base(source, 10) or_else panic("bad")
		value  := parse(t, allocator) or_else panic("bad")

		close := next(t)
		if close.type != .Close_Tag {
			panic("bad close")
		}

		tagp := new(cbor.Tag, allocator) or_else panic("bad alloc")
		tagp.number = tag
		tagp.value  = value

		return tagp, true

	case .Open_Bracket:
		return parse_map(t, allocator)

	case .Open_Brace:
		return parse_array(t, allocator)

	case .Close_Brace, .Close_Bracket, .Colon, .Comma, .Close_Tag:
		fmt.panicf("bad %v", tok)
	}

	unreachable()
}
