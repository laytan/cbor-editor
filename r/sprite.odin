package r

import intr "base:intrinsics"

import      "core:fmt"
import      "core:image"
import      "core:image/png"
import      "core:bytes"
import      "core:slice"
import      "core:math/linalg"

import      "vendor:wgpu"

MAX_SPRITES :: 2048

Sprite_Data :: struct {
	location, size, anchor, position, scale: [2]f32,
	rotation: f32,
	color:    u32,
}

Sprite :: struct {
    r: ^Renderer,

    zoom: f32,
    translation: [2]f32,

	constant_buffer:  wgpu.Buffer,

    spritesheet_width, spritesheet_height: f32,
	spritesheet:      wgpu.Texture,
	spritesheet_srv:  wgpu.TextureView,

	sprite_buffer: wgpu.Buffer,

	bindgroup_layout: wgpu.BindGroupLayout,
	bindgroup:        wgpu.BindGroup,

	sampler: wgpu.Sampler,

	module: wgpu.ShaderModule,

	pipeline_layout: wgpu.PipelineLayout,
	pipeline: wgpu.RenderPipeline,
}

Constants :: struct {
	texture_size:   [2]f32,
    transformation: matrix[4, 4]f32,
}
#assert(size_of(Constants) % 16 == 0)

sprite_init :: proc(s: ^Sprite, r: ^Renderer) {
	s.r = r

	///////////////////////////////////////////////////////////////////////////////////////////////

	spritesheet, err := png.load(#load("sprites/spritesheet.png"), {}, context.temp_allocator)
	fmt.assertf(err == nil, "spritesheet load error: %v", err)

	s.spritesheet_width, s.spritesheet_height = f32(spritesheet.width), f32(spritesheet.height)

	// Convert from RGBA to BGRA
	pixels := slice.reinterpret([]image.RGBA_Pixel, bytes.buffer_to_bytes(&spritesheet.pixels))
	for &pixel in pixels {
		pixel = pixel.bgra
	}

	///////////////////////////////////////////////////////////////////////////////////////////////

	if s.zoom == 0 {
		s.zoom = 1
	}

	w, h := f32(s.r.config.width), f32(s.r.config.height)
	transformation := linalg.matrix_ortho3d(0, w, h, 0, -1, 1) * linalg.matrix4_scale(s.zoom)
	transformation *= linalg.matrix4_translate_f32({s.translation.x, s.translation.y, 0})

	///////////////////////////////////////////////////////////////////////////////////////////////

	constants := Constants{ 
		texture_size   = { 1. / s.spritesheet_width, 1. / s.spritesheet_height },
		transformation = transformation,
	}
	s.constant_buffer = wgpu.DeviceCreateBuffer(r.device, &{
		label = "Constants",
		usage = { .Uniform, .CopyDst },
		size  = size_of(constants),
	})
	wgpu.QueueWriteBuffer(r.queue, s.constant_buffer, 0, &constants, size_of(constants))

	///////////////////////////////////////////////////////////////////////////////////////////////

	s.spritesheet = wgpu.DeviceCreateTexture(r.device, &{
		usage         = { .CopyDst, .TextureBinding },
		dimension     = ._2D,
		size          = { u32(spritesheet.width), u32(spritesheet.height), 1 },
		format        = .BGRA8Unorm,
		mipLevelCount = 1,
		sampleCount   = 1,
	})

	wgpu.QueueWriteTexture(
		r.queue,
		&{
			texture  = s.spritesheet,
		},
		raw_data(pixels),
		uint(spritesheet.width*spritesheet.height * size_of(u32)),
		&{
			bytesPerRow  = u32(spritesheet.width) * size_of(u32),
			rowsPerImage = u32(spritesheet.height),
		},
		&{
			width              = u32(spritesheet.width),
			height             = u32(spritesheet.height),
			depthOrArrayLayers = 1,
		},
	)

	s.spritesheet_srv = wgpu.TextureCreateView(s.spritesheet, nil)

	///////////////////////////////////////////////////////////////////////////////////////////////

	s.sprite_buffer = wgpu.DeviceCreateBuffer(r.device, &{
		label = "Sprites",
		usage = { .CopyDst, .Storage },
		size  = size_of(Sprite_Data) * MAX_SPRITES,
	})

	///////////////////////////////////////////////////////////////////////////////////////////////

	s.sampler = wgpu.DeviceCreateSampler(r.device, &{
		addressModeU  = .ClampToEdge,
		addressModeV  = .ClampToEdge,
		addressModeW  = .ClampToEdge,
		magFilter     = .Linear,
		minFilter     = .Linear,
		mipmapFilter  = .Linear,
		lodMinClamp   = 0,
		lodMaxClamp   = 1,
		compare       = .Undefined,
		maxAnisotropy = 1,
	})

	///////////////////////////////////////////////////////////////////////////////////////////////

	s.bindgroup_layout = wgpu.DeviceCreateBindGroupLayout(r.device, &{
		entryCount = 4,
		entries    = raw_data([]wgpu.BindGroupLayoutEntry{
			{
				binding    = 0,
				visibility = { .Vertex, .Fragment },
				buffer     = {
					type           = .Uniform,
					minBindingSize = size_of(constants),
				},
			},
			{
				binding    = 1,
				visibility = { .Vertex },
				buffer     = {
					type           = .ReadOnlyStorage,
					minBindingSize = size_of(Sprite_Data) * MAX_SPRITES,
				},
			},
			{
				binding    = 2,
				visibility = { .Fragment },
				texture    = {
					sampleType    = .Float,
					viewDimension = ._2D,
					multisampled  = false,
				},
			},
			{
				binding    = 3,
				visibility = { .Fragment },
				sampler    = {
					type = .Filtering,
				},
			},
		}),
	})

	s.bindgroup = wgpu.DeviceCreateBindGroup(r.device, &{
		layout     = s.bindgroup_layout,
		entryCount = 4,
		entries    = raw_data([]wgpu.BindGroupEntry{
			{
				binding = 0,
				buffer  = s.constant_buffer,
				size    = size_of(constants),
			},
			{
				binding = 1,
				buffer  = s.sprite_buffer,
				size    = size_of(Sprite_Data) * MAX_SPRITES,
			},
			{
				binding     = 2,
				textureView = s.spritesheet_srv,
			},
			{
				binding = 3,
				sampler = s.sampler,
			},
		}),
	})

	///////////////////////////////////////////////////////////////////////////////////////////////

	s.module = wgpu.DeviceCreateShaderModule(r.device, &{
		nextInChain = &wgpu.ShaderModuleWGSLDescriptor{
			sType = .ShaderModuleWGSLDescriptor,
			code  = #load("sprite.wgsl"),
		},
	})

	///////////////////////////////////////////////////////////////////////////////////////////////

	s.pipeline_layout = wgpu.DeviceCreatePipelineLayout(r.device, &{
		bindGroupLayoutCount = 1,
		bindGroupLayouts     = &s.bindgroup_layout,
	})
	s.pipeline = wgpu.DeviceCreateRenderPipeline(r.device, &{
		layout = s.pipeline_layout,
		vertex = {
			module     = s.module,
			entryPoint = "vs",
		},
		fragment = &{
			module      = s.module,
			entryPoint  = "ps",
			targetCount = 1,
			targets     = &wgpu.ColorTargetState{
				format = .BGRA8Unorm,
				blend = &{
					color = {
						srcFactor = .One,
						dstFactor = .OneMinusSrcAlpha,
						operation = .Add,
					},
					alpha = {
						srcFactor = .Zero,
						dstFactor = .One,
						operation = .Add,
					},
				},
				writeMask = wgpu.ColorWriteMaskFlags_All,
			},
		},
		primitive = {
			topology = .TriangleStrip,

		},
		multisample = {
			count = 1,
			mask  = 0xFFFFFFFF,
		},
	})

	///////////////////////////////////////////////////////////////////////////////////////////////
}

sprite_resize :: proc(s: ^Sprite) {
	// TODO: DPI
	w, h := f32(s.r.config.width), f32(s.r.config.height)
	transformation := linalg.matrix_ortho3d(0, w, h, 0, -1, 1) * linalg.matrix4_scale(s.zoom)
	transformation *= linalg.matrix4_translate_f32({s.translation.x, s.translation.y, 0})

	constants := Constants{ 
		texture_size   = { 1. / s.spritesheet_width, 1. / s.spritesheet_height },
		transformation = transformation,
	}
	wgpu.QueueWriteBuffer(s.r.queue, s.constant_buffer, 0, &constants, size_of(constants))
}

sprite_render :: proc(s: ^Sprite, sprites: []Sprite_Data) {
	assert(len(sprites) <= MAX_SPRITES)

	///////////////////////////////////////////////////////////////////////////////////////////////

	wgpu.QueueWriteBuffer(s.r.queue, s.sprite_buffer, 0, raw_data(sprites), uint(size_of(Sprite_Data)*len(sprites)))

	///////////////////////////////////////////////////////////////////////////////////////////////

	encoder := wgpu.DeviceCreateCommandEncoder(s.r.device, nil)
	pass    := wgpu.CommandEncoderBeginRenderPass(encoder, &{
		colorAttachmentCount = 1,
		colorAttachments = &wgpu.RenderPassColorAttachment{
			view       = s.r.curr_view,
			loadOp     = .Load,
			storeOp    = .Store,
			depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
		},
	})
	defer wgpu.CommandEncoderRelease(encoder)

	wgpu.RenderPassEncoderSetPipeline(pass, s.pipeline)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, s.bindgroup)

	///////////////////////////////////////////////////////////////////////////////////////////////

	wgpu.RenderPassEncoderDraw(pass, 4, u32(len(sprites)), 0, 0)

	///////////////////////////////////////////////////////////////////////////////////////////////

	wgpu.RenderPassEncoderEnd(pass)
	wgpu.RenderPassEncoderRelease(pass)

	command_buffer := wgpu.CommandEncoderFinish(encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)
	wgpu.QueueSubmit(s.r.queue, {command_buffer})
}
