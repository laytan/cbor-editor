(function() {

	class ClipboardInterface {

		/**
	 	 * @param {WasmMemoryInterface} mem
	 	 */
		constructor(mem) {
			this.mem = mem;
		}

		getInterface() {
			return {
				get_clipboard_text_raw: () => {
					if (!navigator.clipboard) {
						return;
					}

					navigator.clipboard.readText()
						.then(text => {
							const textLength = new TextEncoder().encode(text).length;

							const textAddr = this.mem.exports.get_clipboard_text_raw_callback(textLength);
							this.mem.storeString(textAddr, text);
						})
						.catch(err => {
							console.error("clipboard read denied", err);
						});
				},

				set_clipboard_text_raw: (textPtr, textLength) => {
					if (!navigator.clipboard) {
						return;
					}

					const text = this.mem.loadString(textPtr, textLength);
					navigator.clipboard.writeText(text)
						.catch(err => {
							console.error("clipboard write denied", err);
						});
				},
			};
		}
	}

	window.odin = window.odin || {};
	window.odin.ClipboardInterface = ClipboardInterface;

})();
