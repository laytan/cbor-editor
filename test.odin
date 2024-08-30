//+build ignore
package pong

import "core:testing"
import "core:log"
import "core:encoding/cbor"

@(test)
test_tokenizer :: proc(t: ^testing.T) {
	t: Tokenizer
	t.source = CBOR
	t.full = t.source
	t.line   = 1

	for {
		token := next(&t)

		log.infof("(%v:%v): %q (%v)", token.pos.line, token.pos.col, token.source, token.type)

		if token.type == .EOF || token.type == .Invalid {
			break
		}
	}
}

@(test)
test_parser :: proc(t: ^testing.T) {
	data: string = #load("test.cbor")
	value, err := cbor.decode(data)
	testing.expect_value(t, err, nil)

	diag, derr := cbor.to_diagnostic_format(value)
	testing.expect_value(t, derr, nil)

	tok: Tokenizer
	tok.source = diag
	tok.full = tok.source
	tok.line   = 1
	new_parsed_value := parse(&tok) or_else panic("bad")

	new_encoded, eerr := cbor.encode(new_parsed_value, cbor.ENCODE_FULLY_DETERMINISTIC)
	testing.expect_value(t, eerr, nil)

	new_value, nerr := cbor.decode(string(new_encoded))
	testing.expect_value(t, nerr, nil)

	new_diag, new_derr := cbor.to_diagnostic_format(new_value)
	testing.expect_value(t, new_derr, nil)

	testing.expect_value(t, new_diag, diag)
}
