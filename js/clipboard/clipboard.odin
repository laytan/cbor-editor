package js_clipboard

import "base:runtime"

import "vendor:wasm/js"

foreign import lib "clipboard"

@(private, default_calling_convention="contextless")
foreign lib {
	get_clipboard_text_raw :: proc() ---
	set_clipboard_text_raw :: proc(text: string) ---
}

Clipboard :: struct {
	ctx:      runtime.Context,
	text:     [dynamic]byte,
	attached: bool,
	ever_set: bool,
}
@(private="file")
g_clipboard: Clipboard

attach :: proc() {
	assert(!g_clipboard.attached, "already attached")
	g_clipboard.attached = true
	g_clipboard.ctx = context

	// Using a focus event listener to hopefully keep the clipboard buffer
	// here in sync with the browser's. We need get_clipboard_text to return with
	// the text immediately, so we have to keep the buffer up-to-date in the background.

	ok := js.add_window_event_listener(.Focus, nil, proc(e: js.Event) {
		get_clipboard_text_raw()
	})
	assert(ok, "couldn't add focus event listener on the window")
}

get_text :: proc() -> (string, bool) {
	assert(g_clipboard.attached, "not attached")

	// Possible the user declined the first time and now decides to paste, so ask again.
	// NOTE: that the return from this proc call will not have the clipboard text due to
	// the asynchronous nature of the clipboard API.
	if !g_clipboard.ever_set {
		get_clipboard_text_raw()
		return "", false
	} else {
		return string(g_clipboard.text[:]), true
	}
}

set_text :: proc(text: string) {
	clear(&g_clipboard.text)
	append(&g_clipboard.text, text)

	// Sync back to the system/browser.
	set_clipboard_text_raw(text)
}

@(private="file", export)
get_clipboard_text_raw_callback :: proc "contextless" (size: i32) -> [^]byte {
	context = g_clipboard.ctx
	err := resize(&g_clipboard.text, size)
	assert(err == nil, "allocation failure")
	g_clipboard.ever_set = true
	return raw_data(g_clipboard.text[:])
}
