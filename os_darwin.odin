package pong

import    "core:os"
import    "core:path/filepath"
import NS "core:sys/darwin/Foundation"

import    "vendor:glfw"

os_open :: proc() {
	NS.scoped_autoreleasepool()

	dialog := NS.OpenPanel_openPanel()
	dialog->setAllowsMultipleSelection(false)
	dialog->setCanChooseDirectories(false)

	// file_types_slice := []^NS.Object{ NS.AT("cbor"), }
	// file_types := NS.Array_alloc()\
	// 	->initWithObjects(raw_data(file_types_slice), auto_cast len(file_types_slice))
	//
	// dialog->setAllowedFileTypes(file_types)

	switch dialog->runModal() {
	case .Cancel: return
	case:         unreachable()
	case .OK:
	}

	urls := dialog->URLs()
	assert(urls->count() == 1)
	url := urls->objectAs(0, ^NS.URL)

	main_window := glfw.GetCocoaWindow(state.os.window)
	main_window->makeKeyAndOrderFront(nil)

	path := url->fileSystemRepresentation()

	data, ok := os.read_entire_file(string(path), context.temp_allocator)
	assert(ok)

	on_file(string(path), data)
}

os_save_as :: proc(data: []byte) {
	NS.scoped_autoreleasepool()

	dialog := NS.OpenPanel_openPanel()
	dialog->setAllowsMultipleSelection(false)
	dialog->setCanChooseDirectories(true)

	switch dialog->runModal() {
	case .Cancel: return
	case:         unreachable()
	case .OK:
	}

	urls := dialog->URLs()
	assert(urls->count() == 1)
	url := urls->objectAs(0, ^NS.URL)

	main_window := glfw.GetCocoaWindow(state.os.window)
	main_window->makeKeyAndOrderFront(nil)

	path := url->fileSystemRepresentation()

	fi, err := os.stat(string(path), context.temp_allocator)
	assert(err == nil)

	fullpath: string
	if fi.is_dir {
		name     := filepath.base(string(state.file_path[:]))
		fullpath  = filepath.join({fi.fullpath, name}, context.temp_allocator)
	} else {
		fullpath  = fi.fullpath
	}

	err = os.write_entire_file_or_err(fullpath, data)
	assert(err == nil)
}
