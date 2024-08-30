package r

import intr "base:intrinsics"
import      "base:runtime"

import      "core:fmt"

import      "vendor:wgpu"

Renderer :: struct {
	instance: wgpu.Instance,
	surface:  wgpu.Surface,
	adapter:  wgpu.Adapter,
	device:   wgpu.Device,
	config:   wgpu.SurfaceConfiguration,

	queue:    wgpu.Queue,

	ctx:         runtime.Context,
	initialized: proc(),

	curr_texture: wgpu.SurfaceTexture,
	curr_view:    wgpu.TextureView,

	dpi: f32,
	screen_width, screen_height: u32,
}

init :: proc(
	r: ^Renderer,
	instance: wgpu.Instance,
	surface: wgpu.Surface,
	log_level: runtime.Logger_Level,
	width, height: u32,
	screen_width, screen_height: u32,
	dpi: f32,
	initialized: proc(),
) {
	r.ctx = context

	when ODIN_OS != .JS {
		wgpu.SetLogLevel(wgpu.ConvertLogLevel(log_level))
		wgpu.SetLogCallback(proc "c" (wgpulevel: wgpu.LogLevel, message: cstring, user: rawptr) {
			r := (^Renderer)(user)
			context = r.ctx
			logger := context.logger
			if logger.procedure == nil {
				return
			}

			level := wgpu.ConvertLogLevel(wgpulevel)
			if level < logger.lowest_level {
				return
			}

			logger.procedure(logger.data, level, string(message), logger.options, {})
		}, r)
	}

	r.initialized = initialized
	r.config.width, r.config.height = width, height
	r.dpi = dpi
	r.screen_width, r.screen_height = screen_width, screen_height

	r.instance = instance
	r.surface = surface

	wgpu.InstanceRequestAdapter(r.instance, &{
		compatibleSurface = r.surface,
		powerPreference   = .LowPower, // Don't need high performance for this.
	}, on_adapter, r)

	on_adapter :: proc "c" (status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: cstring, r: rawptr) {
		r := (^Renderer)(r)
		context = r.ctx
		if status != .Success || adapter == nil do fmt.panicf("request adapter failure: [%v] %s", status, message)
		r.adapter = adapter
		wgpu.AdapterRequestDevice(adapter, nil, on_device, r)
	}

	on_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: cstring, r: rawptr) {
		r := (^Renderer)(r)
		context = r.ctx
		if status != .Success || device == nil do fmt.panicf("request device failure: [%v] %s", status, message)
		r.device = device 

		r.config = wgpu.SurfaceConfiguration {
			device      = r.device,
			usage       = { .RenderAttachment },
			format      = .BGRA8Unorm,
			width       = r.config.width,
			height      = r.config.height,
			presentMode = .Fifo, // VSync.
			alphaMode   = .Opaque,
		}

		r.queue = wgpu.DeviceGetQueue(r.device)

		wgpu.SurfaceConfigure(r.surface, &r.config)

		r.initialized()
	}
}

resize :: proc(r: ^Renderer, width, height: u32, screen_width, screen_height: u32, dpi: f32) {
	r.config.width, r.config.height = width, height
	r.screen_width, r.screen_height = screen_width, screen_height
	r.dpi = dpi
	wgpu.SurfaceConfigure(r.surface, &r.config)
}

clear :: proc(r: ^Renderer, clear: wgpu.Color) {
	r.curr_texture = wgpu.SurfaceGetCurrentTexture(r.surface)
	r.curr_view = wgpu.TextureCreateView(r.curr_texture.texture)

	// NOTE: I've never hit this?
	assert(!r.curr_texture.suboptimal, "TODO")
	assert(r.curr_texture.status == .Success, "TODO")

	// NOTE: I guess it is a bad idea to create an entire pass for clearing the screen, it seems
	// the easiest right now though.

	encoder := wgpu.DeviceCreateCommandEncoder(r.device)
	defer wgpu.CommandEncoderRelease(encoder)

	pass := wgpu.CommandEncoderBeginRenderPass(encoder, &{
		colorAttachmentCount = 1,
		colorAttachments = raw_data([]wgpu.RenderPassColorAttachment{
			{
				view       = r.curr_view,
				loadOp     = .Clear,
				storeOp    = .Store,
				clearValue = clear,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			},
		}),
	})

	wgpu.RenderPassEncoderEnd(pass)
	wgpu.RenderPassEncoderRelease(pass)

	buffer := wgpu.CommandEncoderFinish(encoder)
	defer wgpu.CommandBufferRelease(buffer)

	wgpu.QueueSubmit(r.queue, {buffer})
}

present :: proc(r: ^Renderer) {
	wgpu.SurfacePresent(r.surface)
	wgpu.TextureViewRelease(r.curr_view)
	wgpu.TextureRelease(r.curr_texture.texture)
}
