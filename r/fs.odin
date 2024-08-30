package r

import intr "base:intrinsics"

import      "core:fmt"
import      "core:math/linalg"
import      "core:strings"
import sa   "core:container/small_array"

import fs   "vendor:fontstash"
import      "vendor:wgpu"

DEFAULT_FONT_ATLAS_SIZE :: 512
MAX_FONT_INSTANCES      :: 8192

Font_Renderer :: struct {
	using m: ^Renderer,

    fs: fs.FontContext,
    // NOTE: this could be made a dynamic array and employ a check if the gpu buffer needs to grow.
    font_instances:     sa.Small_Array(MAX_FONT_INSTANCES, Font_Instance),
    font_instances_buf: wgpu.Buffer,
    font_index_buf:     wgpu.Buffer,

    module: wgpu.ShaderModule,

    atlas_texture:      wgpu.Texture,
    atlas_texture_view: wgpu.TextureView,

    pipeline_layout: wgpu.PipelineLayout,
    pipeline:        wgpu.RenderPipeline,

    const_buffer: wgpu.Buffer,

    sampler: wgpu.Sampler,

    bind_group_layout: wgpu.BindGroupLayout,
    bind_group:        wgpu.BindGroup,
}

Font_Instance :: struct {
    pos_min: [2]f32,
    pos_max: [2]f32,
    uv_min:  [2]f32,
    uv_max:  [2]f32,
    color:   [4]u8,
}

Text_Align_Horizontal :: enum {
    Left   = int(fs.AlignHorizontal.LEFT),
    Center = int(fs.AlignHorizontal.CENTER),
    Right  = int(fs.AlignHorizontal.RIGHT),
}

Text_Align_Vertical :: enum {
    Top      = int(fs.AlignVertical.TOP),
    Middle   = int(fs.AlignVertical.MIDDLE),
    Bottom   = int(fs.AlignVertical.BOTTOM),
    Baseline = int(fs.AlignVertical.BASELINE),
}

Font :: enum {
    Default,
	UI,
}

@(rodata)
fonts := [Font][]byte{
    .Default = #load("fonts/SourceCodePro-500-100.ttf"),
	.UI      = #load("fonts/NotoSans-500-100.ttf"),
}

fs_init :: proc(r: ^Font_Renderer, m: ^Renderer) {
	r.m = m

	fs.Init(&r.fs, DEFAULT_FONT_ATLAS_SIZE, DEFAULT_FONT_ATLAS_SIZE, .TOPLEFT)

	for font in Font {
		fs.AddFontMem(&r.fs, fmt.enum_value_to_string(font) or_else unreachable(), fonts[font], freeLoadedData=false)
	}

	// This font has literally everything, just use it as a fallback for all others.
	// fallback := fs.AddFontMem(&r.fs, "arial", #load("/System/Library/Fonts/Supplemental/Arial Unicode.ttf"), freeLoadedData=false)
	// for font in Font {
	// 	fs.AddFallbackFont(&r.fs, int(font), fallback)
	// }

	r.font_instances_buf = wgpu.DeviceCreateBuffer(r.device, &{
		label = "Font Instance Buffer",
		usage = { .Vertex, .CopyDst },
		size = size_of(r.font_instances.data),
	})

	r.font_index_buf = wgpu.DeviceCreateBufferWithData(r.device, &{
		label = "Font Index Buffer",
		usage = { .Index, .Uniform },
	}, []u32{0, 1, 2, 1, 2, 3})

	r.const_buffer = wgpu.DeviceCreateBuffer(r.device, &{
		label = "Constant buffer",
		usage = { .Uniform, .CopyDst },
		size  = size_of(matrix[4, 4]f32),
	})

	r.sampler = wgpu.DeviceCreateSampler(r.device, &{
		addressModeU  = .ClampToEdge,
		addressModeV  = .ClampToEdge,
		addressModeW  = .ClampToEdge,
		magFilter     = .Linear,
		minFilter     = .Linear,
		mipmapFilter  = .Linear,
		lodMinClamp   = 0,
		lodMaxClamp   = 32,
		compare       = .Undefined,
		maxAnisotropy = 1,
	})

	r.bind_group_layout = wgpu.DeviceCreateBindGroupLayout(r.device, &{
		entryCount = 3,
		entries = raw_data([]wgpu.BindGroupLayoutEntry{
			{
				binding = 0,
				visibility = { .Fragment },
				sampler = {
					type = .Filtering,
				},
			},
			{
				binding = 1,
				visibility = { .Fragment },
				texture = {
					sampleType = .Float,
					viewDimension = ._2D,
					multisampled = false,
				},
			},
			{
				binding = 2,
				visibility = { .Vertex },
				buffer = {
					type = .Uniform,
					minBindingSize = size_of(matrix[4, 4]f32),
				},
			},
		}),
	})

	fs_create_atlas(r)

	r.module = wgpu.DeviceCreateShaderModule(r.device, &{
		nextInChain = &wgpu.ShaderModuleWGSLDescriptor{
			sType = .ShaderModuleWGSLDescriptor,
			code  = #load("fs.wgsl"),
		},
	})

	r.pipeline_layout = wgpu.DeviceCreatePipelineLayout(r.device, &{
		bindGroupLayoutCount = 1,
		bindGroupLayouts = &r.bind_group_layout,
	})
	r.pipeline = wgpu.DeviceCreateRenderPipeline(r.device, &{
		layout = r.pipeline_layout,
		vertex = {
			module = r.module,
			entryPoint = "vs_main",
			bufferCount = 1,
			buffers = raw_data([]wgpu.VertexBufferLayout{
				{
					arrayStride = size_of(Font_Instance),
					stepMode    = .Instance,
					attributeCount = 5,
					attributes = raw_data([]wgpu.VertexAttribute{
						{
							format         = .Float32x2,
							shaderLocation = 0,
						},
						{
							format         = .Float32x2,
							shaderLocation = 1,
							offset         = 8,
						},
						{
							format         = .Float32x2,
							shaderLocation = 2,
							offset         = 16,
						},
						{
							format         = .Float32x2,
							shaderLocation = 3,
							offset         = 24,
						},
						{
							format         = .Uint32,
							shaderLocation = 4,
							offset         = 32,
						},
					}),
				},
			}),
		},
		fragment = &{
			module = r.module,
			entryPoint = "fs_main",
			targetCount = 1,
			targets = &wgpu.ColorTargetState{
				format = .BGRA8Unorm,
				blend = &{
					alpha = {
						srcFactor = .SrcAlpha,
						dstFactor = .OneMinusSrcAlpha,
						operation = .Add,
					},
					color = {
						srcFactor = .SrcAlpha,
						dstFactor = .OneMinusSrcAlpha,
						operation = .Add,
					},
				},
				writeMask = wgpu.ColorWriteMaskFlags_All,
			},
		},
		primitive = {
			topology  = .TriangleList,
			cullMode  = .None,
		},
		multisample = {
			count = 1,
			mask = 0xFFFFFFFF,
		},
	})

	fs_write_consts(r)
}

fs_resize :: proc(r: ^Font_Renderer) {
	fs_write_consts(r)
}

@(private="file")
fs_write_consts :: proc(r: ^Font_Renderer) {
	// Transformation matrix to convert from screen to device pixels and scale based on DPI.
	fw, fh := f32(r.screen_width), f32(r.screen_height)
	fmt.println(fw, fh)
	transform := linalg.matrix_ortho3d(0, fw, fh, 0, -1, 1) * linalg.matrix4_scale(1/r.dpi)

	wgpu.QueueWriteBuffer(r.queue, r.const_buffer, 0, &transform, size_of(transform))
}

@(private="file")
fs_create_atlas :: proc(r: ^Font_Renderer) {
	r.atlas_texture = wgpu.DeviceCreateTexture(r.device, &{
		usage = { .TextureBinding, .CopyDst },
		dimension = ._2D,
		size = { u32(r.fs.width), u32(r.fs.height), 1 },
		format = .R8Unorm,
		mipLevelCount = 1,
		sampleCount = 1,
	})
	r.atlas_texture_view = wgpu.TextureCreateView(r.atlas_texture, nil)

	r.bind_group = wgpu.DeviceCreateBindGroup(r.device, &{
		layout = r.bind_group_layout,
		entryCount = 3,
		entries = raw_data([]wgpu.BindGroupEntry{
			{
				binding = 0,
				sampler = r.sampler,
			},
			{
				binding = 1,
				textureView = r.atlas_texture_view,
			},
			{
				binding = 2,
				buffer = r.const_buffer,
				size = size_of(matrix[4, 4]f32),
			},
		}),
	})

	fs_write_atlas(r)
}

@(private="file")
fs_write_atlas :: proc(r: ^Font_Renderer) {
	wgpu.QueueWriteTexture(
		r.queue,
		&{ texture = r.atlas_texture },
		raw_data(r.fs.textureData),
		uint(r.fs.width * r.fs.height),
		&{
			bytesPerRow  = u32(r.fs.width),
			rowsPerImage = u32(r.fs.height),
		},
		&{ u32(r.fs.width), u32(r.fs.height), 1 },
	)
}

fs_render :: proc(r: ^Font_Renderer) {
	command_encoder := wgpu.DeviceCreateCommandEncoder(r.device, nil)
	defer wgpu.CommandEncoderRelease(command_encoder)

	render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
		command_encoder, &{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment{
				view       = r.curr_view,
				loadOp     = .Load,
				storeOp    = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			},
		},
	)

	if (
		wgpu.TextureGetHeight(r.atlas_texture) != u32(r.fs.height) ||
		wgpu.TextureGetWidth(r.atlas_texture)  != u32(r.fs.width)
	) {
		fmt.println("atlas has grown to", r.fs.width, r.fs.height)
		wgpu.TextureViewRelease(r.atlas_texture_view)
		wgpu.TextureRelease(r.atlas_texture)
		wgpu.BindGroupRelease(r.bind_group)
		fs_create_atlas(r)
		fs.__dirtyRectReset(&r.fs)
	} else {
		dirty_texture := r.fs.dirtyRect[0] < r.fs.dirtyRect[2] && r.fs.dirtyRect[1] < r.fs.dirtyRect[3]
		if dirty_texture {

			// NOTE: could technically only update the part of the texture that changed,
			// seems non-trivial though.

			fmt.println("atas is dirty, updating")
			fs_write_atlas(r)
			fs.__dirtyRectReset(&r.fs)
		}
	}

	if r.font_instances.len > 0 {
		wgpu.QueueWriteBuffer(
			r.queue,
			r.font_instances_buf,
			0,
			&r.font_instances.data,
			uint(r.font_instances.len) * size_of(Font_Instance),
		)

		wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, r.pipeline)
		wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, r.bind_group)

		wgpu.RenderPassEncoderSetVertexBuffer(render_pass_encoder, 0, r.font_instances_buf, 0, u64(r.font_instances.len) * size_of(Font_Instance))
		wgpu.RenderPassEncoderSetIndexBuffer(render_pass_encoder, r.font_index_buf, .Uint32, 0, wgpu.BufferGetSize(r.font_index_buf))

		wgpu.RenderPassEncoderDrawIndexed(render_pass_encoder, indexCount=6, instanceCount=u32(r.font_instances.len), firstIndex=0, baseVertex=0, firstInstance=0)

		wgpu.RenderPassEncoderEnd(render_pass_encoder)

		sa.clear(&r.font_instances)
		r.fs.state_count = 0
	}
	wgpu.RenderPassEncoderRelease(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(r.queue, { command_buffer })
}

fs_apply :: proc(
	r: ^Font_Renderer,
    size: f32 = 36,
    blur: f32 = 0,
    spacing: f32 = 0,
    font: Font = .Default,
    align_h: Text_Align_Horizontal = .Left,
    align_v: Text_Align_Vertical   = .Baseline,
) {
	state := fs.__getState(&r.fs)
	state^ = {
		size    = size * r.dpi,
		blur    = blur,
		spacing = spacing,
		font    = int(font),
		ah      = fs.AlignHorizontal(align_h),
		av      = fs.AlignVertical(align_v),
	}
}

fs_lh :: proc(r: ^Font_Renderer) -> f32 {
	_, _, lh := fs.VerticalMetrics(&r.fs)
	return lh
}

fs_width :: proc(r: ^Font_Renderer, text: string) -> f32 {
	assert(strings.count(text, "\n") == 0)
	actual_text, _ := strings.replace_all(text, "\t", "    ", context.temp_allocator)
	return fs.TextBounds(&r.fs, actual_text)
}

fs_draw_text :: proc(
    r: ^Font_Renderer,
    text: string,
    pos: [2]f32,
    size: f32 = 36,
    color: [4]u8 = max(u8),
    blur: f32 = 0,
    spacing: f32 = 0,
    font: Font = .Default,
    align_h: Text_Align_Horizontal = .Left,
    align_v: Text_Align_Vertical   = .Baseline,
    x_inc: ^f32 = nil,
    y_inc: ^f32 = nil,
) {
	if len(text) == 0 {
		return
	}

	fs_apply(r, size, blur, spacing, font, align_h, align_v)

	_, _, lh := fs.VerticalMetrics(&r.fs)

	pos := pos

	iter_text := text
	for line in strings.split_lines_iterator(&iter_text) {
		actual_line, _ := strings.replace_all(line, "\t", "    ", context.temp_allocator)

		for iter := fs.TextIterInit(&r.fs, pos.x, pos.y, actual_line); true; {
			quad: fs.Quad
			fs.TextIterNext(&r.fs, &iter, &quad) or_break

			added := sa.append(
				&r.font_instances,
				Font_Instance {
					pos_min = {quad.x0, quad.y0},
					pos_max = {quad.x1, quad.y1},
					uv_min  = {quad.s0, quad.t0},
					uv_max  = {quad.s1, quad.t1},
					color   = color,
				},
			)

			fmt.assertf(added, "font instance buffer full")
		}

		pos.y += lh
	}

	if y_inc != nil {
		y_inc^ = pos.y
	}

	if x_inc != nil {
		last := r.font_instances.data[r.font_instances.len-1]
		x_inc^ = last.pos_max.x
	}
}
